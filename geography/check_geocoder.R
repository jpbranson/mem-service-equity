# Geocoder accuracy check (plan section 7, DECISIONS.md H6).
#
# The reference is the City's own address points. Random in-city tax-parcel
# centroids are reverse-geocoded with the City's 311 locator
# (LiveLinkGeolocator, an address-point locator), and a parcel is kept when
# the locator returns a PointAddress within 50 m of it. Each of those official
# addresses is then geocoded exactly as the site's address lookup does, and
# the script measures how far the result lands from the official address
# point and whether it falls in the same H3 cell, disk, council district and
# ZIP code (ZCTA). The output is the worksheet for the hand check: the numbers
# are automatic, the verdicts are a person's.
#
# The parcel layer's PropertyAddress field is empty on every record
# (checked 2026-09-25), which is why addresses come from the locator.
#
# Usage (from the repository root):
#   Rscript geography/check_geocoder.R [out_dir] [n] [seed]
#
# Only non-personal parcel fields are requested (no owner names or owner
# addresses).

suppressPackageStartupMessages({
  library(memequity)
  library(sf)
})

args <- commandArgs(trailingOnly = TRUE)

# Summary rates over the whole sample: an address with no result counts as a
# miss in every rate, and so does one that lands outside every ZIP or district.
summarize_sheet <- function(sheet, seed, date) {
  pct <- function(x) sprintf("%.1f%%", 100 * mean(x %in% TRUE))
  located <- !is.na(sheet$geocode_lon)
  q <- stats::quantile(sheet$distance_m[located], c(0.5, 0.9, 0.95), names = FALSE)
  c(sprintf("sample: %d official address points from random in-city parcels (seed %s, %s)",
            nrow(sheet), seed, date),
    sprintf("census match: %s; nominatim fallback: %s; no result: %s",
            pct(sheet$geocoder == "census"), pct(startsWith(sheet$geocoder, "nominatim")),
            pct(startsWith(sheet$geocoder, "none"))),
    sprintf("distance to the official address point (located): median %.0f m, 90th pct %.0f m, 95th pct %.0f m",
            q[1], q[2], q[3]),
    sprintf("within 50 m: %s; within 100 m: %s; within 250 m: %s",
            pct(sheet$distance_m <= 50), pct(sheet$distance_m <= 100), pct(sheet$distance_m <= 250)),
    sprintf("same H3 cell: %s; inside the address point's 7-cell disk: %s",
            pct(sheet$same_cell), pct(sheet$in_reference_disk)),
    sprintf("same ZIP (ZCTA): %s; same council district: %s",
            pct(sheet$reference_zcta == sheet$geocode_zcta),
            pct(sheet$reference_council_district == sheet$geocode_council_district)),
    sprintf("flagged for the hand check: %d", sum(nzchar(sheet$flag))))
}

# `--summarize <sample.csv> [seed]` rebuilds the summary from a saved sample without
# querying any service.
if (length(args) >= 2 && args[1] == "--summarize") {
  sheet <- utils::read.csv(args[2], stringsAsFactors = FALSE, na.strings = "",
                           colClasses = c(reference_zcta = "character", geocode_zcta = "character",
                                          reference_council_district = "character",
                                          geocode_council_district = "character"))
  sheet$flag[is.na(sheet$flag)] <- ""
  date <- sub("^.*_([0-9]{4}-[0-9]{2}-[0-9]{2})[.]csv$", "\\1", basename(args[2]))
  summary <- summarize_sheet(sheet, if (length(args) >= 3) args[3] else "not given", date)
  writeLines(summary, file.path(dirname(args[2]), sprintf("geocoder_summary_%s.txt", date)))
  cat(summary, sep = "\n")
  quit(save = "no")
}

out_dir <- if (length(args) >= 1) args[1] else file.path("docs", "reviews", "h6-geocoder")
n_sample <- if (length(args) >= 2) as.integer(args[2]) else 200L
seed <- if (length(args) >= 3) as.integer(args[3]) else 20260925L

PARCELS <- "https://311.memphistn.gov/server/rest/services/311/ParcelCentroids/MapServer/0"
LOCATOR <- "https://311.memphistn.gov/server/rest/services/311/LiveLinkGeolocator/GeocodeServer"
FIELDS <- c("OBJECTID", "PARCELID", "ZipCode", "cd_name")
UA <- "memphis-service-equity (https://github.com/jpbranson/mem-service-equity)"

arcgis <- function(url, ...) {
  resp <- httr2::request(url) |> httr2::req_url_query(..., f = "json") |>
    httr2::req_user_agent(UA) |> httr2::req_retry(max_tries = 5) |> httr2::req_timeout(120) |>
    httr2::req_perform()
  jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = TRUE)
}

# ---- sample: random in-city parcels with an official address point -----------
ids <- arcgis(paste0(PARCELS, "/query"), where = "1=1", returnIdsOnly = "true")$objectIds
message(length(ids), " parcels in the layer")
set.seed(seed)
cand <- sample(ids, min(length(ids), 8L * n_sample))   # about 30% yield an address point
chunks <- split(cand, ceiling(seq_along(cand) / 200L))
parcels <- do.call(rbind, lapply(chunks, function(ch) {
  b <- arcgis(paste0(PARCELS, "/query"), objectIds = paste(ch, collapse = ","),
              outFields = paste(FIELDS, collapse = ","), outSR = 4326, returnGeometry = "true")
  a <- b$features$attributes
  a$lon <- b$features$geometry$x; a$lat <- b$features$geometry$y
  a
}))
parcels <- parcels[match(cand, parcels$OBJECTID), ]          # keep the random order
parcels <- parcels[!is.na(parcels$OBJECTID), ]
pts <- points_from_lonlat(parcels, "lon", "lat")
pts <- assign_geography(pts, load_boundaries("citywide"), "citywide")
parcels <- parcels[!is.na(pts$citywide), ]
message(nrow(parcels), " drawn parcels are inside the city")

reverse_one <- function(lon, lat) {
  Sys.sleep(0.25)
  loc <- jsonlite::toJSON(list(x = lon, y = lat, spatialReference = list(wkid = 4326)), auto_unbox = TRUE)
  b <- tryCatch(arcgis(paste0(LOCATOR, "/reverseGeocode"), location = loc, outSR = 4326),
                error = function(e) NULL)
  if (is.null(b) || is.null(b$address)) return(NULL)
  list(address = b$address$Address, postal = b$address$Postal, type = b$address$Addr_type,
       lon = b$location$x, lat = b$location$y)
}
kept <- list(); tried <- 0L
for (i in seq_len(nrow(parcels))) {
  if (length(kept) >= n_sample) break
  tried <- tried + 1L
  r <- reverse_one(parcels$lon[i], parcels$lat[i])
  if (is.null(r) || !identical(r$type, "PointAddress") || !grepl("^[1-9]", if (is.null(r$address)) "" else r$address)) next
  d <- xy_meters(points_from_lonlat(data.frame(x = c(parcels$lon[i], r$lon), y = c(parcels$lat[i], r$lat)),
                                    "x", "y"))
  if (sqrt(sum((d[1, ] - d[2, ])^2)) > 50) next
  kept[[length(kept) + 1]] <- data.frame(parcels[i, c("OBJECTID", "PARCELID", "ZipCode")],
                                         address = r$address, postal = r$postal,
                                         lon = r$lon, lat = r$lat)
  if (length(kept) %% 25 == 0) message("  ", length(kept), " addresses from ", tried, " parcels")
}
message(length(kept), " official addresses from ", tried, " in-city parcels")
if (length(kept) < n_sample) stop("not enough address points; raise the draw", call. = FALSE)
s <- do.call(rbind, kept)
s$PropertyAddress <- s$address

# ---- geocode as the site does ------------------------------------------------------
# site/assets/app.js: append ", Memphis, TN" when the input lacks "memphis",
# take the Census geocoder's first match (Public_AR_Current), and fall back to
# Nominatim (bounded to the Memphis box) when there is none.
census_one <- function(address) {
  Sys.sleep(0.5)
  b <- tryCatch({
    resp <- httr2::request("https://geocoding.geo.census.gov/geocoder/locations/onelineaddress") |>
      httr2::req_url_query(address = address, benchmark = "Public_AR_Current", format = "json") |>
      httr2::req_user_agent(UA) |> httr2::req_retry(max_tries = 4) |> httr2::req_timeout(60) |>
      httr2::req_perform()
    jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)
  }, error = function(e) NULL)
  if (is.null(b)) return(list(status = "error"))
  m <- b$result$addressMatches
  if (!length(m)) return(list(status = "no_match"))
  list(status = "match", lon = m[[1]]$coordinates$x, lat = m[[1]]$coordinates$y,
       matched = m[[1]]$matchedAddress, n_matches = length(m))
}
nominatim_one <- function(address) {
  Sys.sleep(1.1)   # usage policy: at most 1 request per second
  b <- tryCatch({
    resp <- httr2::request("https://nominatim.openstreetmap.org/search") |>
      httr2::req_url_query(q = address, format = "jsonv2", limit = 1, countrycodes = "us",
                           viewbox = "-90.31,35.27,-89.63,34.99", bounded = 1) |>
      httr2::req_user_agent(UA) |> httr2::req_timeout(60) |> httr2::req_perform()
    jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)
  }, error = function(e) NULL)
  if (!length(b)) return(NULL)
  list(lon = as.numeric(b[[1]]$lon), lat = as.numeric(b[[1]]$lat), matched = b[[1]]$display_name)
}

s$input <- paste0(trimws(s$PropertyAddress), ", Memphis, TN")
res <- lapply(seq_len(nrow(s)), function(i) {
  if (i %% 25 == 0) message("  geocoded ", i)
  r <- census_one(s$input[i])
  if (identical(r$status, "match"))
    return(data.frame(geocoder = "census", geo_lon = r$lon, geo_lat = r$lat, matched_address = r$matched,
                      census_candidates = r$n_matches))
  nm <- nominatim_one(s$input[i])
  if (is.null(nm)) return(data.frame(geocoder = paste0("none (census ", r$status, ")"), geo_lon = NA_real_,
                                     geo_lat = NA_real_, matched_address = NA_character_,
                                     census_candidates = 0L))
  data.frame(geocoder = paste0("nominatim (census ", r$status, ")"), geo_lon = nm$lon, geo_lat = nm$lat,
             matched_address = nm$matched, census_candidates = 0L)
})
s <- cbind(s, do.call(rbind, res))

# ---- compare with the official address point -------------------------------------------------------
truth <- points_from_lonlat(s, "lon", "lat")
geo <- points_from_lonlat(s, "geo_lon", "geo_lat")
for (g in c("zcta", "council_district")) {
  b <- load_boundaries(g)
  truth <- assign_geography(truth, b, g)
  geo <- assign_geography(geo, b, g)
}
tx <- xy_meters(truth); gx <- xy_meters(geo)
s$distance_m <- round(sqrt(rowSums((tx - gx)^2)), 1)
s$reference_cell <- h3_cell(truth, res = 9L)
s$geocode_cell <- h3_cell(geo, res = 9L)
s$same_cell <- s$reference_cell == s$geocode_cell
disk <- h3jsr::get_disk(ifelse(is.na(s$reference_cell), "8029fffffffffff", s$reference_cell), ring_size = 1)
s$in_reference_disk <- mapply(function(c, d) !is.na(c) && c %in% d, s$geocode_cell, disk)
s$reference_zcta <- truth$zcta; s$geocode_zcta <- geo$zcta
s$reference_council_district <- truth$council_district; s$geocode_council_district <- geo$council_district
s$same_zcta <- s$reference_zcta == s$geocode_zcta
s$same_council_district <- s$reference_council_district == s$geocode_council_district
s$flag <- ifelse(is.na(s$geo_lon), "no result",
          ifelse(!s$same_council_district %in% TRUE | !s$same_zcta %in% TRUE, "different area",
          ifelse(s$distance_m > 250, "over 250 m", ifelse(s$distance_m > 100, "over 100 m", ""))))

sheet <- data.frame(
  sample_id = seq_len(nrow(s)), parcel_id = s$PARCELID, input = s$input,
  reference_lon = round(s$lon, 6), reference_lat = round(s$lat, 6), geocoder = s$geocoder,
  matched_address = s$matched_address, census_candidates = s$census_candidates,
  geocode_lon = round(s$geo_lon, 6), geocode_lat = round(s$geo_lat, 6), distance_m = s$distance_m,
  same_cell = s$same_cell, in_reference_disk = s$in_reference_disk,
  reference_zcta = s$reference_zcta, geocode_zcta = s$geocode_zcta,
  reference_council_district = s$reference_council_district,
  geocode_council_district = s$geocode_council_district,
  same_zcta = s$same_zcta, same_council_district = s$same_council_district, flag = s$flag,
  reviewer_verdict = "", reviewer_notes = "", stringsAsFactors = FALSE)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
f <- file.path(out_dir, sprintf("geocoder_sample_%s.csv", format(Sys.Date())))
utils::write.csv(sheet, f, row.names = FALSE, na = "")

summary <- summarize_sheet(sheet, seed, format(Sys.Date()))
writeLines(summary, file.path(out_dir, sprintf("geocoder_summary_%s.txt", format(Sys.Date()))))
cat(summary, sep = "\n")
