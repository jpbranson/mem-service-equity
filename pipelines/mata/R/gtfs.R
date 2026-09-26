# Static GTFS: MATA regenerates it nightly as a rolling 30-day window and does
# not keep old versions, so the poller archives it once per run
# (mata_gtfs_<date>_<sha>.zip). The schedule in force on a service date is the
# newest archived zip dated on or before that date (plan 6.1).

read_gtfs <- function(zip_path) {
  rd <- function(name) {
    if (!name %in% utils::unzip(zip_path, list = TRUE)$Name) return(NULL)
    fread(cmd = NULL, file = utils::unzip(zip_path, name, exdir = tempfile("gtfs_")),
          colClasses = "character", encoding = "UTF-8")
  }
  g <- list(trips = rd("trips.txt"), stop_times = rd("stop_times.txt"), stops = rd("stops.txt"),
            shapes = rd("shapes.txt"), calendar = rd("calendar.txt"),
            calendar_dates = rd("calendar_dates.txt"), routes = rd("routes.txt"))
  g$stop_times[, `:=`(stop_sequence = as.integer(stop_sequence),
                      shape_dist_traveled = as.numeric(shape_dist_traveled),
                      timepoint = timepoint == "1")]
  g$shapes[, `:=`(shape_pt_sequence = as.integer(shape_pt_sequence),
                  shape_pt_lat = as.numeric(shape_pt_lat), shape_pt_lon = as.numeric(shape_pt_lon),
                  shape_dist_traveled = as.numeric(shape_dist_traveled))]
  g$stops[, `:=`(stop_lat = as.numeric(stop_lat), stop_lon = as.numeric(stop_lon))]
  g$file <- basename(zip_path)
  g
}

#' The archived zip in force on `date`: the newest whose file date is on or
#' before it. NULL when the archive starts later.
gtfs_zip_for_date <- function(archive_dir, date) {
  z <- list.files(archive_dir, pattern = "^mata_gtfs_\\d{4}-\\d{2}-\\d{2}_[0-9a-f]+\\.zip$", full.names = TRUE)
  if (!length(z)) return(NULL)
  d <- as.Date(sub("^mata_gtfs_(\\d{4}-\\d{2}-\\d{2})_.*$", "\\1", basename(z)))
  ok <- d <= as.Date(date)
  if (!any(ok)) return(NULL)
  z <- z[ok]; d <- d[ok]
  z[order(d, basename(z), decreasing = TRUE)][1]
}

#' Service ids running on `date` (calendar.txt, then calendar_dates.txt
#' exceptions: 1 adds, 2 removes).
active_services <- function(g, date) {
  date <- as.Date(date)
  ymd <- format(date, "%Y%m%d")
  dow <- c("sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday")[as.POSIXlt(date)$wday + 1]
  cal <- g$calendar
  on <- if (is.null(cal)) character() else
    cal[get(dow) == "1" & start_date <= ymd & end_date >= ymd, service_id]
  cd <- g$calendar_dates
  if (!is.null(cd) && nrow(cd)) {
    on <- union(on, cd[date == ymd & exception_type == "1", service_id])
    on <- setdiff(on, cd[date == ymd & exception_type == "2", service_id])
  }
  on
}

to_seconds <- function(hms) {
  p <- tstrsplit(hms, ":", fixed = TRUE, type.convert = as.integer)
  p[[1]] * 3600L + p[[2]] * 60L + p[[3]]
}

#' Scheduled trips on `date` with their first and last scheduled times (UTC
#' POSIXct; GTFS times count from local noon minus 12 hours, which equals
#' local midnight except on daylight-saving change days).
scheduled_trips <- function(g, date) {
  svc <- active_services(g, date)
  tr <- g$trips[service_id %in% svc]
  st <- g$stop_times[trip_id %in% tr$trip_id]
  noon <- as.POSIXct(paste(format(as.Date(date)), "12:00:00"), tz = "America/Chicago")
  st[, sched := noon - 12 * 3600 + to_seconds(arrival_time)]
  attr(st$sched, "tzone") <- "UTC"   # same zone as the vehicle reports
  span <- st[, .(first = min(sched), last = max(sched), n_stops = .N, n_timepoints = sum(timepoint)),
             by = trip_id]
  out <- merge(tr[, .(trip_id, route_id, direction_id, shape_id, block_id)], span, by = "trip_id")
  out[, service_date := as.Date(date)]
  list(trips = out, stop_times = st)
}
