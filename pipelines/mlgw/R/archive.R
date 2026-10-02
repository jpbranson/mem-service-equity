# Read the MLGW poller archive (pollers/mlgw_poller.py; weekly release assets,
# D7): every successful poll writes one snapshot of all active outages, and
# every poll attempt, failed or not, is logged.

library(data.table)

#' Outage fields the specs use; validation fails if a snapshot lacks one.
MLGW_FIELDS <- c("OUTAGE_NO", "TIME_STAMP", "EST_REPAIR_TIME", "CUR_CUST_AFF", "OUT_CAUSE",
                 "IMPACT", "STATUS", "lon", "lat")
MLGW_TIME_FORMAT <- "%m/%d/%Y %I:%M:%S %p"

# The same reader as the MATA pipeline's: a crash can leave a partial last
# line, but every flush is a complete gzip member, so only that line is lost.
read_jsonl_gz <- function(files) {
  rbindlist(lapply(files, function(f) {
    con <- gzfile(f, "rt", encoding = "UTF-8")
    on.exit(close(con))
    lines <- readLines(con, warn = FALSE)
    ok <- nzchar(lines) & endsWith(lines, "}")
    if (!any(ok)) return(NULL)
    as.data.table(jsonlite::fromJSON(paste0("[", paste(lines[ok], collapse = ","), "]"),
                                     simplifyVector = TRUE))
  }), fill = TRUE)
}

#' Map times ("09/27/2026 01:30:00 PM") are local with no zone. They are read
#' as America/Chicago; in the repeated hour when daylight saving ends, as the
#' first (CDT) occurrence (spec outage_events_per_year). Blank is NA. UTC out.
parse_local_time <- function(x) {
  x <- trimws(as.character(x))
  x[!nzchar(x)] <- NA_character_
  out <- as.POSIXct(x, format = MLGW_TIME_FORMAT, tz = "America/Chicago")
  # A clock time that reads the same in CDT (UTC-5) is a valid CDT time, so
  # in the repeated hour this picks the CDT reading; elsewhere it changes nothing.
  cdt <- as.POSIXct(x, format = MLGW_TIME_FORMAT, tz = "Etc/GMT+5")
  same <- !is.na(cdt) & format(cdt, MLGW_TIME_FORMAT, tz = "America/Chicago") == x
  out[same] <- cdt[same]
  attr(out, "tzone") <- "UTC"
  out
}

#' Successful polls and the outages each one showed.
#' @return list(polls = sorted unique poll times (UTC), obs = one row per
#'   outage per poll, missing_fields = fields absent from the snapshots).
read_snapshots <- function(archive_dir) {
  files <- list.files(archive_dir, pattern = "^mlgw_snapshots_.*\\.jsonl\\.gz$", full.names = TRUE)
  if (!length(files)) stop("no mlgw_snapshots files in ", archive_dir, call. = FALSE)
  s <- read_jsonl_gz(files)
  s[, time := as.POSIXct(poll_time, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]
  # Overlapping runs (D15) poll independently; only a repeated poll time is a duplicate.
  s <- unique(s[!is.na(time)], by = "time")
  setorder(s, time)
  outs <- s$outages
  names(outs) <- seq_along(outs)
  obs <- rbindlist(Filter(function(o) length(o) && NROW(o), outs), fill = TRUE, idcol = "snap")
  missing <- setdiff(MLGW_FIELDS, names(obs))
  if (nrow(obs)) {
    for (f in missing) obs[, (f) := NA]
    obs[, poll_time := s$time[as.integer(snap)]]
    obs <- unique(obs, by = c("poll_time", "OUTAGE_NO"))
  }
  list(polls = s$time, obs = obs, missing_fields = if (nrow(obs)) missing else character())
}

#' Every logged attempt to fetch the outage map: data.table(time, ok).
read_poll_log <- function(archive_dir) {
  files <- list.files(archive_dir, pattern = "^mlgw_polls_.*\\.jsonl\\.gz$", full.names = TRUE)
  p <- read_jsonl_gz(files)
  if (!nrow(p)) return(data.table(time = as.POSIXct(character(), tz = "UTC"), ok = logical()))
  p <- p[feed == "outages"]
  p[, .(time = as.POSIXct(poll_time, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), ok = ok %in% TRUE)]
}

#' Spans of time the map was observed: successful polls no more than
#' `max_gap` seconds apart (polls run every 5 minutes). data.table(start, end).
covered_spans <- function(polls, max_gap = 900) {
  t <- sort(unique(polls))
  if (length(t) < 2) return(data.table(start = as.POSIXct(character(), tz = "UTC"),
                                       end = as.POSIXct(character(), tz = "UTC")))
  run <- cumsum(c(TRUE, diff(as.numeric(t)) > max_gap))
  data.table(t = t, run = run)[, .(start = min(t), end = max(t)), by = run][end > start, .(start, end)]
}

#' Share of [from, to) the spans cover.
span_coverage <- function(spans, from, to) {
  if (!nrow(spans)) return(0)
  s <- pmax(as.numeric(spans$start), as.numeric(from))
  e <- pmin(as.numeric(spans$end), as.numeric(to))
  sum(pmax(0, e - s)) / (as.numeric(to) - as.numeric(from))
}
