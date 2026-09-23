# Demographic context and denominators (design plan section 7, DECISIONS D20).
#
# geography/fetch_demographics.R apportions ACS 5-year block-group estimates
# to every geography through 2020 Census blocks and writes one long file of
# components (estimate and margin of error per ACS variable). The functions
# here read that file and derive the published measures, carrying margins of
# error with the Census Bureau's approximation formulas.

#' Margin of error of a sum of independent estimates (Census approximation).
#' @export
acs_moe_sum <- function(moe) sqrt(sum(moe^2))

#' Margin of error of a ratio `num / den` where the numerator is not a subset
#' of the denominator (e.g. aggregate income per resident).
#' @export
acs_moe_ratio <- function(num, den, moe_num, moe_den) {
  r <- num / den
  sqrt(moe_num^2 + r^2 * moe_den^2) / den
}

#' Margin of error of a proportion `num / den` where the numerator is a
#' subset of the denominator. Falls back to the ratio formula when the value
#' under the square root is negative, as the Census Bureau advises.
#' @export
acs_moe_prop <- function(num, den, moe_num, moe_den) {
  p <- num / den
  rad <- moe_num^2 - p^2 * moe_den^2
  ifelse(rad < 0, sqrt(moe_num^2 + p^2 * moe_den^2), sqrt(pmax(rad, 0))) / den
}

#' Reliability class from the coefficient of variation (CV = (MOE / 1.645) /
#' estimate): "high" below 12%, "medium" from 12% to 40%, "low" above 40%.
#' These are the thresholds commonly used for ACS estimates (e.g. by Esri).
#' @export
acs_reliability <- function(estimate, moe) {
  cv <- (moe / 1.645) / abs(estimate)
  out <- ifelse(cv < 0.12, "high", ifelse(cv <= 0.40, "medium", "low"))
  out[is.na(cv) | !is.finite(cv)] <- NA_character_
  out[!is.na(moe) & moe == 0 & !is.na(estimate)] <- "high"
  out
}

#' The demographics registry: which components file is current, its source
#' and vintages.
#' @export
demographics_registry <- function(dir = geography_dir()) {
  utils::read.csv(file.path(dir, "demographics", "registry.csv"), stringsAsFactors = FALSE)
}

#' The published demographic measures: id, label, unit, numerator (ACS
#' variables joined by "+"), denominator and a note.
#' @export
demographic_measures <- function(dir = geography_dir()) {
  utils::read.csv(file.path(dir, "demographics", "measures.csv"), stringsAsFactors = FALSE,
                  colClasses = "character", na.strings = character())
}

#' Apportioned ACS components (long: geo_type, geo_id, variable, estimate,
#' moe) for one geography, or all of them when `geo_type` is NULL.
#' @export
load_demographic_components <- function(geo_type = NULL, dir = geography_dir()) {
  reg <- demographics_registry(dir)
  d <- utils::read.csv(file.path(dir, "demographics", reg$file[1]), stringsAsFactors = FALSE,
                       colClasses = c(geo_type = "character", geo_id = "character"))
  if (!is.null(geo_type)) {
    if (!geo_type %in% d$geo_type) stop("No demographics for geo_type: ", geo_type, call. = FALSE)
    d <- d[d$geo_type == geo_type, ]
  }
  d
}

#' Derive the published measures from components.
#'
#' @param components long data.frame from load_demographic_components().
#' @param measures from demographic_measures().
#' @return data.frame: geo_type, geo_id, measure, value, moe, reliability.
#' @export
derive_demographics <- function(components, measures) {
  key <- paste(components$geo_type, components$geo_id, sep = "\r")
  if (anyDuplicated(paste(key, components$variable)))
    stop("components must have one row per area and variable", call. = FALSE)
  est <- tapply(components$estimate, list(key, components$variable), sum)
  moe <- tapply(components$moe, list(key, components$variable), sum)
  sum_of <- function(spec, m) {
    vars <- strsplit(spec, "+", fixed = TRUE)[[1]]
    miss <- setdiff(vars, colnames(est))
    if (length(miss)) stop("Missing ACS variables: ", paste(miss, collapse = ", "), call. = FALSE)
    if (m == "estimate") rowSums(est[, vars, drop = FALSE])
    else sqrt(rowSums(moe[, vars, drop = FALSE]^2))
  }
  out <- lapply(seq_len(nrow(measures)), function(i) {
    ms <- measures[i, ]
    n <- sum_of(ms$numerator, "estimate"); n_moe <- sum_of(ms$numerator, "moe")
    if (!nzchar(ms$denominator)) {
      v <- n; v_moe <- n_moe
    } else {
      d <- sum_of(ms$denominator, "estimate"); d_moe <- sum_of(ms$denominator, "moe")
      v <- ifelse(d > 0, n / d, NA_real_)
      v_moe <- if (ms$unit == "proportion") acs_moe_prop(n, d, n_moe, d_moe)
               else acs_moe_ratio(n, d, n_moe, d_moe)
      v_moe[is.na(v)] <- NA_real_
    }
    parts <- do.call(rbind, strsplit(rownames(est), "\r", fixed = TRUE))
    data.frame(geo_type = parts[, 1], geo_id = parts[, 2], measure = ms$id,
               value = unname(v), moe = unname(v_moe),
               reliability = acs_reliability(unname(v), unname(v_moe)),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

#' Demographic measures for one geography (e.g. "zcta"), for the part of
#' each area inside the City of Memphis.
#' @export
load_demographics <- function(geo_type, dir = geography_dir()) {
  derive_demographics(load_demographic_components(geo_type, dir), demographic_measures(dir))
}

#' Residents per area (ACS population inside city limits), for rate
#' denominators: data.frame geo_id, population, moe.
#' @export
area_population <- function(geo_type, dir = geography_dir()) {
  d <- load_demographic_components(geo_type, dir)
  d <- d[d$variable == "B01003_001", ]
  data.frame(geo_id = d$geo_id, population = d$estimate, moe = d$moe, stringsAsFactors = FALSE)
}

#' Split block-group components across geographies through blocks.
#'
#' @param bg data.frame: bg (12-digit GEOID), variable, estimate, moe.
#' @param blocks data.frame: bg, weight_pop, weight_hu (each block's share of
#'   its block group's 2020 population / housing units; each sums to 1 per
#'   block group), plus one column per geography holding the block's geo_id
#'   (NA when the block is in none).
#' @param geo_cols names of the geography columns in `blocks`.
#' @param hu_vars ACS variables apportioned by housing units rather than
#'   population.
#' @return long data.frame geo_type, geo_id, variable, estimate, moe. Pieces of
#'   one block group inside one area are fully correlated, so they are summed
#'   first; different block groups are treated as independent.
#' @export
apportion_block_groups <- function(bg, blocks, geo_cols, hu_vars = character()) {
  out <- list()
  for (g in geo_cols) {
    b <- blocks[!is.na(blocks[[g]]), ]
    if (!nrow(b)) next
    w <- stats::aggregate(cbind(weight_pop, weight_hu) ~ bg + geo, data =
                            data.frame(bg = b$bg, geo = b[[g]], weight_pop = b$weight_pop,
                                       weight_hu = b$weight_hu), FUN = sum)
    m <- merge(w, bg, by = "bg")
    wt <- ifelse(m$variable %in% hu_vars, m$weight_hu, m$weight_pop)
    m$e <- m$estimate * wt
    m$m2 <- (m$moe * wt)^2
    # na.pass: a missing estimate or MOE makes the area's value missing
    # rather than silently too small.
    a <- stats::aggregate(cbind(e, m2) ~ geo + variable, data = m, FUN = sum, na.action = stats::na.pass)
    out[[g]] <- data.frame(geo_type = g, geo_id = a$geo, variable = a$variable,
                           estimate = a$e, moe = sqrt(a$m2), stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}
