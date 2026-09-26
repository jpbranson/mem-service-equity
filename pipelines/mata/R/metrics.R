# Metric computation for the MATA pipeline. Specs: specs/mata/*.md.
#
# Units: a scheduled trip (ghost_bus_rate), an inferred arrival at a
# timepoint stop (on_time_pct) and a gap between consecutive arrivals
# (peak_headway_ratio). Geographies: citywide, route, stop, and the H3
# resolution-8 cell of the stop.

SPEC_VERSIONS <- c(ghost_bus_rate = "0.2", on_time_pct = "0.2", peak_headway_ratio = "0.2")
WINDOW_DAYS <- c("30d" = 30L, "90d" = 90L)
MATCH_RATE_FLOOR <- 0.85
ON_TIME <- list(primary = c(-60, 300), window_0_10 = c(0, 600))
PEAKS <- list(c(6, 9), c(15, 18))          # local hours, weekdays
MAX_PEAK_HEADWAY_S <- 30 * 60

#' Classify each measurable scheduled trip (DECISIONS.md: spec ghost_bus_rate).
#' - observed: a vehicle reported on the trip.
#' - ghost: not observed, but a vehicle reported on another trip of the same
#'   block that day. The bus was out and this trip did not happen.
#' - unobserved: nothing from the block reported all day. Possibly a dead
#'   tracker, so neither run nor missed.
classify_trips <- function(m) {
  m <- copy(m)
  seen_blocks <- unique(m[observed == TRUE & !is.na(block_id) & block_id != "", .(service_date, block_id)])
  seen_blocks[, block_seen := TRUE]
  m <- merge(m, seen_blocks, by = c("service_date", "block_id"), all.x = TRUE)
  m[is.na(block_seen), block_seen := FALSE]
  m[, status := fifelse(observed, "observed", fifelse(block_seen, "ghost", "unobserved"))]
  m[]
}

# Assign rows (with route_id and stop_id) to each geography; returns a
# data.table with geo_type and geo_id, rows duplicated once per geography.
explode_geos <- function(d, stop_cells) {
  city <- copy(d)[, `:=`(geo_type = "citywide", geo_id = "4748000")]
  route <- copy(d)[, `:=`(geo_type = "route", geo_id = route_id)]
  out <- list(city, route)
  if ("stop_id" %in% names(d)) {
    out[[3]] <- copy(d)[, `:=`(geo_type = "stop", geo_id = stop_id)]
    h <- merge(d, stop_cells, by = "stop_id")
    if (nrow(h)) out[[4]] <- h[, `:=`(geo_type = "h3_8", geo_id = h3_8)]
  }
  rbindlist(out, fill = TRUE)
}

prop_rows <- function(d, flag, min_n) {
  d[, {
    r <- memequity::proportion_counts(sum(get(flag)), .N, min_n = min_n)
    list(value = r$value, ci_low = r$ci_low, ci_high = r$ci_high, n = r$n, suppressed = r$suppressed)
  }, by = .(geo_type, geo_id)]
}

in_window <- function(d, through, days) d[service_date > through - days & service_date <= through]

# ---- ghost bus rate ---------------------------------------------------------

#' Trips on stops: a ghost trip is missing at every stop it was scheduled to
#' serve, so the stop and cell views count each trip once per stop.
compute_ghost <- function(classified_by_tolerance, stop_times, stop_cells, through, windows = WINDOW_DAYS) {
  out <- list()
  for (v in names(classified_by_tolerance)) {
    cls <- classified_by_tolerance[[v]]
    for (w in names(windows)) {
      d <- in_window(cls, through, windows[[w]])[measurable == TRUE & status != "unobserved"]
      if (!nrow(d)) next
      d[, ghost := status == "ghost"]
      trips <- explode_geos(d[, .(trip_id, service_date, route_id, ghost)], stop_cells)
      at_stops <- merge(d[, .(trip_id, service_date, route_id, ghost)],
                        unique(stop_times[, .(service_date, trip_id, stop_id)]), by = c("service_date", "trip_id"))
      stops <- explode_geos(at_stops, stop_cells)[geo_type %in% c("stop", "h3_8")]
      r <- rbind(prop_rows(trips[geo_type %in% c("citywide", "route")], "ghost", 30L),
                 prop_rows(stops, "ghost", 30L))
      r[, `:=`(variant = v, window_start = through - windows[[w]] + 1, window_end = through)]
      out[[length(out) + 1]] <- r
    }
  }
  res <- rbindlist(out)
  if (nrow(res)) res[, metric := "ghost_bus_rate"]
  res[]
}

# ---- on-time performance ------------------------------------------------------

#' Only routes whose match rate in the window clears the floor are measured
#' (spec on_time_pct).
routes_above_floor <- function(cls, through, days) {
  r <- in_window(cls, through, days)[measurable == TRUE,
                                     .(rate = mean(status == "observed")), by = route_id]
  r[rate >= MATCH_RATE_FLOOR, route_id]
}

compute_on_time <- function(arrivals, cls, stop_cells, through, windows = WINDOW_DAYS) {
  out <- list()
  for (w in names(windows)) {
    ok_routes <- routes_above_floor(cls, through, windows[[w]])
    a <- in_window(arrivals, through, windows[[w]])[!is.na(arrival) & route_id %in% ok_routes]
    if (!nrow(a)) next
    for (v in names(ON_TIME)) {
      lim <- ON_TIME[[v]]
      a[, on_time := delay_s >= lim[1] & delay_s <= lim[2]]
      r <- prop_rows(explode_geos(a[, .(route_id, stop_id, on_time)], stop_cells), "on_time", 30L)
      r[, `:=`(variant = v, window_start = through - windows[[w]] + 1, window_end = through)]
      out[[length(out) + 1]] <- r
    }
  }
  res <- rbindlist(out)
  if (nrow(res)) res[, metric := "on_time_pct"]
  res[]
}

# ---- peak headway ratio -----------------------------------------------------------

in_peak <- function(t) {
  lt <- as.POSIXlt(t, tz = "America/Chicago")
  h <- lt$hour + lt$min / 60
  wk <- lt$wday %in% 1:5
  wk & Reduce(`|`, lapply(PEAKS, function(p) h >= p[1] & h < p[2]))
}

#' Gaps between consecutive arrivals at each timepoint stop, route and
#' direction during weekday peaks. `events` has one row per scheduled
#' trip at each timepoint (measurable or not), with its status and inferred
#' arrival. Each stop's trips are walked in scheduled order:
#' - a confirmed ghost is skipped, so the gap spans it: that is the wait a
#'   rider really had;
#' - anything whose outcome is unknown breaks the chain, so no gap spans it:
#'   an unobserved block, a trip in a poller gap, or a trip that ran but
#'   could not be timed.
#' A negative gap (one bus overtaking another) is dropped. Scheduled gaps
#' come from the same stops and trips.
headway_gaps <- function(events) {
  e <- events[in_peak(scheduled)]
  setorder(e, service_date, route_id, direction_id, stop_id, scheduled)
  sched_gaps <- e[, .(gap = diff(as.numeric(scheduled))), by = .(service_date, route_id, direction_id, stop_id)]
  obs <- e[, {
    last_t <- NA_real_
    gaps <- numeric()
    for (i in seq_len(.N)) {
      if (measurable[i] && status[i] == "ghost") next
      t <- if (measurable[i] && status[i] == "observed") as.numeric(arrival[i]) else NA_real_
      if (is.na(t)) { last_t <- NA_real_; next }
      if (!is.na(last_t)) gaps <- c(gaps, t - last_t)
      last_t <- t
    }
    list(gap = gaps)
  }, by = .(service_date, route_id, direction_id, stop_id)]
  list(scheduled = sched_gaps, observed = obs[gap > 0])
}

#' @param events scheduled timepoint events (see headway_gaps).
compute_headway <- function(events, stop_cells, through, windows = WINDOW_DAYS) {
  out <- list()
  for (w in names(windows)) {
    ev <- in_window(events, through, windows[[w]])
    if (!nrow(ev)) next
    g <- headway_gaps(ev)
    # Only routes scheduled at 30 minutes or better in the peaks.
    frequent <- g$scheduled[, .(med = stats::median(gap)), by = route_id][med <= MAX_PEAK_HEADWAY_S, route_id]
    so <- explode_geos(g$scheduled[route_id %in% frequent], stop_cells)
    ob <- explode_geos(g$observed[route_id %in% frequent], stop_cells)
    if (!nrow(ob)) next
    sched_med <- so[, .(sched = stats::median(gap)), by = .(geo_type, geo_id)]
    r <- ob[, {
      m <- memequity::metric_median(gap, min_n = 20L)
      list(obs = m$value, lo = m$ci_low, hi = m$ci_high, n = m$n, suppressed = m$suppressed)
    }, by = .(geo_type, geo_id)]
    r <- merge(r, sched_med, by = c("geo_type", "geo_id"))
    r[, `:=`(value = obs / sched, ci_low = lo / sched, ci_high = hi / sched)]
    r[suppressed == TRUE, `:=`(value = NA_real_, ci_low = NA_real_, ci_high = NA_real_)]
    r <- r[, .(geo_type, geo_id, value, ci_low, ci_high, n, suppressed)]
    r[, `:=`(variant = "primary", window_start = through - windows[[w]] + 1, window_end = through)]
    out[[length(out) + 1]] <- r
  }
  res <- rbindlist(out)
  if (nrow(res)) res[, metric := "peak_headway_ratio"]
  res[]
}

add_citywide_reference <- function(m) {
  city <- m[geo_type == "citywide"]
  key <- function(d) paste(d$metric, d$variant, format(as.Date(d$window_start)), sep = "\r")
  m[, citywide_median := city$value[match(key(m), key(city))]]
  m[]
}
