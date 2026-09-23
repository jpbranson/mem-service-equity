# Normalize: raw 311 rows -> one clean row per request with the fields every
# metric needs. No metric logic here; exclusions are flagged, not dropped, so
# the validation report can count them.

# Generous bounding box around Shelby County; points outside are bad
# coordinates (the source contains lon -168, lat 0/90, etc).
SHELBY_BBOX <- c(xmin = -90.32, ymin = 34.99, xmax = -89.63, ymax = 35.42)

# The current 311 system went live 2023-10-16. Records created earlier are
# migration artifacts and are never mixed into the post-migration series.
MIGRATION_DATE <- as.Date("2023-10-16")

read_311_config <- function(dir) {
  list(
    request_types = utils::read.csv(file.path(dir, "request_types.csv"), stringsAsFactors = FALSE,
                                    na.strings = ""),
    status_map = utils::read.csv(file.path(dir, "status_map.csv"), stringsAsFactors = FALSE,
                                 na.strings = character(), encoding = "UTF-8"),
    contract = memequity::read_contract(file.path(dir, "contract.yml"))
  )
}

#' @param raw data.frame from fetch_311().
#' @param as_of run date; data are complete through as_of - 1.
normalize_311 <- function(raw, config, as_of) {
  as_of <- as.Date(as_of)
  through <- as_of - 1
  status <- ifelse(is.na(raw$REQUEST_STATUS), "", raw$REQUEST_STATUS)
  state <- config$status_map$state[match(status, config$status_map$status)]
  state[is.na(state)] <- "unmapped"

  opened_at <- raw$created_date
  open_date <- memequity::local_date(opened_at)
  closed_raw <- raw$Closed_Date
  close_date_raw <- memequity::local_date(closed_raw)

  close_problem <- rep(NA_character_, nrow(raw))
  is_closed <- state == "closed"
  close_problem[is_closed & is.na(closed_raw)] <- "missing_close_date"
  close_problem[is_closed & !is.na(close_date_raw) & close_date_raw < MIGRATION_DATE] <- "sentinel_close_date"
  close_problem[is_closed & is.na(close_problem) & close_date_raw < open_date] <- "close_before_open"
  close_problem[is_closed & is.na(close_problem) & close_date_raw > through + 1] <- "close_in_future"
  close_ok <- is_closed & is.na(close_problem)
  close_date <- as.Date(ifelse(close_ok, close_date_raw, NA), origin = "1970-01-01")

  hol <- memequity::holiday_calendar(2023:(as.integer(format(as_of, "%Y")) + 1))$date
  bd_to_close <- memequity::business_days_between(open_date, close_date, hol)
  age_bd <- memequity::business_days_between(open_date, rep(through, nrow(raw)), hol)

  lon <- raw$longitude; lat <- raw$latitude
  located <- !is.na(lon) & !is.na(lat) &
    lon >= SHELBY_BBOX[["xmin"]] & lon <= SHELBY_BBOX[["xmax"]] &
    lat >= SHELBY_BBOX[["ymin"]] & lat <= SHELBY_BBOX[["ymax"]]

  rt <- config$request_types
  exclusion <- rep(NA_character_, nrow(raw))
  exclusion[is.na(raw$REQUEST_TYPE) | raw$REQUEST_TYPE == ""] <- "missing_request_type"
  exclusion[is.na(exclusion) & open_date < MIGRATION_DATE] <- "pre_migration"
  exclusion[is.na(exclusion) & open_date > through] <- "partial_day"
  exclusion[is.na(exclusion) & !is.na(raw$SYSREVSTATUS) & raw$SYSREVSTATUS == "DUPLICATE"] <- "city_duplicate"
  exclusion[is.na(exclusion) & state %in% c("unknown", "unmapped")] <- "unknown_status"

  data.frame(
    sr_id = raw$INCIDENT_NUMBER,
    request_type = raw$REQUEST_TYPE,
    category = rt$category[match(raw$REQUEST_TYPE, rt$request_type)],
    status = status,
    state = state,
    opened_at = opened_at,
    open_date = open_date,
    close_date = close_date,
    close_problem = close_problem,
    closed = close_ok,
    bd_to_close = bd_to_close,
    age_bd = age_bd,
    origin = ifelse(!is.na(raw$SCF_URL) & nzchar(raw$SCF_URL), "seeclickfix", "311"),
    source_council_district = raw$cd_name,
    source_zip = raw$ZipCode,
    longitude = ifelse(located, lon, NA_real_),
    latitude = ifelse(located, lat, NA_real_),
    match_quality = ifelse(located, "source_point",
                           ifelse(is.na(lon) | is.na(lat), "missing", "out_of_area")),
    exclusion = exclusion,
    stringsAsFactors = FALSE
  )
}

#' Attach geographies, deduplicate, and return an sf of requests.
attach_geography_311 <- function(sr, geo_dir, h3_res = 9L, dedupe_m = 50, dedupe_days = 7) {
  pts <- memequity::points_from_lonlat(sr)
  for (g in c("citywide", "zcta", "council_district", "super_district"))
    pts <- memequity::assign_geography(pts, memequity::load_boundaries(g, geo_dir), g)
  pts$in_city <- !is.na(pts$citywide)
  pts$h3 <- memequity::h3_cell(pts, res = h3_res)
  # Deduplicate among included, located requests (DECISIONS.md D6).
  pts$duplicate_of <- NA_character_
  cand <- which(is.na(pts$exclusion) & pts$located)
  if (length(cand)) {
    d <- memequity::near_duplicates(pts[cand, ], pts$request_type[cand], pts$opened_at[cand],
                                    meters = dedupe_m, days = dedupe_days)
    pts$duplicate_of[cand] <- pts$sr_id[cand][d]
  }
  pts
}
