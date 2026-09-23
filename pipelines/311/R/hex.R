# Address-level metrics on the H3 grid (plan section 9: precompute on hexes so
# the browser needs no server).
#
# For each resolution-9 cell (edge ~174 m) the "near this address" area is
# the cell plus its six neighbors (H3 grid disk k = 1, about 0.74 km^2,
# roughly a 0.3-mile radius). Per-cell counts are computed once and summed
# over each disk, so every estimate uses the same count-based estimators as
# the district metrics (DECISIONS.md D16).

library(data.table)

hex_disk_pairs <- function(cells, k = 1L) {
  disks <- h3jsr::get_disk(cells, ring_size = k)
  data.table(target = rep(cells, lengths(disks)), member = unlist(disks))
}

proportion_rows <- function(x, n, min_n = 30L) {
  ci <- memequity::wilson_ci(x, n)
  sup <- n < min_n
  data.table(value = ifelse(sup, NA_real_, x / n), ci_low = ifelse(sup, NA_real_, ci$ci_low),
             ci_high = ifelse(sup, NA_real_, ci$ci_high), n = as.integer(n), suppressed = sup)
}

hex_proportion <- function(d, flag, pairs) {
  # d: data.table with h3 and logical column `flag`.
  per <- d[, list(x = sum(get(flag)), n = .N), by = list(member = h3)]
  agg <- pairs[per, on = "member", nomatch = NULL][, list(x = sum(x), n = sum(n)), by = target]
  cbind(agg[, list(geo_id = target)], proportion_rows(agg$x, agg$n))
}

hex_km <- function(d, pairs) {
  # d: data.table with h3, integer time, logical event.
  per <- d[, list(e = sum(event), c = sum(!event)), by = list(member = h3, time)]
  agg <- pairs[per, on = "member", nomatch = NULL, allow.cartesian = TRUE][
    , list(e = sum(e), c = sum(c)), by = list(target, time)]
  res <- agg[, memequity::km_median_counts(time, e, c), by = target]
  setnames(res, "target", "geo_id")
  res
}

compute_hex_metrics <- function(pts, rereport, targets, headline, through) {
  df <- as.data.table(base_records(pts))
  df <- df[request_type %in% headline & !is.na(h3)]
  if (!nrow(df)) return(NULL)
  cells <- unique(df$h3)
  all_targets <- unique(unlist(h3jsr::get_disk(cells, ring_size = 1L)))
  pairs <- hex_disk_pairs(all_targets)
  out <- list()
  add <- function(r, metric, variant, subgroup, win) {
    if (is.null(r) || !nrow(r)) return()
    r[, `:=`(metric = metric, variant = variant, subgroup = subgroup,
             window_start = win[1], window_end = win[2], geo_type = "h3_9")]
    out[[length(out) + 1]] <<- r
  }
  rr <- as.data.table(rereport)
  for (w in names(WINDOWS)) {
    win <- window_range(through, WINDOWS[[w]])
    for (ty in headline) {
      d <- df[request_type == ty]
      md <- as.data.table(median_input(as.data.frame(d), win))
      if (nrow(md)) add(hex_km(md[, list(h3, time = as.integer(time), event)], pairs),
                        "median_business_days_to_close", "primary", ty, win)
      if (ty %in% targets$request_type[!is.na(targets$target_high_bd)]) {
        td <- as.data.table(target_input(as.data.frame(d), targets, win, "target_high_bd"))
        if (nrow(td)) add(hex_proportion(td, "on_time", pairs), "pct_within_target", "primary", ty, win)
      }
      cd <- d[closed & close_date >= win[1] & close_date <= win[2] & close_date <= through - 30L]
      cd <- merge(cd, rr[, list(sr_id, r50)], by = "sr_id", all.x = TRUE)
      cd[, reopened := !is.na(r50) & r50 <= 30]
      if (nrow(cd)) add(hex_proportion(cd, "reopened", pairs), "reopen_rate", "primary", ty, win)
    }
  }
  res <- rbindlist(out, use.names = TRUE)
  as.data.frame(res)
}
