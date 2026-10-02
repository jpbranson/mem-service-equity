repo_root <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", ".."))
suppressPackageStartupMessages(library(data.table))
for (f in list.files(file.path(repo_root, "pipelines", "mlgw", "R"), full.names = TRUE)) source(f)

DATE <- "2026-09-24"                      # CDT, UTC-5
# A local clock time on DATE, held in UTC like the pipeline's times.
utc <- function(hm) {
  t <- as.POSIXct(paste(DATE, hm), format = "%Y-%m-%d %H:%M", tz = "America/Chicago")
  attr(t, "tzone") <- "UTC"
  t
}
map_time <- function(hm) format(utc(hm), "%m/%d/%Y %I:%M:%S %p", tz = "America/Chicago")

#' An outage as the map shows it at one poll.
outage <- function(no, start, cust, etr = "", cause = "", lon = -90.05, lat = 35.14) {
  list(OUTAGE_NO = no, TIME_STAMP = map_time(start), DURATION = "", IMPACT = "One Block",
       STATUS = "A crew is currently working on the problem",
       EST_REPAIR_TIME = if (nzchar(etr)) map_time(etr) else "", CUR_CUST_AFF = cust,
       OUT_CAUSE = cause, lon = lon, lat = lat)
}

write_snapshots <- function(polls, path) {
  con <- gzfile(path, "wt")
  for (p in polls)
    writeLines(as.character(jsonlite::toJSON(
      list(poll_time = format(utc(p$at), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"), outages = p$outages),
      auto_unbox = TRUE)), con)
  close(con)
}

write_poll_log <- function(times, path) {
  con <- gzfile(path, "wt")
  for (t in times)
    writeLines(as.character(jsonlite::toJSON(list(
      poll_time = format(utc(t), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"), feed = "outages", ok = TRUE),
      auto_unbox = TRUE)), con)
  close(con)
}

# The scenario on 2026-09-24: polls every 5 minutes from 08:00 to 12:00,
# except none between 10:00 and 10:35 (a poller gap).
#   101  08:05-08:30, 10 customers, ETR 08:20; moves after 08:15. Back at
#        11:00-11:10 (2 h 25 min after vanishing): a new event.
#   102  09:00-09:10, gone 09:15-09:25, back 09:30-09:40: one event, flagged.
#        Its start is revised from 08:58 to 08:55.
#   103  09:50-10:00, 20 customers, ETR 10:15; restored in the gap.
#   104  08:00-08:20, planned.
#   105  11:30-12:00, still on at the last poll; ETR 12:30, revised to 13:00 at 12:00.
SCENARIO_POLLS <- format(seq(utc("08:00"), utc("12:00"), by = 300), "%H:%M", tz = "America/Chicago")
SCENARIO_POLLS <- SCENARIO_POLLS[!(SCENARIO_POLLS > "10:00" & SCENARIO_POLLS < "10:35")]

scenario <- function() {
  dir <- tempfile("mlgw_archive_"); dir.create(dir)
  between <- function(t, a, b) t >= a & t <= b
  polls <- lapply(SCENARIO_POLLS, function(t) {
    o <- list()
    if (between(t, "08:05", "08:30"))
      o[[length(o) + 1]] <- outage(101, "08:02", 10, "08:20", lon = if (t <= "08:15") -90.05 else -90.049)
    if (between(t, "11:00", "11:10")) o[[length(o) + 1]] <- outage(101, "10:58", 3)
    if (between(t, "09:00", "09:10") || between(t, "09:30", "09:40"))
      o[[length(o) + 1]] <- outage(102, if (t == "09:00") "08:58" else "08:55", 5)
    if (between(t, "09:50", "10:00")) o[[length(o) + 1]] <- outage(103, "09:45", 20, "10:15")
    if (between(t, "08:00", "08:20")) o[[length(o) + 1]] <- outage(104, "07:30", 50, cause = "Planned Construction")
    if (between(t, "11:30", "12:00"))
      o[[length(o) + 1]] <- outage(105, "11:00", 2, if (t == "12:00") "13:00" else "12:30")
    list(at = t, outages = o)
  })
  write_snapshots(polls, file.path(dir, "mlgw_snapshots_run1.jsonl.gz"))
  # An overlapping run repeats one snapshot (D15).
  write_snapshots(polls[2], file.path(dir, "mlgw_snapshots_run2.jsonl.gz"))
  write_poll_log(SCENARIO_POLLS, file.path(dir, "mlgw_polls_run1.jsonl.gz"))
  dir
}

scenario_events <- function() {
  s <- read_snapshots(scenario())
  build_events(s$obs, s$polls, "Planned Construction")
}
