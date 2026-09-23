repo_root <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", ".."))
for (f in list.files(file.path(repo_root, "pipelines", "311", "R"), full.names = TRUE)) source(f)
geo_dir <- file.path(repo_root, "geography")
cfg <- read_311_config(file.path(repo_root, "pipelines", "311", "config"))

# Downtown Memphis (inside the city, ZCTA 38103).
BASE_LON <- -90.0490
BASE_LAT <- 35.1495
M_PER_DEG_LAT <- 110950
M_PER_DEG_LON <- 111320 * cos(35.1495 * pi / 180)

local_ts <- function(x) as.POSIXct(x, tz = "America/Chicago")

#' Build rows shaped like fetch_311() output. Unspecified fields get benign
#' defaults. `east_m` offsets the point east of the base location (east of
#' downtown stays inside the city for well over 15 km).
make_raw <- function(n = 1, type = "PW (SM)-Potholes", status = "Closed",
                     created = "2026-06-01 10:00", closed = "2026-06-03 00:00",
                     east_m = 0, lon = NA, sysrev = NA_character_, id = NULL) {
  n <- max(n, length(created), length(closed), length(east_m), length(status), length(type))
  rep_n <- function(x) rep_len(x, n)
  lon0 <- BASE_LON + rep_n(east_m) / M_PER_DEG_LON
  data.frame(
    OBJECTID = seq_len(n), INCIDENT_NUMBER = if (is.null(id)) sprintf("T%05d", seq_len(n)) else id,
    INCIDENT_TYPE_ID = 1L, REQUEST_TYPE = rep_n(type), DEPARTMENT = NA_character_,
    GROUP_NAME = "MEMPHIS", REQUEST_STATUS = rep_n(status), Request_Sub_Status = "See Resolution Summary",
    REQUEST_PRIORITY = "Medium", REPORTED_DATE = local_ts(rep_n(created)),
    created_date = local_ts(rep_n(created)),
    Closed_Date = local_ts(rep_n(closed)), RESOLVED_DATE = as.POSIXct(NA),
    last_edited_date = local_ts(rep_n(created)), RESOLUTION_CODE = "X", ZipCode = "38103",
    cd_name = 6L, scd_name = 8L, SYSREVSTATUS = rep_n(sysrev), LINKED_SR = NA_character_,
    SCF_URL = NA_character_,
    longitude = ifelse(is.na(rep_n(lon)), lon0, rep_n(lon)), latitude = BASE_LAT,
    stringsAsFactors = FALSE)
}

pipeline_points <- function(raw, as_of) {
  sr <- normalize_311(raw, cfg, as.Date(as_of))
  attach_geography_311(sr, geo_dir)
}

citywide <- function(m, metric, variant = "primary", window_days = 90) {
  m$window_start <- as.Date(m$window_start); m$window_end <- as.Date(m$window_end)
  r <- m[m$geo_type == "citywide" & m$metric == metric & m$variant == variant &
           as.integer(m$window_end - m$window_start) + 1L == window_days, ]
  stopifnot(nrow(r) == 1)
  r
}
