# Outage events from the sequence of snapshots (specs/mlgw/
# outage_events_per_year.md, "Details and edge cases"; DECISIONS.md H19):
# - an event is one OUTAGE_NO, followed across successful polls;
# - it is restored when absent from two consecutive successful polls, at a
#   time between the last poll that showed it and the first that did not;
# - an OUTAGE_NO that comes back within 2 hours of vanishing continues the
#   same event and is flagged; later, it starts a new one.

library(data.table)

REAPPEAR_WITHIN_S <- 2 * 3600
# restoration_vs_estimate leaves out restorations inside a longer poller gap.
RESTORATION_SPAN_MAX_S <- 30 * 60
# "ETR shown 60 minutes after outage start": the estimate on the last snapshot
# at or before start + 60 minutes, if that snapshot is no more than 10 minutes
# earlier (otherwise what the map showed then is unknown).
ETR_AT_S <- 3600
ETR_AT_TOLERANCE_S <- 600

#' @param obs one row per outage per successful poll (read_snapshots()$obs).
#' @param polls every successful poll time, sorted.
#' @param planned_causes OUT_CAUSE values that mark a planned outage.
#' @return one row per event.
build_events <- function(obs, polls, planned_causes) {
  if (!nrow(obs)) return(empty_events())
  P <- as.numeric(polls)
  o <- obs[, .(outage_no = as.character(OUTAGE_NO), t = as.numeric(poll_time),
               start_ts = as.numeric(parse_local_time(TIME_STAMP)),
               etr = as.numeric(parse_local_time(EST_REPAIR_TIME)),
               cust = as.numeric(CUR_CUST_AFF), cause = trimws(as.character(OUT_CAUSE)),
               lon = as.numeric(lon), lat = as.numeric(lat))]
  o[is.na(cause), cause := ""]
  setorder(o, outage_no, t)
  o[, i := match(t, P)]
  # Successful polls between this sighting and the previous one; all of them
  # showed the outage absent.
  o[, absent_before := i - shift(i) - 1L, by = outage_no]
  o[, vanished_for := t - P[shift(i) + 1L], by = outage_no]
  o[, new_event := is.na(absent_before) | (absent_before >= 2L & vanished_for > REAPPEAR_WITHIN_S)]
  o[, reappeared := !new_event & absent_before >= 2L]
  o[, event := cumsum(new_event), by = outage_no]
  # Customer-minutes from each sighting to the next successful poll, at that
  # sighting's count. If the next poll still shows the outage, the span is
  # certain; if not, restoration lies somewhere in it, so only the upper
  # bound counts it. After the last poll in the archive nothing is counted.
  o[, next_t := P[i + 1L]]
  o[, present_next := shift(i, type = "lead") == i + 1L & !shift(new_event, type = "lead"), by = outage_no]
  o[is.na(present_next), present_next := FALSE]
  o[, span := fifelse(is.na(next_t), 0, next_t - t)]
  o[, `:=`(cust_s_lo = fifelse(present_next, cust * span, 0), cust_s_hi = cust * span)]

  ev <- o[, {
    last <- .N
    hi_i <- i[last] + 1L
    confirmed <- hi_i + 1L <= length(P)          # a second poll after it also lacked it
    start <- suppressWarnings(min(start_ts, na.rm = TRUE))
    if (!is.finite(start)) start <- t[1]
    etrs <- etr[!is.na(etr)]
    at <- which(t <= start + ETR_AT_S)
    at <- if (length(at)) max(at) else NA_integer_
    etr_60 <- if (!is.na(at) && t[at] >= start + ETR_AT_S - ETR_AT_TOLERANCE_S) etr[at] else NA_real_
    loc <- which(!is.na(lon) & !is.na(lat))[1]
    list(start = start, first_seen = t[1], last_seen = t[last],
         restored_hi = if (hi_i <= length(P)) P[hi_i] else NA_real_, confirmed = confirmed,
         reappeared = any(reappeared), max_cust = max(cust, na.rm = TRUE),
         cust_hours_lo = sum(cust_s_lo, na.rm = TRUE) / 3600, cust_hours_hi = sum(cust_s_hi, na.rm = TRUE) / 3600,
         first_etr = if (length(etrs)) etrs[1] else NA_real_,
         etr_60m = etr_60,
         final_etr = if (length(etrs)) etrs[length(etrs)] else NA_real_,
         # A cause can be filled in after the first snapshot, so any planned
         # cause marks the event planned.
         planned = any(cause %in% planned_causes),
         lon = lon[loc], lat = lat[loc])
  }, by = .(outage_no, event)]
  ev[confirmed == FALSE, restored_hi := NA_real_]
  ev[, `:=`(restored_lo = fifelse(confirmed, last_seen, NA_real_))]
  ev[, restored_mid := (restored_lo + restored_hi) / 2]
  ev[, restoration_span_s := restored_hi - restored_lo]
  # Seconds without power: to the midpoint restoration, or to the last
  # sighting while the outage is still on.
  ev[, duration_s := fifelse(confirmed, restored_mid, last_seen) - start]
  ev[, event_id := paste(outage_no, event, sep = "-")]
  time_cols <- c("start", "first_seen", "last_seen", "restored_lo", "restored_hi", "restored_mid",
                 "first_etr", "etr_60m", "final_etr")
  for (col in time_cols) set(ev, j = col, value = as.POSIXct(ev[[col]], origin = "1970-01-01", tz = "UTC"))
  ev[, event := NULL]
  setcolorder(ev, "event_id")
  ev[]
}

empty_events <- function() {
  t0 <- as.POSIXct(character(), tz = "UTC")
  data.table(event_id = character(), outage_no = character(), start = t0, first_seen = t0,
             last_seen = t0, restored_hi = t0, confirmed = logical(), reappeared = logical(),
             max_cust = numeric(), cust_hours_lo = numeric(), cust_hours_hi = numeric(),
             first_etr = t0, etr_60m = t0, final_etr = t0, planned = logical(), lon = numeric(),
             lat = numeric(), restored_lo = t0, restored_mid = t0, restoration_span_s = numeric(),
             duration_s = numeric())
}
