# Output schema (design plan section 8). Every pipeline writes the same files
# through these functions; the front end reads nothing else.

#' Columns of every metrics_<pipeline>_by_<geography>.csv, in order.
#'
#' `variant` extends the section 8 schema: it names the threshold variant
#' (e.g. "primary", "window_0_10") so the sensitivity versions required by 5.1
#' sit in the same file as the primary series.
#' `citywide_median` is the citywide reference for the same metric, variant
#' and window: the citywide median for median metrics, the citywide pooled
#' value for proportions and rates.
#' @export
METRICS_COLUMNS <- c("geo_type", "geo_id", "metric", "metric_version", "variant",
                     "window_start", "window_end", "value", "ci_low", "ci_high", "n",
                     "suppressed", "citywide_median", "computed_at", "data_current_through")

METRICS_KEY <- c("geo_type", "geo_id", "metric", "metric_version", "variant",
                 "window_start", "window_end")

#' Geography types a metrics file may use.
#' @export
GEO_TYPES <- c("citywide", "zcta", "council_district", "commission_district", "tract",
               "h3_8", "h3_9", "reference_neighborhood", "route", "stop",
               "outage_polygon", "establishment", "street_segment")

#' Assemble metric rows into the standard schema.
#'
#' @param rows data.frame with at least geo_type, geo_id, metric, value,
#'   ci_low, ci_high, n, suppressed, window_start, window_end.
#' @export
as_metrics_table <- function(rows, metric_version, data_current_through,
                             computed_at = format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ")) {
  if (!"variant" %in% names(rows)) rows$variant <- "primary"
  if (!"citywide_median" %in% names(rows)) rows$citywide_median <- NA_real_
  if (!"metric_version" %in% names(rows)) rows$metric_version <- metric_version
  rows$computed_at <- computed_at
  rows$data_current_through <- format(as.Date(data_current_through))
  rows$window_start <- format(as.Date(rows$window_start))
  rows$window_end <- format(as.Date(rows$window_end))
  missing <- setdiff(METRICS_COLUMNS, names(rows))
  if (length(missing)) stop("Metric rows missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  out <- as.data.frame(rows)[, METRICS_COLUMNS]
  # Suppressed rows never carry a number.
  out$value[out$suppressed] <- NA
  out$ci_low[out$suppressed] <- NA
  out$ci_high[out$suppressed] <- NA
  out
}

#' Validate a metrics table against the output contract. Returns a character
#' vector of problems (empty when valid).
#' @export
metrics_problems <- function(df) {
  p <- character()
  if (!identical(names(df), METRICS_COLUMNS))
    return(paste("columns must be exactly:", paste(METRICS_COLUMNS, collapse = ", ")))
  if (any(!df$geo_type %in% GEO_TYPES))
    p <- c(p, paste("unknown geo_type:", paste(unique(setdiff(df$geo_type, GEO_TYPES)), collapse = ", ")))
  if (anyNA(df$suppressed)) p <- c(p, "suppressed must be TRUE/FALSE")
  sup <- df$suppressed %in% TRUE
  if (any(sup & !is.na(df$value))) p <- c(p, "suppressed rows carry a value")
  pub <- !sup
  if (any(pub & (is.na(df$value) | is.na(df$ci_low) | is.na(df$ci_high))))
    p <- c(p, "published rows missing value or interval")
  eps <- 1e-9
  if (any(pub & (df$ci_low > df$value + eps | df$ci_high < df$value - eps), na.rm = TRUE))
    p <- c(p, "value outside its interval")
  if (any(is.na(df$n) | df$n < 0)) p <- c(p, "n missing or negative")
  if (any(as.Date(df$window_start) > as.Date(df$window_end)))
    p <- c(p, "window_start after window_end")
  if (any(is.na(df$data_current_through))) p <- c(p, "data_current_through missing")
  if (anyDuplicated(df[, METRICS_KEY])) p <- c(p, "duplicate metric keys")
  p
}

#' Write metrics_<pipeline>_by_<geography>.csv after validating it.
#' @export
write_metrics <- function(df, pipeline, geography, dir) {
  probs <- metrics_problems(df)
  if (length(probs)) stop("Metrics table invalid: ", paste(probs, collapse = "; "), call. = FALSE)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, sprintf("metrics_%s_by_%s.csv", pipeline, geography))
  utils::write.csv(df, path, row.names = FALSE, na = "")
  invisible(path)
}

#' Write points_<pipeline>.geojson: the minimum fields for radius queries and
#' display, plus geocode match quality. Unlocated points are dropped.
#' @export
write_points <- function(points, pipeline, dir, fields) {
  if (!"match_quality" %in% names(points)) stop("points need a match_quality column", call. = FALSE)
  keep <- !sf::st_is_empty(points)
  pts <- sf::st_transform(points[keep, unique(c(fields, "match_quality"))], MSE_CRS_LONLAT)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, sprintf("points_%s.geojson", pipeline))
  if (file.exists(path)) unlink(path)
  sf::st_write(pts, path, driver = "GeoJSON", quiet = TRUE,
               layer_options = c("COORDINATE_PRECISION=6", "RFC7946=YES"))
  invisible(path)
}
