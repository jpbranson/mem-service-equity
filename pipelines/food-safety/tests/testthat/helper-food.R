repo_root <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", ".."))
for (f in list.files(file.path(repo_root, "pipelines", "food-safety", "R"), full.names = TRUE)) source(f)
geo_dir <- file.path(repo_root, "geography")
cfg <- read_food_config(file.path(repo_root, "pipelines", "food-safety", "config"))

# Downtown Memphis (inside the city, ZCTA 38103).
BASE_LON <- -90.0490
BASE_LAT <- 35.1495
M_PER_DEG_LON <- 111320 * cos(35.1495 * pi / 180)

#' Geocoder stub with the signature of memequity::geocode_addresses():
#' "<n> TEST ST" lands n * 10 m east of downtown; anything else fails.
stub_geocoder <- function(street, city = "Memphis", state = "TN", zip = "", cache_path = NULL) {
  n <- suppressWarnings(as.integer(sub("^([0-9]+) TEST ST$", "\\1", street)))
  ok <- !is.na(n)
  data.frame(longitude = ifelse(ok, BASE_LON + n * 10 / M_PER_DEG_LON, NA_real_),
             latitude = ifelse(ok, BASE_LAT, NA_real_),
             match_quality = ifelse(ok, "exact", "no_match"), matched_address = street,
             geocoder = "stub", stringsAsFactors = FALSE)
}

#' Synthetic inspections for fictitious establishments ("Test Grill <n>" at
#' "<n> TEST ST", permit P<n>), in canonical field names.
make_inspections <- function(est, dates, types, scores) {
  data.frame(establishment_id = paste0("P", est), name = paste("Test Grill", est),
             address = paste(est, "TEST ST"), city = "Memphis", zip = "38103",
             inspection_id = sprintf("I%05d", seq_along(est)),
             inspection_date = format(as.Date(dates), "%m/%d/%Y"), inspection_type = types,
             score = scores, stringsAsFactors = FALSE)
}

#' Write canonical tables to a temp inbox under the export's column names
#' from config/column_map.yml, so tests exercise the real column mapping.
write_export <- function(inspections, establishments = NULL) {
  dir <- tempfile("inbox_")
  dir.create(dir)
  cm <- cfg$column_map$tables
  rename <- function(d, map) { names(d) <- vapply(names(d), function(n) map[[n]], ""); d }
  utils::write.csv(rename(inspections, cm$inspections$columns),
                   file.path(dir, "inspections_export.csv"), row.names = FALSE, na = "")
  if (!is.null(establishments))
    utils::write.csv(rename(establishments, cm$establishments$columns),
                     file.path(dir, "establishments_export.csv"), row.names = FALSE, na = "")
  dir
}

food_pipeline <- function(inbox, through) {
  through <- as.Date(through)
  tables <- ingest_export(inbox, cfg)
  ins <- normalize_inspections(tables, cfg, through)
  est <- geocode_establishments(normalize_establishments(tables, ins), geocoder = stub_geocoder)
  pts <- attach_geography_food(est, geo_dir)
  list(tables = tables, ins = ins, est = pts, m = compute_metrics_food(pts, ins, cfg$rules, through))
}

get_food <- function(m, metric, geo_type = "citywide", variant = "primary") {
  r <- m[m$metric == metric & m$geo_type == geo_type & m$variant == variant, ]
  stopifnot(nrow(r) == 1)
  r
}
