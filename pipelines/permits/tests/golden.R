# Shared by build_golden.R and the golden-file test, so both read the frozen
# inputs and order the outputs the same way.

# The parcel counts frozen with the golden sample, so an annual parcel refresh
# does not break the golden test.
golden_parcels <- function(dir) {
  d <- utils::read.csv(file.path(dir, "golden_parcels.csv"), stringsAsFactors = FALSE,
                       colClasses = c(geo_type = "character", geo_id = "character"))
  lapply(split(d[, c("geo_id", "parcels")], d$geo_type), function(x) { rownames(x) <- NULL; x })
}

golden_order <- function(m) {
  m <- m[order(m$metric, m$variant, m$subgroup, m$geo_type, m$geo_id, m$window_start),
         c("metric", "variant", "subgroup", "geo_type", "geo_id", "window_start", "value",
           "ci_low", "ci_high", "n", "suppressed")]
  m$window_start <- format(as.Date(m$window_start))
  rownames(m) <- NULL
  m
}
