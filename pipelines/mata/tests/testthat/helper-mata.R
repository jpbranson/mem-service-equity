repo_root <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", ".."))
suppressPackageStartupMessages(library(data.table))
for (f in list.files(file.path(repo_root, "pipelines", "mata", "R"), full.names = TRUE)) source(f)

# A straight 5 km route running east along one latitude, downtown Memphis.
LAT0 <- 35.1495
LON0 <- -90.0500
M_PER_DEG_LON <- 111320 * cos(LAT0 * pi / 180)
lon_at <- function(m) LON0 + m / M_PER_DEG_LON
DATE <- "2026-09-24"                      # a Thursday (weekday service)
# NA-safe: as.POSIXct() given "2026-09-24 NA" among valid strings falls back
# to a date-only format for the whole vector and drops every clock time.
local <- function(hms) {
  out <- as.POSIXct(rep(NA_real_, length(hms)), origin = "1970-01-01", tz = "America/Chicago")
  ok <- !is.na(hms)
  out[ok] <- as.POSIXct(paste(DATE, hms[ok]), format = "%Y-%m-%d %H:%M:%S", tz = "America/Chicago")
  out
}

#' A GTFS zip in `dir` (named like the poller's archive) with one shape and
#' stops at 0, 1000, 2500 and 5000 m; 0, 2500 and 5000 are timepoints.
#' trips: data.frame(trip_id, block_id, start "HH:MM:SS"); each runs 20 min.
write_gtfs <- function(dir, trips, date_label = DATE, sha = "abc123def456") {
  src <- tempfile("gtfs_src_"); dir.create(src)
  w <- function(d, f) data.table::fwrite(d, file.path(src, f))
  w(data.table(route_id = "R1", route_short_name = "1", route_type = 3), "routes.txt")
  w(data.table(service_id = "WK", monday = 1, tuesday = 1, wednesday = 1, thursday = 1, friday = 1,
               saturday = 0, sunday = 0, start_date = "20260901", end_date = "20261031"), "calendar.txt")
  w(data.table(service_id = character(), date = character(), exception_type = character()), "calendar_dates.txt")
  s <- seq(0, 5000, by = 100)
  w(data.table(shape_id = "S1", shape_pt_lat = LAT0, shape_pt_lon = lon_at(s),
               shape_pt_sequence = seq_along(s) - 1L, shape_dist_traveled = s), "shapes.txt")
  st <- data.table(stop_id = c("A", "B", "C", "D"), stop_name = c("A", "B", "C", "D"),
                   stop_lat = LAT0, stop_lon = lon_at(c(0, 1000, 2500, 5000)))
  w(st, "stops.txt")
  w(data.table(route_id = "R1", service_id = "WK", trip_id = trips$trip_id, direction_id = "0",
               block_id = trips$block_id, shape_id = "S1"), "trips.txt")
  offs <- c(0, 4, 10, 20) * 60
  stt <- rbindlist(lapply(seq_len(nrow(trips)), function(i) {
    t0 <- to_seconds(trips$start[i]) + offs
    hms <- sprintf("%02d:%02d:%02d", t0 %/% 3600, t0 %% 3600 %/% 60, t0 %% 60)
    data.table(trip_id = trips$trip_id[i], arrival_time = hms, departure_time = hms,
               stop_id = c("A", "B", "C", "D"), stop_sequence = 1:4,
               shape_dist_traveled = c(0, 1000, 2500, 5000), timepoint = c(1, 0, 1, 1))
  }))
  w(stt, "stop_times.txt")
  zip <- file.path(dir, sprintf("mata_gtfs_%s_%s.zip", date_label, sha))
  old <- setwd(src); on.exit(setwd(old))
  utils::zip(zip, list.files(src), flags = "-q")
  zip
}

#' Reports every 30 s for a vehicle moving from `start_m` at constant speed
#' so that it passes 2500 m at `at_2500` (local time), between `from` and `to`.
pings <- function(vehicle, trip_id, at_2500, speed, from, to) {
  t <- seq(as.numeric(local(from)), as.numeric(local(to)), by = 30) + 15
  m <- pmax(0, pmin(5000, 2500 + speed * (t - as.numeric(local(at_2500)))))
  data.table(entity_id = vehicle, vehicle_id = vehicle, vehicle_label = vehicle, trip_id = trip_id,
             route_id = "R1", schedule_relationship = "SCHEDULED", lat = LAT0, lon = lon_at(m),
             current_status = "IN_TRANSIT_TO", stop_id = NA_character_, timestamp = as.integer(t))
}

write_jsonl_gz <- function(d, path) {
  con <- gzfile(path, "wt")
  writeLines(vapply(seq_len(nrow(d)), function(i)
    as.character(jsonlite::toJSON(as.list(d[i]), auto_unbox = TRUE, na = "null")), ""), con)
  close(con)
}

#' Successful vehicle polls every 30 s over [from, to] local time.
write_polls <- function(dir, from, to, name = "mata_polls_run1.jsonl.gz") {
  t <- seq(local(from), local(to), by = 30)
  write_jsonl_gz(data.table(poll_time = format(t, tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
                            feed = "vehicle_positions", ok = TRUE), file.path(dir, name))
}
