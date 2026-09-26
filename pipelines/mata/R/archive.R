# Read the MATA poller archive (pollers/mata_poller.py; weekly release assets,
# D7): vehicle positions, the log of every poll attempt, and the static GTFS
# zips archived once per run.

library(data.table)

read_jsonl_gz <- function(files) {
  rbindlist(lapply(files, function(f) {
    con <- gzfile(f, "rt", encoding = "UTF-8")
    on.exit(close(con))
    lines <- readLines(con, warn = FALSE)
    # A crash can leave a partial last line; every flush is a complete gzip
    # member, so only the unflushed tail is lost (D15).
    ok <- nzchar(lines) & endsWith(lines, "}")
    if (!any(ok)) return(NULL)
    as.data.table(jsonlite::fromJSON(paste0("[", paste(lines[ok], collapse = ","), "]"),
                                     simplifyVector = TRUE))
  }), fill = TRUE)
}

#' Vehicle positions, deduplicated across overlapping poller runs (D15) on
#' vehicle and report timestamp, with local time and service date.
read_positions <- function(archive_dir) {
  files <- list.files(archive_dir, pattern = "^mata_positions_.*\\.jsonl\\.gz$", full.names = TRUE)
  if (!length(files)) stop("no mata_positions files in ", archive_dir, call. = FALSE)
  p <- read_jsonl_gz(files)
  p <- p[!is.na(timestamp) & !is.na(lat) & !is.na(lon)]
  p[, vehicle := fifelse(is.na(vehicle_id) | vehicle_id == "", entity_id, vehicle_id)]
  p <- unique(p, by = c("vehicle", "timestamp"))
  p[, time := as.POSIXct(timestamp, origin = "1970-01-01", tz = "UTC")]
  # No MATA trip runs past midnight (no stop time at or after 24:00), so the
  # service date is the local calendar date of the report.
  p[, service_date := as.Date(format(time, tz = "America/Chicago", "%Y-%m-%d"))]
  setorder(p, vehicle, timestamp)
  p[]
}

#' Spans of time the vehicle feed was actually observed: successful polls no
#' more than `max_gap` seconds apart. data.table(start, end) in UTC.
covered_spans <- function(archive_dir, max_gap = 90) {
  files <- list.files(archive_dir, pattern = "^mata_polls_.*\\.jsonl\\.gz$", full.names = TRUE)
  polls <- read_jsonl_gz(files)
  t <- sort(unique(as.POSIXct(polls[feed == "vehicle_positions" & ok %in% TRUE]$poll_time,
                              format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
  if (length(t) < 2) return(data.table(start = as.POSIXct(character()), end = as.POSIXct(character())))
  brk <- c(TRUE, diff(as.numeric(t)) > max_gap)
  run <- cumsum(brk)
  data.table(t = t, run = run)[, .(start = min(t), end = max(t)), by = run][end > start, .(start, end)]
}

#' TRUE where [from, to] lies entirely inside one covered span.
fully_covered <- function(from, to, spans) {
  if (!nrow(spans)) return(rep(FALSE, length(from)))
  i <- findInterval(as.numeric(from), as.numeric(spans$start))
  ok <- i > 0
  ok[ok] <- as.numeric(to[ok]) <= as.numeric(spans$end[i[ok]])
  ok
}
