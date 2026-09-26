# Normalize: raw DPD permits -> one clean row per permit with the fields the
# metrics need. Exclusions are flagged, not dropped, so the validation report
# can count them.

# Generous bounding box around Shelby County (same as the 311 pipeline);
# points outside it, including the 0,0 placeholders, are unlocated.
SHELBY_BBOX <- c(xmin = -90.32, ymin = 34.99, xmax = -89.63, ymax = 35.42)

read_permits_config <- function(dir) {
  rd <- function(f) utils::read.csv(file.path(dir, f), stringsAsFactors = FALSE,
                                    na.strings = character(), encoding = "UTF-8")
  list(sector_map = rd("sector_map.csv"), category_map = rd("category_map.csv"),
       contract = memequity::read_contract(file.path(dir, "contract.yml")))
}

#' Last day of data the layer is complete through. The layer is refreshed
#' monthly, so the month of its latest data edit is treated as incomplete and
#' the data run through the end of the month before (never past as_of - 1).
permits_through <- function(last_edit, as_of) {
  edit_day <- as.Date(format(last_edit, tz = "America/Chicago", "%Y-%m-%d"))
  month_start <- as.Date(format(edit_day, "%Y-%m-01"))
  min(month_start - 1L, as.Date(as_of) - 1L)
}

#' @param raw data.frame from fetch_permits().
#' @param through last day the data are complete through (permits_through()).
normalize_permits <- function(raw, config, through) {
  sm <- config$sector_map; cm <- config$category_map
  sector <- sm$sector[match(raw$Sub_Type, sm$sub_type)]
  work <- cm$work[match(raw$Construction_Type, cm$construction_type)]
  category <- cm$category[match(raw$Construction_Type, cm$construction_type)]
  issue_date <- memequity::local_date(raw$Issued_Date)
  value <- ifelse(!is.na(raw$Valuation) & raw$Valuation > 0, raw$Valuation, NA_real_)

  lon <- raw$Longitude; lat <- raw$Latitude
  located <- !is.na(lon) & !is.na(lat) &
    lon >= SHELBY_BBOX[["xmin"]] & lon <= SHELBY_BBOX[["xmax"]] &
    lat >= SHELBY_BBOX[["ymin"]] & lat <= SHELBY_BBOX[["ymax"]]

  exclusion <- rep(NA_character_, nrow(raw))
  exclusion[is.na(issue_date)] <- "missing_issue_date"
  exclusion[is.na(exclusion) & (is.na(sector) | is.na(category))] <- "unmapped_type"
  exclusion[is.na(exclusion) & issue_date > through] <- "after_data_through"

  data.frame(
    permit_id = raw$Record_ID,
    issue_date = issue_date,
    sector = sector, work = work, category = category,
    value = value,
    longitude = ifelse(located, lon, NA_real_),
    latitude = ifelse(located, lat, NA_real_),
    match_quality = ifelse(located, "source_point", ifelse(is.na(lon) | is.na(lat), "missing", "out_of_area")),
    exclusion = exclusion,
    stringsAsFactors = FALSE)
}

PERMIT_GEOS <- c("citywide", "zcta", "council_district")

#' Attach the spec geographies and return an sf of permits.
attach_geography_permits <- function(p, geo_dir) {
  pts <- memequity::points_from_lonlat(p)
  for (g in PERMIT_GEOS)
    pts <- memequity::assign_geography(pts, memequity::load_boundaries(g, geo_dir), g)
  pts$in_city <- !is.na(pts$citywide)
  pts
}
