# Parcel counts per area: the denominator for the permits metrics. Written by
# geography/fetch_parcels.R from the Assessor's tax parcels; only parcels
# inside the city are counted, like the ACS populations (D20).

#' The parcels registry: which counts file is current, its source and vintage.
#' @export
parcels_registry <- function(dir = geography_dir()) {
  utils::read.csv(file.path(dir, "parcels", "registry.csv"), stringsAsFactors = FALSE)
}

#' Parcels per area inside the city: data.frame geo_id, parcels.
#' @export
area_parcels <- function(geo_type, dir = geography_dir()) {
  reg <- parcels_registry(dir)
  d <- utils::read.csv(file.path(dir, "parcels", reg$file[1]), stringsAsFactors = FALSE,
                       colClasses = c(geo_type = "character", geo_id = "character"))
  if (!geo_type %in% d$geo_type) stop("No parcel counts for geo_type: ", geo_type, call. = FALSE)
  d <- d[d$geo_type == geo_type, ]
  data.frame(geo_id = d$geo_id, parcels = as.integer(d$parcels), stringsAsFactors = FALSE)
}
