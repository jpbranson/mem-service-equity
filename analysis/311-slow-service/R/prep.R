# Data preparation. Each source goes through its own pipeline's normalize and
# geography code (pipelines/<name>/R/), so exclusions, deduplication (D6) and
# boundary rules (D8) are exactly the project's. This file only adds a 2020
# census-tract assignment and saves one cache for the analysis.

# Source a pipeline's R/ files into their own environment, so the three
# pipelines' helpers (several share names) cannot overwrite each other.
source_pipeline <- function(dir) {
  e <- new.env()
  for (f in list.files(file.path(dir, "R"), full.names = TRUE)) sys.source(f, envir = e)
  e
}

# A geocoder that only reads the food-safety geocode cache and never calls the
# Census service, so the analysis runs offline and cannot change the cache.
cache_only_geocoder <- function(street, city = "Memphis", state = "TN", zip = "", cache_path = NULL) {
  n <- length(street)
  key <- memequity::normalize_address(paste(street, rep_len(city, n), rep_len(state, n), rep_len(zip, n)))
  cache <- memequity::read_geocode_cache(cache_path)
  miss <- sum(!key %in% cache$address_key)
  if (miss) message("  ", miss, " establishment addresses are not in the geocode cache; left unlocated")
  out <- cache[match(key, cache$address_key),
               c("longitude", "latitude", "match_quality", "matched_address", "geocoder")]
  rownames(out) <- NULL
  out
}

#' Build (or read) the analysis cache.
#'
#' @param as_of run date of the 311 and permits caches; data are complete
#'   through as_of - 1 (the pipelines' convention).
prep_data <- function(p, rebuild = FALSE) {
  if (!rebuild && file.exists(p$prep_cache)) return(readRDS(p$prep_cache))
  gd <- memequity::geography_dir()
  tracts <- memequity::load_boundaries("tract", gd)
  add_tract <- function(pts) sf::st_drop_geometry(memequity::assign_geography(pts, tracts, "tract"))
  out <- list()

  # 311 (City of Memphis 311 layer, offline cache)
  e3 <- source_pipeline("pipelines/311")
  cfg3 <- e3$read_311_config("pipelines/311/config")
  raw3 <- readRDS(p$raw_311)
  sr <- e3$normalize_311(raw3, cfg3, p$as_of)
  message("311: attaching geography and removing near-duplicates (about 2 minutes)")
  out$sr <- add_tract(e3$attach_geography_311(sr, gd))
  # The source's resolution code, kept only to describe how requests were
  # closed (its meanings are undocumented; the disposition audit is H4).
  out$sr$resolution_code <- raw3$RESOLUTION_CODE[match(out$sr$sr_id, raw3$INCIDENT_NUMBER)]
  out$request_types <- cfg3$request_types

  # Building permits (City DPD layer, offline cache)
  ep <- source_pipeline("pipelines/permits")
  cfgp <- ep$read_permits_config("pipelines/permits/config")
  rawp <- readRDS(p$raw_permits)
  thr <- ep$permits_through(attr(rawp, "last_edit"), p$as_of)
  out$permits <- add_tract(ep$attach_geography_permits(ep$normalize_permits(rawp, cfgp, thr), gd))
  attr(out$permits, "through") <- thr

  # Demolitions (owner's Data Midsouth snapshot, DECISIONS.md D30); optional
  if (file.exists(p$demolitions_file)) {
    demo <- ep$read_demolitions(p$demolitions_file, cfgp$demolitions)
    dthr <- max(demo$status_date, na.rm = TRUE)
    out$demolitions <- add_tract(ep$attach_geography_permits(ep$normalize_demolitions(demo, dthr), gd))
    attr(out$demolitions, "through") <- dthr
  }

  # Food inspections (owner's collector for the state portal, D29); optional.
  # Used only for the data inventory (see README).
  if (dir.exists(p$inspections_dir)) {
    ef <- source_pipeline("pipelines/food-safety")
    cfgf <- ef$read_food_config("pipelines/food-safety/config")
    tabs <- ef$food_program_only(ef$ingest_export(p$inspections_dir, cfgf), cfgf)
    thr_f <- max(tabs$inspections$inspection_date, na.rm = TRUE)
    from_f <- min(tabs$inspections$inspection_date, na.rm = TRUE)
    ins <- ef$normalize_inspections(tabs, cfgf, thr_f, from_f)
    est <- ef$normalize_establishments(tabs, ins, cfgf)
    est <- ef$geocode_establishments(est, geocoder = cache_only_geocoder, cache_path = p$geocode_cache)
    out$establishments <- add_tract(ef$attach_geography_food(est, gd))
    out$inspections <- ins
    attr(out$inspections, "from") <- from_f
    attr(out$inspections, "through") <- thr_f
  }

  dir.create(dirname(p$prep_cache), FALSE, TRUE)
  saveRDS(out, p$prep_cache)
  out
}
