# Fetch: page through the City's DPD Building Permits layer on the Memphis
# Data Hub (docs/research/311-permits-districts.md). Read-only `query`
# requests only. The free-text Description field is never requested.
# Data Midsouth is not used: its robots.txt forbids automated access (D24).

PERMITS_LAYER <- paste0("https://services2.arcgis.com/saWmpKJIUAjyyNVc/arcgis/rest/services/",
                        "DPD_Building_Permits/FeatureServer/0")

PERMIT_FIELDS <- c("ObjectId", "Record_ID", "Issued_Date", "Sub_Type", "Construction_Type",
                   "Valuation", "Address", "City", "ZIP_Code", "State", "Latitude", "Longitude")

UA <- "memphis-service-equity (https://github.com/jpbranson/mem-service-equity)"

permits_request <- function(path, ..., layer = PERMITS_LAYER) {
  httr2::request(paste0(layer, path)) |>
    httr2::req_url_query(..., f = "json") |>
    httr2::req_user_agent(UA) |>
    httr2::req_retry(max_tries = 5, backoff = function(i) 2^i) |>
    httr2::req_timeout(120)
}

# Retries dropped connections and ArcGIS errors returned with HTTP 200.
perform_json <- function(req) memequity::arcgis_json(req)

#' Fetch every permit. Dates come back as epoch milliseconds (UTC).
fetch_permits <- function(layer = PERMITS_LAYER, page_size = 1000L, verbose = TRUE) {
  pages <- list(); after <- 0L
  repeat {
    b <- perform_json(permits_request("/query", where = sprintf("ObjectId > %d", after),
                                      outFields = paste(PERMIT_FIELDS, collapse = ","),
                                      orderByFields = "ObjectId ASC", resultRecordCount = page_size,
                                      returnGeometry = "false", layer = layer))
    a <- b$features$attributes
    if (!NROW(a)) break
    pages[[length(pages) + 1]] <- a
    after <- max(a$ObjectId)
    if (verbose && length(pages) %% 10 == 0) message("  fetched ", sum(vapply(pages, nrow, 1L)), " permits")
  }
  if (!length(pages)) stop("permits fetch returned no rows", call. = FALSE)
  out <- do.call(rbind, lapply(pages, function(p) {
    for (f in setdiff(PERMIT_FIELDS, names(p))) p[[f]] <- NA
    p[, PERMIT_FIELDS]
  }))
  out$Issued_Date <- as.POSIXct(as.numeric(out$Issued_Date) / 1000, origin = "1970-01-01", tz = "UTC")
  out
}

#' Layer record count and the time of its last data edit, for the
#' completeness check and the data-through date.
permits_layer_info <- function(layer = PERMITS_LAYER) {
  count <- perform_json(permits_request("/query", where = "1=1", returnCountOnly = "true",
                                        layer = layer))$count
  meta <- perform_json(permits_request("", layer = layer))
  edited <- meta$editingInfo$dataLastEditDate %||% meta$editingInfo$lastEditDate
  list(count = count,
       last_edit = if (is.null(edited)) NA else
         as.POSIXct(edited / 1000, origin = "1970-01-01", tz = "UTC"))
}

`%||%` <- function(a, b) if (is.null(a)) b else a
