# Parcel counts per area, the denominator for the permits metrics (plan 7:
# "parcel counts from the Assessor ... refresh annually and version").
#
# Source: the City's "Tax Parcels" centroid layer on its 311 server, credited
# to the Shelby County Assessor of Property (docs/research/
# food-safety-geography-holidays.md). The county's own GIS and the
# Assessor's site block automated clients. Only the parcel id and the point
# are requested (no owner fields).
#
# Each parcel is counted in the area its centroid falls in, with the same
# boundary files and boundary rule (D8) as the pipelines. Writes
# geography/parcels/parcel_counts_<source>_<vintage>.csv and updates
# geography/parcels/registry.csv.
#
# Usage (from the repository root): Rscript geography/fetch_parcels.R

suppressPackageStartupMessages({
  library(memequity)
  library(sf)
})

LAYER <- "https://311.memphistn.gov/server/rest/services/311/ParcelCentroids/MapServer/0"
UA <- "memphis-service-equity (https://github.com/jpbranson/mem-service-equity)"
GEOS <- c("citywide", "zcta", "council_district", "super_district")

get_json <- function(..., tries = 6) {
  req <- httr2::request(paste0(LAYER, "/query")) |> httr2::req_url_query(..., f = "json") |>
    httr2::req_user_agent(UA) |> httr2::req_retry(max_tries = 5, backoff = function(i) 2^i) |>
    httr2::req_timeout(120)
  # req_retry covers HTTP 429/503; this also retries dropped connections.
  for (i in seq_len(tries)) {
    resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
    if (!inherits(resp, "error")) break
    if (i == tries) stop(resp)
    Sys.sleep(2^i)
  }
  b <- jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = TRUE)
  if (!is.null(b$error)) stop("ArcGIS error: ", b$error$message, call. = FALSE)
  b
}

expected <- get_json(where = "1=1", returnCountOnly = "true")$count
vintage_ms <- get_json(where = "1=1", outStatistics = jsonlite::toJSON(list(list(
  statisticType = "max", onStatisticField = "last_edited_date", outStatisticFieldName = "m")),
  auto_unbox = TRUE))$features$attributes$m
vintage <- format(as.POSIXct(vintage_ms / 1000, origin = "1970-01-01", tz = "UTC"), "%Y-%m")
message(expected, " parcels; newest edit ", vintage)

pages <- list(); after <- 0L
repeat {
  b <- get_json(where = sprintf("OBJECTID > %d", after), outFields = "OBJECTID,PARCELID",
                orderByFields = "OBJECTID ASC", resultRecordCount = 2000, outSR = 4326,
                returnGeometry = "true")
  if (!length(b$features) || !NROW(b$features$attributes)) break
  p <- b$features$attributes
  p$longitude <- b$features$geometry$x; p$latitude <- b$features$geometry$y
  pages[[length(pages) + 1]] <- p
  after <- max(p$OBJECTID)
  if (length(pages) %% 25 == 0) message("  ", sum(vapply(pages, nrow, 1L)), " parcels")
}
parcels <- do.call(rbind, pages)
stopifnot(nrow(parcels) == expected)
dups <- sum(duplicated(parcels$PARCELID))
message(nrow(parcels), " fetched; ", dups, " repeated PARCELIDs")
parcels <- parcels[!duplicated(parcels$PARCELID), ]

pts <- points_from_lonlat(parcels)
for (g in GEOS) pts <- assign_geography(pts, load_boundaries(g), g)
in_city <- !is.na(pts$citywide)
rn <- reference_neighborhoods()
pts$reference_neighborhood <- rn$neighborhood[match(pts$zcta, rn$zip)]

# Only parcels inside the city count, as for the pipelines (D20): an area that
# crosses the city line gets its in-city parcels.
counts <- do.call(rbind, lapply(c(GEOS, "reference_neighborhood"), function(g) {
  v <- pts[[g]][in_city]
  t <- table(v[!is.na(v)])
  data.frame(geo_type = g, geo_id = names(t), parcels = as.integer(t), stringsAsFactors = FALSE)
}))

dir <- file.path("geography", "parcels")
dir.create(dir, showWarnings = FALSE, recursive = TRUE)
file <- sprintf("parcel_counts_assessor-311parcelcentroids_%s.csv", vintage)
utils::write.csv(counts, file.path(dir, file), row.names = FALSE)
reg <- data.frame(
  file = file,
  source = paste("Shelby County Assessor of Property tax parcels, via the City of Memphis 311 server",
                 "(311/ParcelCentroids/MapServer/0)"),
  vintage = vintage, parcels_in_layer = nrow(parcels), parcels_in_city = sum(in_city),
  unlocated = sum(!pts$located), repeated_parcel_ids = dups,
  in_city_no_council_district = sum(in_city & is.na(pts$council_district)),
  fetched = format(Sys.Date()), stringsAsFactors = FALSE)
utils::write.csv(reg, file.path(dir, "registry.csv"), row.names = FALSE)
message(sum(in_city), " parcels inside the city -> ", file.path(dir, file))
