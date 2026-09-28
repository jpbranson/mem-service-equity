# Demolitions: the Data Midsouth snapshot of Shelby County building and
# demolition permits (DECISIONS.md D30). Only its demolition permits are used.
# The snapshot has no issue date: `date_status` is the date of the latest
# status, which is the issue date for a permit still open and the completion
# date for a closed one. Each demolition is dated by it and counted once.

#' Read the snapshot and return one row per demolition permit with canonical
#' field names (config/demolitions.yml). A permit on several rows keeps the
#' row with the latest status date. `attr(, "absent")` lists mapped columns
#' the file lacks.
read_demolitions <- function(path, map) {
  raw <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE,
                         na.strings = c("", "NA"), encoding = "UTF-8")
  cols <- unlist(map$columns)
  absent <- names(cols)[!cols %in% names(raw)]
  d <- as.data.frame(lapply(stats::setNames(cols, names(cols)), function(src)
    if (src %in% names(raw)) trimws(raw[[src]]) else rep(NA_character_, nrow(raw))),
    stringsAsFactors = FALSE)
  d <- d[d$record_type %in% map$demolition_record_type, ]
  d$status_date <- as.Date(d$status_date, format = "%Y-%m-%d")
  d <- d[order(d$permit_id, d$status_date, decreasing = TRUE, na.last = TRUE), ]
  dup <- duplicated(d$permit_id)
  out <- d[!dup, ]
  rownames(out) <- NULL
  attr(out, "file") <- basename(path)
  attr(out, "rows_read") <- nrow(raw)
  attr(out, "duplicate_rows") <- sum(dup)
  attr(out, "absent") <- absent
  out
}

#' @param d data.frame from read_demolitions().
#' @param through last day the snapshot is complete through.
#' @return rows shaped like normalize_permits() output, category "demolition".
normalize_demolitions <- function(d, through) {
  lon <- suppressWarnings(as.numeric(d$longitude))
  lat <- suppressWarnings(as.numeric(d$latitude))
  located <- in_shelby(lon, lat)
  value <- suppressWarnings(as.numeric(d$value))
  exclusion <- rep(NA_character_, nrow(d))
  exclusion[is.na(d$status_date)] <- "missing_status_date"
  exclusion[is.na(exclusion) & d$status_date > through] <- "after_data_through"
  data.frame(
    permit_id = d$permit_id,
    issue_date = d$status_date,
    sector = NA_character_, work = "demolition", category = "demolition",
    value = ifelse(!is.na(value) & value > 0, value, NA_real_),
    longitude = ifelse(located, lon, NA_real_),
    latitude = ifelse(located, lat, NA_real_),
    match_quality = ifelse(located, "source_point", ifelse(is.na(lon) | is.na(lat), "missing", "out_of_area")),
    exclusion = exclusion,
    stringsAsFactors = FALSE)
}
