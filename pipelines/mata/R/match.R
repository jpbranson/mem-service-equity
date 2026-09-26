# Trip matching (plan 6.1). The GTFS-Realtime feed carries MATA's own
# trip_id on every vehicle report, and the ids match the static feed, so a
# scheduled trip is matched by id on the service date. A scheduled trip is
# measurable only when the poller covered its whole span, plus the
# observation tolerance on each side; trips during poller gaps are excluded,
# never counted as missing (spec ghost_bus_rate).

OBS_TOLERANCE_MIN <- 15L

#' @param sched scheduled_trips(...)$trips for one or more service dates.
#' @param pos read_positions() output.
#' @param spans covered_spans() output.
#' @param tolerance minutes before the first and after the last scheduled
#'   time in which a report still counts as the trip being observed.
match_trips <- function(sched, pos, spans, tolerance = OBS_TOLERANCE_MIN) {
  tol <- tolerance * 60
  s <- copy(sched)
  s[, `:=`(from = first - tol, to = last + tol)]
  s[, measurable := fully_covered(from, to, spans)]
  seen <- pos[, .(n_reports = .N, first_report = min(time), last_report = max(time)),
              by = .(service_date, trip_id)]
  s <- merge(s, seen, by = c("service_date", "trip_id"), all.x = TRUE)
  s[is.na(n_reports), n_reports := 0L]
  s[, observed := n_reports > 0 & first_report <= to & last_report >= from]
  s[]
}

#' Per route (and all routes) share of measurable scheduled trips observed.
match_rates <- function(m) {
  r <- m[measurable == TRUE, .(scheduled = .N, observed = sum(observed)), by = route_id]
  r <- rbind(r, m[measurable == TRUE, .(route_id = "(all)", scheduled = .N, observed = sum(observed))])
  r[, match_rate := observed / scheduled]
  setorder(r, route_id)
  r[]
}

#' Vehicle reports whose trip_id is not in the schedule for their date
#' (MATA marks most of them ADDED).
unscheduled_reports <- function(pos, sched) {
  k <- paste(sched$service_date, sched$trip_id)
  pos[!paste(service_date, trip_id) %in% k,
      .(reports = .N, trips = uniqueN(trip_id)), by = schedule_relationship]
}
