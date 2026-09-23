# Metric computation for the 311 pipeline. Specs: specs/311/*.md.
#
# Every metric is computed per request type (`subgroup`) over rolling windows
# ending on the last complete day. Only requests inside the city limits,
# not excluded in normalization, and not near-duplicates are counted.

WINDOWS <- c("90d" = 90L, "12m" = 365L)

SPEC_VERSIONS <- c(median_business_days_to_close = "0.1", pct_within_target = "0.1",
                   reopen_rate = "0.1")

REOPEN_VARIANTS <- data.frame(
  variant = c("primary", "window_14d", "window_60d", "radius_25m", "radius_100m"),
  days = c(30L, 14L, 60L, 30L, 30L),
  meters = c(50, 50, 50, 25, 100))

base_records <- function(pts) {
  df <- if (inherits(pts, "sf")) sf::st_drop_geometry(pts) else pts
  df[is.na(df$exclusion) & is.na(df$duplicate_of) & df$in_city %in% TRUE, ]
}

window_range <- function(through, days) c(through - days + 1L, through)

geo_levels <- function() c("citywide", "zcta", "council_district", "super_district")

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

#' For each closed primary request, find the first later request of the same
#' type within `max_m` meters; returns per-request the smallest
#' (days-after-close) at each radius in `radii`.
rereport_days <- function(pts_all, primaries_idx, radii = c(25, 50, 100)) {
  xy <- sf::st_coordinates(sf::st_transform(sf::st_geometry(pts_all), memequity::MSE_CRS_METERS))
  out <- matrix(NA_real_, nrow(pts_all), length(radii), dimnames = list(NULL, paste0("r", radii)))
  types <- unique(pts_all$request_type[primaries_idx])
  for (ty in types) {
    all_ix <- which(pts_all$request_type == ty)
    src_ix <- intersect(primaries_idx, all_ix)
    src_ix <- src_ix[pts_all$closed[src_ix]]
    if (!length(src_ix)) next
    nb <- sf::st_is_within_distance(sf::st_geometry(pts_all)[src_ix], sf::st_geometry(pts_all)[all_ix],
                                    dist = max(radii))
    i <- rep(seq_along(src_ix), lengths(nb))
    if (!length(i)) next
    j <- all_ix[unlist(nb)]
    s <- src_ix[i]
    lag <- as.numeric(pts_all$open_date[j] - pts_all$close_date[s])
    dist <- sqrt((xy[s, 1] - xy[j, 1])^2 + (xy[s, 2] - xy[j, 2])^2)
    keep <- j != s & lag > 0
    for (k in seq_along(radii)) {
      sel <- keep & dist <= radii[k]
      if (!any(sel)) next
      m <- tapply(lag[sel], s[sel], min)
      out[as.integer(names(m)), k] <- m
    }
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
