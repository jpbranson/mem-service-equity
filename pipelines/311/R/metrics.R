# Metric computation for the 311 pipeline. Specs: specs/311/*.md.
#
# Every metric is computed per request type (`subgroup`) over rolling windows
# ending on the last complete day. Only requests inside the city limits,
# not excluded in normalization, and not near-duplicates are counted.

WINDOWS <- c("90d" = 90L, "12m" = 365L)

SPEC_VERSIONS <- c(median_business_days_to_close = "0.1", pct_within_target = "0.1",
                   reopen_rate = "0.1", requests_per_1000 = "0.2")

REOPEN_VARIANTS <- data.frame(
  variant = c("primary", "window_14d", "window_60d", "radius_25m", "radius_100m"),
  days = c(30L, 14L, 60L, 30L, 30L),
  meters = c(50, 50, 50, 25, 100))

base_records <- function(pts) {
  df <- if (inherits(pts, "sf")) sf::st_drop_geometry(pts) else pts
  df[is.na(df$exclusion) & is.na(df$duplicate_of) & df$in_city %in% TRUE, ]
}

window_range <- function(through, days) c(through - days + 1L, through)

geo_levels <- function() c("citywide", "zcta", "council_district", "super_district",
                             "reference_neighborhood")

# Apply `fun(sub_df)` -> one-row metric frame to every (request_type, geo_id)
# group of `df` for one geography level.
by_type_geo <- function(df, geo, fun) {
  ok <- !is.na(df[[geo]])
  df <- df[ok, , drop = FALSE]
  if (!nrow(df)) return(NULL)
  key <- paste(df$request_type, df[[geo]], sep = "\r")
  groups <- split(seq_len(nrow(df)), key)
  rows <- lapply(names(groups), function(k) {
    ix <- groups[[k]]
    r <- fun(df[ix, , drop = FALSE])
    r$subgroup <- df$request_type[ix[1]]
    r$geo_id <- as.character(df[[geo]][ix[1]])
    r
  })
  out <- do.call(rbind, rows)
  out$geo_type <- geo
  out
}

km_row <- function(time, event) {
  nb <- max(time, 0L) + 1L
  memequity::km_median_counts(0:(nb - 1L), tabulate(time[event] + 1L, nb),
                              tabulate(time[!event] + 1L, nb))
}

# ---- median business days to close -------------------------------------

median_input <- function(df, win) {
  d <- df[df$open_date >= win[1] & df$open_date <= win[2] & is.na(df$close_problem), ]
  d$time <- ifelse(d$closed, d$bd_to_close, d$age_bd)
  d$event <- d$closed
  d[!is.na(d$time), ]
}

compute_median <- function(df, through) {
  out <- list()
  for (w in names(WINDOWS)) {
    win <- window_range(through, WINDOWS[[w]])
    d <- median_input(df, win)
    for (g in geo_levels()) {
      r <- by_type_geo(d, g, function(s) km_row(s$time, s$event))
      if (is.null(r)) next
      r$window_start <- win[1]; r$window_end <- win[2]
      out[[length(out) + 1]] <- r
    }
  }
  res <- do.call(rbind, out)
  res$metric <- "median_business_days_to_close"
  res$variant <- "primary"
  res
}

# ---- share within target -------------------------------------------------

target_input <- function(df, targets, win, which) {
  t <- targets[!is.na(targets[[which]]), ]
  d <- df[df$request_type %in% t$request_type & df$open_date >= win[1] & df$open_date <= win[2] &
            is.na(df$close_problem), ]
  d$target <- t[[which]][match(d$request_type, t$request_type)]
  d <- d[!is.na(d$age_bd) & d$age_bd >= d$target, ]  # deadline day fully observed
  d$on_time <- d$closed & !is.na(d$bd_to_close) & d$bd_to_close <= d$target
  d
}

compute_target <- function(df, targets, through) {
  variants <- c(primary = "target_high_bd", lower_bound = "target_low_bd")
  out <- list()
  for (v in names(variants)) for (w in names(WINDOWS)) {
    win <- window_range(through, WINDOWS[[w]])
    d <- target_input(df, targets, win, variants[[v]])
    for (g in geo_levels()) {
      r <- by_type_geo(d, g, function(s) memequity::proportion_counts(sum(s$on_time), nrow(s)))
      if (is.null(r)) next
      r$window_start <- win[1]; r$window_end <- win[2]; r$variant <- v
      out[[length(out) + 1]] <- r
    }
  }
  if (!length(out)) return(NULL)
  res <- do.call(rbind, out)
  res$metric <- "pct_within_target"
  res
}

# ---- re-report ("reopen") rate -------------------------------------------

#' For each closed primary request, the number of days from its close to the
#' first later request of the same type, at each radius in `radii` (NA if none
#' within `max_days`).
rereport_days <- function(pts_all, primaries_idx, radii = c(25, 50, 100), max_days = 60) {
  xy <- memequity::xy_meters(pts_all)
  out <- matrix(NA_real_, nrow(pts_all), length(radii), dimnames = list(NULL, paste0("r", radii)))
  src <- primaries_idx[pts_all$closed[primaries_idx]]
  if (!length(src)) return(out)
  g <- as.integer(factor(pts_all$request_type))
  pr <- memequity::grid_pairs(xy[src, 1], xy[src, 2], xy[, 1], xy[, 2], max(radii),
                              ag = g[src], bg = g,
                              at = as.numeric(pts_all$close_date[src]),
                              bt = as.numeric(pts_all$open_date),
                              lag_min = 0, lag_max = max_days)
  if (!nrow(pr)) return(out)
  s <- src[pr$i]
  for (k in seq_along(radii)) {
    sel <- pr$dist <= radii[k]
    if (!any(sel)) next
    m <- tapply(pr$lag[sel], s[sel], min)
    out[as.integer(names(m)), k] <- m
  }
  out
}

compute_reopen <- function(pts, through) {
  df_all <- sf::st_drop_geometry(pts)
  # Re-reports can be any included, located, in-city request (duplicates
  # included: a re-report is by definition near an earlier request).
  pool <- which(is.na(df_all$exclusion) & df_all$in_city %in% TRUE & !is.na(df_all$longitude))
  pts_pool <- pts[pool, ]
  prim <- which(is.na(pts_pool$duplicate_of))
  rd <- rereport_days(pts_pool, prim)
  base <- sf::st_drop_geometry(pts_pool)[prim, ]
  rd <- rd[prim, , drop = FALSE]
  out <- list()
  for (vi in seq_len(nrow(REOPEN_VARIANTS))) {
    v <- REOPEN_VARIANTS[vi, ]
    col <- paste0("r", v$meters)
    base$reopened <- !is.na(rd[, col]) & rd[, col] <= v$days
    for (w in names(WINDOWS)) {
      win <- window_range(through, WINDOWS[[w]])
      d <- base[base$closed & base$close_date >= win[1] & base$close_date <= win[2] &
                  base$close_date <= through - v$days, ]
      for (g in geo_levels()) {
        r <- by_type_geo(d, g, function(s) memequity::proportion_counts(sum(s$reopened), nrow(s)))
        if (is.null(r)) next
        r$window_start <- win[1]; r$window_end <- win[2]; r$variant <- v$variant
        out[[length(out) + 1]] <- r
      }
    }
  }
  res <- do.call(rbind, out)
  res$metric <- "reopen_rate"
  list(metrics = res, rereport = cbind(base[, "sr_id", drop = FALSE], as.data.frame(rd)))
}

# ---- requests per 1,000 residents (demand) ---------------------------------

RATE_GEOS <- c("citywide", "zcta", "council_district", "super_district", "reference_neighborhood")
MIN_POPULATION <- 1000

#' Requests per 1,000 residents, for every request type seen in the window,
#' in every area with a population, including areas with no requests of that
#' type (a zero is a result). Same estimator as memequity::metric_rate(),
#' vectorized.
#'
#' @param populations named list: geo_type -> data.frame(geo_id, population),
#'   the residents of the part of each area inside the city.
compute_requests_per_1000 <- function(df, populations, through) {
  out <- list()
  for (w in names(WINDOWS)) {
    win <- window_range(through, WINDOWS[[w]])
    d <- df[df$open_date >= win[1] & df$open_date <= win[2], ]
    types <- sort(unique(d$request_type))
    if (!length(types)) next
    for (g in intersect(RATE_GEOS, names(populations))) {
      pop <- populations[[g]]
      counts <- table(factor(d$request_type, types), factor(d[[g]], pop$geo_id))
      r <- expand.grid(subgroup = types, geo_id = pop$geo_id, stringsAsFactors = FALSE)
      r$n <- as.integer(counts[cbind(r$subgroup, r$geo_id)])
      exposure <- pop$population[match(r$geo_id, pop$geo_id)]
      ci <- memequity::poisson_rate_ci(r$n, exposure, per = 1000)
      r$suppressed <- is.na(exposure) | exposure < MIN_POPULATION
      r$value <- ifelse(r$suppressed, NA_real_, ci$value)
      r$ci_low <- ifelse(r$suppressed, NA_real_, ci$ci_low)
      r$ci_high <- ifelse(r$suppressed, NA_real_, ci$ci_high)
      r$geo_type <- g
      r$window_start <- win[1]; r$window_end <- win[2]
      out[[length(out) + 1]] <- r
    }
  }
  res <- do.call(rbind, out)
  res$metric <- "requests_per_1000"
  res$variant <- "primary"
  res$metric_version <- SPEC_VERSIONS[["requests_per_1000"]]
  # For rates the reference is the citywide rate itself (D4).
  city <- res[res$geo_type == "citywide", ]
  key <- function(d) paste(d$subgroup, d$window_start, sep = "\r")
  res$citywide_median <- city$value[match(key(res), key(city))]
  res
}

# ---- citywide reference and assembly --------------------------------------

add_citywide_reference <- function(m) {
  city <- m[m$geo_type == "citywide", ]
  key <- function(d) paste(d$metric, d$variant, d$subgroup, d$window_start, sep = "\r")
  m$citywide_median <- city$value[match(key(m), key(city))]
  m
}

compute_metrics_311 <- function(pts, targets, through) {
  df <- base_records(pts)
  med <- compute_median(df, through)
  tgt <- compute_target(df, targets, through)
  reo <- compute_reopen(pts, through)
  m <- rbind(med, tgt, reo$metrics)
  m$metric_version <- SPEC_VERSIONS[m$metric]
  m <- add_citywide_reference(m)
  list(metrics = m, rereport = reo$rereport)
}
