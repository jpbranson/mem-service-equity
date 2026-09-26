# Fetch: page through the City of Memphis 311 ArcGIS layer.
#
# The layer advertises editing capabilities; this code only ever issues
# read-only `query` requests. Contact fields (names, emails, phones) and free
# text are never requested.

SR_LAYER <- "https://311.memphistn.gov/server/rest/services/311/311_Request_Map_PROD/FeatureServer/0"

SR_FIELDS <- c("OBJECTID", "INCIDENT_NUMBER", "INCIDENT_TYPE_ID", "REQUEST_TYPE", "DEPARTMENT",
               "GROUP_NAME", "REQUEST_STATUS", "Request_Sub_Status", "REQUEST_PRIORITY",
               "REPORTED_DATE", "created_date", "Closed_Date", "RESOLVED_DATE", "last_edited_date",
               "RESOLUTION_CODE", "ZipCode", "cd_name", "scd_name", "SYSREVSTATUS", "LINKED_SR",
               "SCF_URL")

SR_DATE_FIELDS <- c("REPORTED_DATE", "created_date", "Closed_Date", "RESOLVED_DATE", "last_edited_date")

arcgis_page <- function(layer, where, fields, after_oid, page_size) {
  req <- httr2::request(paste0(layer, "/query")) |>
    httr2::req_url_query(
      where = sprintf("(%s) AND OBJECTID > %d", where, after_oid),
      outFields = paste(fields, collapse = ","), outSR = 4326, returnGeometry = "true",
      orderByFields = "OBJECTID ASC", resultRecordCount = page_size, f = "json") |>
    httr2::req_user_agent("memphis-service-equity (https://github.com/jpbranson/mem-service-equity)") |>
    httr2::req_retry(max_tries = 5, backoff = function(i) 2^i) |>
    httr2::req_timeout(120)
  # Retries dropped connections and ArcGIS errors returned with HTTP 200.
  body <- memequity::arcgis_json(req)
  feats <- body$features
  if (!length(feats) || !NROW(feats$attributes)) return(NULL)
  out <- feats$attributes
  out$longitude <- if (!is.null(feats$geometry)) feats$geometry$x else NA_real_
  out$latitude <- if (!is.null(feats$geometry)) feats$geometry$y else NA_real_
  out
}

#' Fetch all 311 requests (or those matching `where`).
fetch_311 <- function(where = "1=1", page_size = 2000L, layer = SR_LAYER, verbose = TRUE) {
  pages <- list(); after <- 0L
  repeat {
    p <- arcgis_page(layer, where, SR_FIELDS, after, page_size)
    if (is.null(p)) break
    pages[[length(pages) + 1]] <- p
    after <- max(p$OBJECTID)
    if (verbose && length(pages) %% 25 == 0) message("  fetched ", sum(vapply(pages, nrow, 1L)), " rows")
    if (nrow(p) < page_size) break
  }
  if (!length(pages)) stop("311 fetch returned no rows", call. = FALSE)
  out <- do.call(rbind, lapply(pages, function(p) {
    for (f in setdiff(c(SR_FIELDS, "longitude", "latitude"), names(p))) p[[f]] <- NA
    p[, c(SR_FIELDS, "longitude", "latitude")]
  }))
  # ArcGIS dates are epoch milliseconds (UTC).
  for (f in SR_DATE_FIELDS)
    out[[f]] <- as.POSIXct(as.numeric(out[[f]]) / 1000, origin = "1970-01-01", tz = "UTC")
  out
}

#' Layer record count, for the fetch-completeness check.
count_311 <- function(where = "1=1", layer = SR_LAYER) {
  req <- httr2::request(paste0(layer, "/query")) |>
    httr2::req_url_query(where = where, returnCountOnly = "true", f = "json") |>
    httr2::req_retry(max_tries = 5)
  memequity::arcgis_json(req)$count
}
