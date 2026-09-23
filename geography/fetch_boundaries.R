# Fetch the shared boundary sets (design plan section 7) and write them to
# geography/boundaries/ with source and vintage in each file name, plus the
# registry that memequity::load_boundaries() reads.
#
# Run from the repository root:  Rscript geography/fetch_boundaries.R
# Sources are documented in docs/research/.

suppressPackageStartupMessages({
  library(sf)
  library(httr2)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

out_dir <- file.path("geography", "boundaries")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

TIGERWEB <- "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb"

# The 41 ZCTAs that intersect Shelby County (47157), from the 2020 Census
# ZCTA-to-county relationship file.
SHELBY_ZCTAS <- c("38002", "38004", "38011", "38016", "38017", "38018", "38028", "38029",
                  "38053", "38054", sprintf("%d", c(38103:38109, 38111:38120, 38122,
                  38125:38128, 38131:38135, 38138, 38139, 38141, 38152)))

arcgis_geojson <- function(layer_url, where, out_fields = "*", page = 2000) {
  # Page through an ArcGIS REST layer and return an sf object.
  parts <- list(); offset <- 0
  repeat {
    resp <- request(paste0(layer_url, "/query")) |>
      req_url_query(where = where, outFields = out_fields, returnGeometry = "true",
                    outSR = 4326, f = "geojson", resultOffset = offset,
                    resultRecordCount = page) |>
      req_retry(max_tries = 4) |>
      req_timeout(300) |>
      req_perform()
    txt <- resp_body_string(resp)
    part <- st_read(txt, quiet = TRUE)
    parts[[length(parts) + 1]] <- part
    if (nrow(part) < page) break
    offset <- offset + page
  }
  do.call(rbind, parts)
}

write_set <- function(x, file) {
  path <- file.path(out_dir, file)
  if (file.exists(path)) unlink(path)
  x <- st_make_valid(x)
  st_write(x, path, driver = "GeoJSON", quiet = TRUE,
           layer_options = c("COORDINATE_PRECISION=6", "RFC7946=YES"))
  message("wrote ", path, " (", nrow(x), " features)")
  path
}

registry <- list()
add <- function(geo_type, file, id_field, source, vintage) {
  registry[[length(registry) + 1]] <<- data.frame(
    geo_type = geo_type, file = file, id_field = id_field, source = source,
    vintage = vintage, fetched = format(Sys.Date()))
}

# ZCTAs (2020)
zcta <- arcgis_geojson(paste0(TIGERWEB, "/tigerWMS_Census2020/MapServer/84"),
                       sprintf("GEOID IN (%s)", paste0("'", SHELBY_ZCTAS, "'", collapse = ",")),
                       "GEOID,ZCTA5,AREALAND")
stopifnot(nrow(zcta) == length(SHELBY_ZCTAS))
f <- write_set(zcta, "zcta_census-tigerweb_2020.geojson")
add("zcta", basename(f), "GEOID", "Census TIGERweb tigerWMS_Census2020 layer 84", "2020")

# Census tracts, Shelby County (2020)
tracts <- arcgis_geojson(paste0(TIGERWEB, "/tigerWMS_Census2020/MapServer/6"),
                         "STATE='47' AND COUNTY='157'", "GEOID,NAME,AREALAND")
stopifnot(nrow(tracts) > 200)
f <- write_set(tracts, "tract_census-tigerweb_2020.geojson")
add("tract", basename(f), "GEOID", "Census TIGERweb tigerWMS_Census2020 layer 6", "2020")

# City of Memphis boundary (current)
city <- arcgis_geojson(paste0(TIGERWEB, "/tigerWMS_Current/MapServer/28"),
                       "GEOID='4748000'", "GEOID,NAME")
stopifnot(nrow(city) == 1)
f <- write_set(city, sprintf("citywide_census-tigerweb_%s.geojson", format(Sys.Date(), "%Y")))
add("citywide", basename(f), "GEOID", "Census TIGERweb tigerWMS_Current layer 28 (place 4748000)",
    format(Sys.Date(), "%Y"))

# City Council districts (current, post-redistricting) -- layer URL and id
# field are set in geography/sources.yml once confirmed (DECISIONS.md).
src <- yaml::read_yaml(file.path("geography", "sources.yml"))
for (s in src$arcgis_layers) {
  if (!isTRUE(s$enabled)) { message("skipping ", s$geo_type, ": ", s$note); next }
  x <- arcgis_geojson(s$url, s$where %||% "1=1", s$out_fields %||% "*")
  if (!is.null(s$expected_features)) stopifnot(nrow(x) == s$expected_features)
  f <- write_set(x, s$file)
  add(s$geo_type, basename(f), s$id_field, s$source, s$vintage)
}

reg <- do.call(rbind, registry)
write.csv(reg, file.path(out_dir, "registry.csv"), row.names = FALSE)
message("registry: ", nrow(reg), " boundary sets")
