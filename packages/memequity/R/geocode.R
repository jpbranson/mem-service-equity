# Geocoding (design plan section 7): U.S. Census Bureau geocoder as primary,
# Nominatim as fallback, every result cached with its match quality.

CENSUS_BATCH_URL <- "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"
CENSUS_ONELINE_URL <- "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
NOMINATIM_URL <- "https://nominatim.openstreetmap.org/search"
CENSUS_BATCH_LIMIT <- 10000L

#' Match-quality levels, best first. Spatial metrics accept `exact` and
#' `non_exact` by default; anything else is counted as unlocated.
#' @export
MATCH_QUALITY_LEVELS <- c("exact", "non_exact", "nominatim", "tie", "no_match")

#' Normalise an address string for use as a cache key.
#' @export
normalize_address <- function(x) {
  x <- toupper(trimws(x))
  x <- gsub("[.,#]", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

empty_geocode_cache <- function() {
  data.frame(address_key = character(), longitude = numeric(), latitude = numeric(),
             match_quality = character(), matched_address = character(),
             geocoder = character(), geocoded_at = character(), stringsAsFactors = FALSE)
}

#' Read the geocode cache (a CSV keyed by normalised address).
#' @export
read_geocode_cache <- function(path) {
  if (!file.exists(path)) return(empty_geocode_cache())
  utils::read.csv(path, stringsAsFactors = FALSE,
                  colClasses = c(address_key = "character", match_quality = "character",
                                 matched_address = "character", geocoder = "character",
                                 geocoded_at = "character"))
}

#' Parse the Census batch geocoder's headerless CSV response.
#' @export
parse_census_batch <- function(text) {
  if (!nzchar(trimws(text))) return(empty_geocode_cache()[0, ])
  raw <- utils::read.csv(text = text, header = FALSE, stringsAsFactors = FALSE,
                         colClasses = "character", fill = TRUE, col.names = paste0("V", 1:8))
  coords <- strsplit(raw$V6, ",", fixed = TRUE)
  lon <- suppressWarnings(as.numeric(vapply(coords, function(v) if (length(v) == 2) v[1] else NA_character_, "")))
  lat <- suppressWarnings(as.numeric(vapply(coords, function(v) if (length(v) == 2) v[2] else NA_character_, "")))
  status <- toupper(raw$V3)
  type <- toupper(raw$V4)
  quality <- ifelse(status == "MATCH" & type == "EXACT", "exact",
             ifelse(status == "MATCH", "non_exact",
             ifelse(status == "TIE", "tie", "no_match")))
  data.frame(id = raw$V1, longitude = lon, latitude = lat, match_quality = quality,
             matched_address = raw$V5, stringsAsFactors = FALSE)
}

#' Geocode addresses with the Census batch geocoder, using and updating a cache.
#'
#' @param street,city,state,zip character vectors of equal length.
#' @param cache_path CSV cache; new results are appended.
#' @param fallback if TRUE, addresses the Census geocoder cannot match are
#'   retried with Nominatim (1 request/second, per its usage policy).
#' @return data.frame with longitude, latitude, match_quality,
#'   matched_address, geocoder, aligned with the inputs.
#' @export
geocode_addresses <- function(street, city = "Memphis", state = "TN", zip = "",
                              cache_path = NULL, fallback = FALSE,
                              benchmark = "Public_AR_Current") {
  n <- length(street)
  city <- rep_len(city, n); state <- rep_len(state, n); zip <- rep_len(zip, n)
  full <- paste(street, city, state, zip)
  key <- normalize_address(full)
  cache <- if (is.null(cache_path)) empty_geocode_cache() else read_geocode_cache(cache_path)
  todo <- unique(key[!key %in% cache$address_key])
  if (length(todo)) {
    first <- match(todo, key)
    new <- census_batch(street[first], city[first], state[first], zip[first], todo, benchmark)
    if (fallback) {
      miss <- new$match_quality %in% c("no_match", "tie")
      for (i in which(miss)) {
        nm <- nominatim_one(full[first[i]])
        if (!is.null(nm)) new[i, c("longitude", "latitude", "match_quality", "matched_address", "geocoder")] <-
          list(nm$longitude, nm$latitude, "nominatim", nm$matched_address, "nominatim")
      }
    }
    cache <- rbind(cache, new)
    if (!is.null(cache_path)) {
      dir.create(dirname(cache_path), showWarnings = FALSE, recursive = TRUE)
      utils::write.csv(cache, cache_path, row.names = FALSE)
    }
  }
  out <- cache[match(key, cache$address_key), c("longitude", "latitude", "match_quality",
                                                 "matched_address", "geocoder")]
  rownames(out) <- NULL
  out
}

census_batch <- function(street, city, state, zip, keys, benchmark) {
  chunks <- split(seq_along(keys), ceiling(seq_along(keys) / CENSUS_BATCH_LIMIT))
  res <- lapply(chunks, function(ix) {
    tmp <- tempfile(fileext = ".csv")
    on.exit(unlink(tmp))
    utils::write.table(data.frame(ix, street[ix], city[ix], state[ix], zip[ix]), tmp,
                       sep = ",", col.names = FALSE, row.names = FALSE, qmethod = "double")
    resp <- httr2::request(CENSUS_BATCH_URL) |>
      httr2::req_body_multipart(addressFile = curl::form_file(tmp), benchmark = benchmark) |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_timeout(600) |>
      httr2::req_perform()
    parsed <- parse_census_batch(httr2::resp_body_string(resp))
    parsed[match(as.character(ix), parsed$id), ]
  })
  parsed <- do.call(rbind, res)
  data.frame(address_key = keys, longitude = parsed$longitude, latitude = parsed$latitude,
             match_quality = ifelse(is.na(parsed$match_quality), "no_match", parsed$match_quality),
             matched_address = parsed$matched_address, geocoder = "census",
             geocoded_at = format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
             stringsAsFactors = FALSE)
}

nominatim_one <- function(address) {
  Sys.sleep(1)
  resp <- tryCatch(
    httr2::request(NOMINATIM_URL) |>
      httr2::req_url_query(q = address, format = "jsonv2", limit = 1, countrycodes = "us") |>
      httr2::req_user_agent("memphis-service-equity (https://github.com/jpbranson/mem-service-equity)") |>
      httr2::req_perform(),
    error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  body <- httr2::resp_body_json(resp)
  if (!length(body)) return(NULL)
  list(longitude = as.numeric(body[[1]]$lon), latitude = as.numeric(body[[1]]$lat),
       matched_address = body[[1]]$display_name)
}
