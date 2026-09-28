# Shared by build_golden.R and the golden-file test, so both read the frozen
# inputs the same way and order the outputs the same way.

golden_key <- function(street, city, zip) paste(street, city, zip, sep = "|")

#' A geocoder with the signature of memequity::geocode_addresses() that
#' answers from the frozen geocodes, so the test never uses the network.
golden_geocoder <- function(dir) {
  g <- utils::read.csv(file.path(dir, "golden_geocodes.csv"), stringsAsFactors = FALSE,
                       na.strings = character(), encoding = "UTF-8",
                       colClasses = c(address = "character", city = "character", zip = "character",
                                      longitude = "numeric", latitude = "numeric",
                                      match_quality = "character"))
  function(street, city = "Memphis", state = "TN", zip = "", cache_path = NULL) {
    i <- match(golden_key(street, city, zip), golden_key(g$address, g$city, g$zip))
    if (anyNA(i)) stop(sum(is.na(i)), " addresses are not in the frozen geocodes", call. = FALSE)
    data.frame(longitude = g$longitude[i], latitude = g$latitude[i], match_quality = g$match_quality[i],
               matched_address = NA_character_, geocoder = "golden", stringsAsFactors = FALSE)
  }
}

golden_dates <- function(dir)
  list(from = as.Date(readLines(file.path(dir, "golden_from.txt"))),
       through = as.Date(readLines(file.path(dir, "golden_through.txt"))))

#' The pipeline from ingest to metrics, as run.R runs it, on the frozen
#' sample in `dir`/inbox.
golden_food <- function(dir, cfg, geo_dir, geocoder = golden_geocoder(dir)) {
  d <- golden_dates(dir)
  tables <- food_program_only(ingest_export(file.path(dir, "inbox"), cfg), cfg)
  ins <- normalize_inspections(tables, cfg, d$through, d$from)
  est <- geocode_establishments(normalize_establishments(tables, ins, cfg), geocoder = geocoder)
  compute_metrics_food(attach_geography_food(est, geo_dir), ins, cfg$rules, d$through, d$from)
}

golden_order <- function(m) {
  m <- m[order(m$metric, m$variant, m$geo_type, m$geo_id, m$window_start),
         c("metric", "variant", "subgroup", "geo_type", "geo_id", "window_start", "value",
           "ci_low", "ci_high", "n", "suppressed")]
  m$window_start <- format(as.Date(m$window_start))
  rownames(m) <- NULL
  m
}
