repo_root <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", ".."))
for (f in list.files(file.path(repo_root, "pipelines", "permits", "R"), full.names = TRUE)) source(f)
source(file.path(repo_root, "pipelines", "permits", "tests", "golden.R"))
geo_dir <- file.path(repo_root, "geography")
cfg <- read_permits_config(file.path(repo_root, "pipelines", "permits", "config"))

# Downtown Memphis (inside the city, ZCTA 38103).
BASE_LON <- -90.0490
BASE_LAT <- 35.1495
M_PER_DEG_LON <- 111320 * cos(35.1495 * pi / 180)

local_ts <- function(x) as.POSIXct(x, tz = "America/Chicago")

#' Rows shaped like fetch_permits() output. `east_m` moves the point east of
#' downtown (still inside the city for well over 15 km).
make_permits <- function(n = 1, sub_type = "RES", construction_type = "NEW",
                         issued = "2026-06-01", value = 100000, east_m = 0, lon = NA, lat = NA,
                         id = NULL) {
  n <- max(n, length(sub_type), length(construction_type), length(issued), length(value),
           length(east_m))
  rep_n <- function(x) rep_len(x, n)
  data.frame(
    ObjectId = seq_len(n),
    Record_ID = if (is.null(id)) sprintf("RES-NEW-26-%06d", seq_len(n)) else id,
    Issued_Date = local_ts(rep_n(issued)),
    Sub_Type = rep_n(sub_type), Construction_Type = rep_n(construction_type),
    Valuation = rep_n(value), Address = "1 TEST ST", City = "MEMPHIS", ZIP_Code = "38103", State = "TN",
    Latitude = ifelse(is.na(rep_n(lat)), BASE_LAT, rep_n(lat)),
    Longitude = ifelse(is.na(rep_n(lon)), BASE_LON + rep_n(east_m) / M_PER_DEG_LON, rep_n(lon)),
    stringsAsFactors = FALSE)
}

permit_points <- function(raw, through) {
  attach_geography_permits(normalize_permits(raw, cfg, as.Date(through)), geo_dir)
}

#' A small parcel table: the city, ZIP 38103 and a tiny ZIP below the floor.
fake_parcels <- function(city = 10000, z38103 = 2000, z38105 = 100) {
  list(citywide = data.frame(geo_id = "4748000", parcels = city),
       zcta = data.frame(geo_id = c("38103", "38105"), parcels = c(z38103, z38105)))
}

get_row <- function(m, metric, geo_type, geo_id, subgroup, variant = "primary", years = 1) {
  through <- unique(as.Date(m$window_end))
  stopifnot(length(through) == 1)
  r <- m[m$metric == metric & m$geo_type == geo_type & m$geo_id == geo_id & m$subgroup == subgroup &
           m$variant == variant & as.Date(m$window_start) == window_start_years(through, years), ]
  stopifnot(nrow(r) == 1)
  r
}
