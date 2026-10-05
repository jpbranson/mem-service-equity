# One analysis specification: a window of opened requests, a neighbor
# definition, and the resulting tract ratios, global and local statistics.

run_spec <- function(x, tracts_geom, p, from, to, neighbors = c("contiguity", "knn"),
                     exclude_categories = character()) {
  neighbors <- match.arg(neighbors)
  d <- window_requests(x$sr, from, to)
  if (length(exclude_categories)) {
    fl <- attr(d, "flow")
    drop <- d$category %in% exclude_categories
    d <- d[!drop, ]
    attr(d, "flow") <- c(fl, in_excluded_categories = sum(drop))
  }
  thr <- type_thresholds(d, min_n = p$min_type_n)
  e <- flag_slow(d, thr)
  t <- area_ratios(e, "tract", min_n = p$min_tract_n)
  t <- merge(data.frame(geo_id = tracts_geom$geo_id, stringsAsFactors = FALSE), t,
             by = "geo_id", all.x = TRUE)
  t$n[is.na(t$n)] <- 0L
  t$suppressed[is.na(t$suppressed)] <- TRUE
  keep <- tracts_geom$geo_id %in% t$geo_id[!t$suppressed]
  g <- tracts_geom[keep, ]
  a <- t[match(g$geo_id, t$geo_id), ]
  nb <- if (neighbors == "contiguity") nb_contiguity(g, p$contiguity_tol_m) else nb_knn(g, p$knn_k)
  eb <- eb_standardize(a$observed, a$expected, a$null_var)
  gm <- moran_global(eb$z, nb, nsim = p$nsim_global, seed = p$seed)
  lc <- lisa(eb$z, nb, nsim = p$nsim_local, seed = p$seed, alpha = p$alpha)
  a <- cbind(a, eb_z = eb$z, eb_smoothed = eb$smoothed, lc[, c("Ii", "lag", "p", "q", "quadrant", "class")],
             n_neighbors = lengths(nb))
  t <- merge(t, a[, c("geo_id", "eb_z", "eb_smoothed", "Ii", "lag", "p", "q", "quadrant", "class",
                      "n_neighbors")], by = "geo_id", all.x = TRUE)
  t$class[t$suppressed] <- "suppressed"
  flow <- c(attr(d, "flow"),
            timing_records = nrow(d),
            in_excluded_types = sum(!d$request_type %in% thr$request_type[thr$status == "ok"]),
            not_yet_observable = sum(d$request_type %in% thr$request_type[thr$status == "ok"]) - nrow(e),
            analysed = nrow(e),
            in_suppressed_tracts = sum(e$tract %in% t$geo_id[t$suppressed]))
  list(from = from, to = to, neighbors = neighbors, requests = d, eligible = e, thresholds = thr,
       tracts = t, nb = nb, nb_ids = g$geo_id, eb = eb[c("b", "a")], moran = gm,
       islands_linked = g$geo_id[attr(nb, "islands_linked")], flow = flow)
}

# Tracts grouped by their local-Moran result in the primary specification.
cluster_groups <- function(spec) {
  t <- spec$tracts
  g <- ifelse(t$class == "HH", "slow_core", ifelse(t$class == "LL", "fast_core",
         ifelse(t$class == "suppressed", NA, "other")))
  stats::setNames(g, t$geo_id)
}

# Every tract with requests in one "citywide" group (including suppressed ones).
all_city <- function(spec) {
  u <- unique(stats::na.omit(spec$requests$tract))
  stats::setNames(rep("citywide", length(u)), u)
}

# Pooled observed/expected for each group, with a Wilson interval.
group_ratios <- function(spec, groups) {
  e <- spec$eligible
  e$group <- groups[e$tract]
  e <- e[!is.na(e$group), ]
  do.call(rbind, lapply(split(e, e$group), function(s) {
    ci <- memequity::wilson_ci(sum(s$slow), nrow(s))
    pe <- mean(s$p_type)
    data.frame(group = s$group[1], tracts = length(unique(s$tract)), n = nrow(s),
               observed_share = mean(s$slow), expected_share = pe, ratio = mean(s$slow) / pe,
               ci_low = ci$ci_low / pe, ci_high = ci$ci_high / pe)
  }))
}

# Neighborhood context for each group: ACS measures (with margins of error,
# pooled from tract components), permit and demolition rates per 1,000
# housing units, and 311 requests per 1,000 residents.
group_context <- function(x, spec, groups, p) {
  gd <- memequity::geography_dir()
  comp <- memequity::load_demographic_components("tract", gd)
  comp$group <- groups[comp$geo_id]
  comp <- comp[!is.na(comp$group), ]
  pooled <- stats::aggregate(cbind(estimate, m2 = moe^2) ~ group + variable, data = comp, FUN = sum)
  city <- memequity::load_demographic_components("citywide", gd)
  pooled <- rbind(data.frame(group = pooled$group, variable = pooled$variable, estimate = pooled$estimate,
                             m2 = pooled$m2),
                  data.frame(group = "citywide", variable = city$variable, estimate = city$estimate,
                             m2 = city$moe^2))
  comps <- data.frame(geo_type = "group", geo_id = pooled$group, variable = pooled$variable,
                      estimate = pooled$estimate, moe = sqrt(pooled$m2), stringsAsFactors = FALSE)
  dem <- memequity::derive_demographics(comps, memequity::demographic_measures(gd))
  dem <- dem[dem$measure %in% p$context_measures, c("geo_id", "measure", "value", "moe")]
  names(dem)[1] <- "group"
  dem$ci_low <- dem$value - dem$moe; dem$ci_high <- dem$value + dem$moe   # ACS 90% MOE
  dem$interval <- "ACS 90% margin of error"

  hu <- stats::setNames(pooled$estimate[pooled$variable == "B25002_001"],
                        pooled$group[pooled$variable == "B25002_001"])
  pop <- stats::setNames(pooled$estimate[pooled$variable == "B01003_001"],
                         pooled$group[pooled$variable == "B01003_001"])
  rate_rows <- function(tract, measure, per_what) {
    grp <- groups[tract]
    cnt <- c(table(factor(grp, c(unique(stats::na.omit(groups))))), citywide = length(tract))
    den <- if (per_what == "hu") hu[names(cnt)] else pop[names(cnt)]
    ci <- memequity::poisson_rate_ci(as.numeric(cnt), den, per = 1000)
    data.frame(group = names(cnt), measure = measure, value = ci$value, moe = NA_real_,
               ci_low = ci$ci_low, ci_high = ci$ci_high, interval = "95% Poisson interval",
               count = as.numeric(cnt), stringsAsFactors = FALSE)
  }
  pm <- x$permits
  pm <- pm[is.na(pm$exclusion) & pm$in_city %in% TRUE & pm$sector %in% "residential" &
             pm$issue_date >= p$permits_from & pm$issue_date <= p$permits_to, ]
  rows <- list(rate_rows(pm$tract[pm$category == "renovation"], "renovation_permits_per_1000_hu", "hu"),
               rate_rows(pm$tract[pm$category == "new"], "new_home_permits_per_1000_hu", "hu"))
  if (!is.null(x$demolitions)) {
    dm <- x$demolitions
    dm <- dm[is.na(dm$exclusion) & dm$in_city %in% TRUE & dm$issue_date >= p$demolitions_from &
               dm$issue_date <= p$demolitions_to, ]
    rows[[length(rows) + 1]] <- rate_rows(dm$tract, "demolitions_per_1000_hu", "hu")
  }
  sr <- x$sr
  sr <- sr[is.na(sr$exclusion) & is.na(sr$duplicate_of) & sr$in_city %in% TRUE &
             sr$open_date >= spec$from & sr$open_date <= spec$to, ]
  rows[[length(rows) + 1]] <- rate_rows(sr$tract, "requests_per_1000_residents", "pop")
  dem$count <- NA_real_
  rbind(dem, do.call(rbind, rows))
}
