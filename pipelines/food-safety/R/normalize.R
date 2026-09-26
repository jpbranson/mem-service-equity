# Normalize: canonical export tables -> one row per inspection and one per
# establishment, with a stable establishment key, the inspection kind, and a
# geocoded location per establishment. Exclusions are flagged, not dropped.

col_or_na <- function(d, field) if (!is.null(d) && field %in% names(d)) d[[field]] else
  rep(NA_character_, if (is.null(d)) 0L else nrow(d))

#' Stable establishment key: the permit number where the export has one,
#' otherwise the normalized name and address (spec
#' pct_below_followup_threshold, objection 2).
establishment_key <- function(id, name, address) {
  fallback <- paste0("name_address:", memequity::normalize_address(paste(name, address)))
  ifelse(!is.na(id) & nzchar(id), paste0("permit:", id), fallback)
}

#' @param through last day the export is complete through.
normalize_inspections <- function(tables, config, through) {
  ins <- tables$inspections
  kinds <- config$inspection_types
  type <- col_or_na(ins, "inspection_type")
  kind <- kinds$kind[match(type, kinds$inspection_type)]
  date <- if ("inspection_date" %in% names(ins)) ins$inspection_date else as.Date(rep(NA, nrow(ins)))
  exclusion <- rep(NA_character_, nrow(ins))
  exclusion[is.na(date)] <- "missing_inspection_date"
  exclusion[is.na(exclusion) & is.na(kind)] <- "unmapped_inspection_type"
  exclusion[is.na(exclusion) & date > through] <- "after_data_through"
  data.frame(
    inspection_id = col_or_na(ins, "inspection_id"),
    establishment_key = establishment_key(col_or_na(ins, "establishment_id"), col_or_na(ins, "name"),
                                          col_or_na(ins, "address")),
    inspection_date = date, inspection_type = type, kind = kind,
    score = suppressWarnings(as.numeric(col_or_na(ins, "score"))),
    exclusion = exclusion, stringsAsFactors = FALSE)
}

#' One row per establishment: from the establishments table where the export
#' has one, plus any establishment seen only in inspections (named and placed
#' by its latest inspection record).
normalize_establishments <- function(tables, inspections) {
  est <- tables$establishments
  from_est <- if (is.null(est) || !nrow(est)) NULL else data.frame(
    establishment_key = establishment_key(col_or_na(est, "establishment_id"), col_or_na(est, "name"),
                                          col_or_na(est, "address")),
    name = col_or_na(est, "name"), address = col_or_na(est, "address"), city = col_or_na(est, "city"),
    zip = col_or_na(est, "zip"), establishment_type = col_or_na(est, "establishment_type"),
    risk_category = col_or_na(est, "risk_category"),
    closed_date = if ("closed_date" %in% names(est)) est$closed_date else as.Date(rep(NA, nrow(est))),
    stringsAsFactors = FALSE)
  ins <- tables$inspections
  o <- order(inspections$inspection_date, decreasing = TRUE, na.last = TRUE)
  latest <- o[!duplicated(inspections$establishment_key[o])]
  from_ins <- data.frame(
    establishment_key = inspections$establishment_key[latest],
    name = col_or_na(ins, "name")[latest], address = col_or_na(ins, "address")[latest],
    city = col_or_na(ins, "city")[latest], zip = col_or_na(ins, "zip")[latest],
    establishment_type = NA_character_, risk_category = NA_character_,
    closed_date = as.Date(rep(NA, length(latest))), stringsAsFactors = FALSE)
  out <- rbind(from_est, from_ins[!from_ins$establishment_key %in% from_est$establishment_key, ])
  out[!duplicated(out$establishment_key), ]
}

#' Geocode establishments. `geocoder` has the signature of
#' memequity::geocode_addresses(); tests pass a stub. Only exact and
#' non-exact Census matches are accepted (the Nominatim fallback misplaced
#' highway addresses by kilometres in the H6 check).
geocode_establishments <- function(est, geocoder = memequity::geocode_addresses, cache_path = NULL,
                                   accepted = c("exact", "non_exact")) {
  city <- ifelse(is.na(est$city) | !nzchar(est$city), "Memphis", est$city)
  zip <- ifelse(is.na(est$zip), "", est$zip)
  g <- geocoder(est$address, city = city, state = "TN", zip = zip, cache_path = cache_path)
  ok <- g$match_quality %in% accepted
  est$longitude <- ifelse(ok, g$longitude, NA_real_)
  est$latitude <- ifelse(ok, g$latitude, NA_real_)
  est$match_quality <- ifelse(is.na(g$match_quality), "no_match", g$match_quality)
  est
}

FOOD_GEOS <- c("citywide", "zcta", "council_district", "h3_8")

attach_geography_food <- function(est, geo_dir) {
  pts <- memequity::points_from_lonlat(est)
  for (g in setdiff(FOOD_GEOS, "h3_8"))
    pts <- memequity::assign_geography(pts, memequity::load_boundaries(g, geo_dir), g)
  pts$h3_8 <- memequity::h3_cell(pts, res = 8L)
  pts$in_city <- !is.na(pts$citywide)
  pts
}
