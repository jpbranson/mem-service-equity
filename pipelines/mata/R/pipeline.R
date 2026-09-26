# Per-service-date processing and metric assembly for the MATA pipeline.

GHOST_TOLERANCES <- c(primary = 15L, tolerance_10m = 10L, tolerance_30m = 30L)

#' Everything the metrics need for one service date, using the schedule in
#' force that day. NULL when no archived schedule covers the date.
process_date <- function(archive_dir, date, pos, spans) {
  z <- gtfs_zip_for_date(archive_dir, date)
  if (is.null(z)) return(NULL)
  g <- read_gtfs(z)
  s <- scheduled_trips(g, date)
  if (!nrow(s$trips)) return(NULL)
  p <- pos[service_date == as.Date(date)]
  cls <- lapply(GHOST_TOLERANCES, function(tol) classify_trips(match_trips(s$trips, p, spans, tol)))
  arrivals <- infer_arrivals(cls$primary, s$stop_times, p, g)
  # Every scheduled trip's timepoints after its first stop, with its
  # status and (if timed) arrival, for the headway walk.
  tp <- s$stop_times[timepoint == TRUE]
  setorder(tp, trip_id, stop_sequence)
  tp <- tp[, .SD[-1], by = trip_id]
  events <- merge(tp[, .(trip_id, stop_id, stop_sequence, scheduled = sched)],
                  cls$primary[, .(trip_id, service_date, route_id, direction_id, status, measurable)],
                  by = "trip_id")
  if (nrow(arrivals))
    events <- merge(events, arrivals[, .(trip_id, stop_id, stop_sequence, arrival)],
                    by = c("trip_id", "stop_id", "stop_sequence"), all.x = TRUE)
  else events[, arrival := as.POSIXct(NA)]
  list(date = as.Date(date), gtfs = basename(z), cls = cls, arrivals = arrivals, events = events,
       stop_times = s$stop_times[, .(service_date = as.Date(date), trip_id, stop_id)],
       stops = g$stops[, .(stop_id, stop_name, stop_lat, stop_lon)])
}

#' H3 resolution-8 cell of each stop.
stop_cells <- function(stops) {
  st <- unique(rbindlist(stops), by = "stop_id")
  pts <- memequity::points_from_lonlat(as.data.frame(st), "stop_lon", "stop_lat")
  data.table(stop_id = st$stop_id, h3_8 = memequity::h3_cell(pts, res = 8L))[!is.na(h3_8)]
}

#' Windows with archived data on at least `min_coverage` of their days. A
#' "30-day" figure from three days of data would misstate what it measures.
usable_windows <- function(data_dates, through, min_coverage) {
  keep <- vapply(WINDOW_DAYS, function(n)
    mean(seq(through - n + 1, through, by = "day") %in% data_dates) >= min_coverage, logical(1))
  WINDOW_DAYS[keep]
}

#' @param days list of process_date() results.
#' @param min_coverage share of a window's days that must have data.
compute_metrics_mata <- function(days, through, min_coverage = 0.9) {
  days <- Filter(Negate(is.null), days)
  windows <- usable_windows(as.Date(vapply(days, function(d) format(d$date), "")), through, min_coverage)
  cells <- stop_cells(lapply(days, `[[`, "stops"))
  cls <- lapply(names(GHOST_TOLERANCES), function(v) rbindlist(lapply(days, function(d) d$cls[[v]])))
  names(cls) <- names(GHOST_TOLERANCES)
  arrivals <- rbindlist(lapply(days, `[[`, "arrivals"), fill = TRUE)
  events <- rbindlist(lapply(days, `[[`, "events"), fill = TRUE)
  stop_times <- rbindlist(lapply(days, `[[`, "stop_times"))
  m <- rbindlist(list(
    if (length(windows)) compute_ghost(cls, stop_times, cells, through, windows),
    if (length(windows) && nrow(arrivals)) compute_on_time(arrivals, cls$primary, cells, through, windows),
    if (length(windows)) compute_headway(events, cells, through, windows)), fill = TRUE)
  if (nrow(m)) {
    m[, `:=`(subgroup = "all", metric_version = SPEC_VERSIONS[metric])]
    m <- add_citywide_reference(m)
  }
  list(metrics = m, windows = windows, classified = cls$primary, arrivals = arrivals)
}
