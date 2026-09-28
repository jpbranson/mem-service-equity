# Metric computation for the permits pipeline. Specs: specs/permits/*.md.
#
# Every metric is computed per category subgroup, over windows ending on the
# last day the data are complete through, for every area with parcels inside
# the city (a zero is a result). Only permits inside the city limits and not
# excluded in normalization are counted. Demolitions come from a separate
# source (R/demolitions.R, DECISIONS.md D30): they are their own subgroup of
# permits_per_1000_parcels and the numerator of demolition_to_new_ratio,
# never part of "all" or of the declared value, and their windows end on
# the earlier of the two sources' data-through dates. Without them neither
# is computed.

SPEC_VERSIONS <- c(permits_per_1000_parcels = "0.3", declared_value_per_1000_parcels = "0.2",
                   demolition_to_new_ratio = "0.2")

WINDOW_YEARS <- c("12m" = 1L, "5y" = 5L)
MIN_PARCELS <- 250L      # suppression floor for areas with few in-city parcels
MIN_N_VALUE <- 20L       # permits with a declared value, for the value metric
MIN_N_RATIO <- 20L       # demolitions + new construction, for demolition_to_new_ratio
MINOR_VALUE <- 5000      # excl_minor variant: declared value below this is minor
CAP_VALUE <- 1e7         # cap_10m variant
CATEGORIES <- c("new", "renovation", "accessory")
SECTORS <- c("residential", "commercial")

base_permits <- function(pts) {
  df <- if (inherits(pts, "sf")) sf::st_drop_geometry(pts) else pts
  df[is.na(df$exclusion) & df$in_city %in% TRUE, ]
}

window_start_years <- function(through, years)
  seq(as.Date(through) + 1L, by = paste0("-", years, " years"), length.out = 2L)[2]

#' Subgroups: each category and all categories, each for residential,
#' commercial and both sectors ("new_residential", "new", ..., "all").
subgroup_masks <- function(df) {
  out <- list()
  for (cat in c(CATEGORIES, "all")) for (sec in c(SECTORS, "all")) {
    name <- if (cat == "all" && sec == "all") "all" else if (sec == "all") cat else paste(cat, sec, sep = "_")
    out[[name]] <- (cat == "all" | df$category %in% cat) & (sec == "all" | df$sector %in% sec)
  }
  out
}

demolition_mask <- function(df) list(demolition = rep(TRUE, nrow(df)))

# ---- permits per 1,000 parcels ------------------------------------------------

#' @param masks_fun function(df) -> named list of logical subgroup masks.
compute_permit_rates <- function(df, parcels, through, masks_fun = subgroup_masks) {
  out <- list()
  for (w in names(WINDOW_YEARS)) {
    start <- window_start_years(through, WINDOW_YEARS[[w]])
    inwin <- df[df$issue_date >= start & df$issue_date <= through, ]
    for (variant in c("primary", "excl_minor")) {
      # excl_minor drops permits declared under $5,000; an unknown value is kept.
      d <- if (variant == "excl_minor") inwin[is.na(inwin$value) | inwin$value >= MINOR_VALUE, ] else inwin
      masks <- masks_fun(d)
      for (g in intersect(PERMIT_GEOS, names(parcels))) {
        areas <- parcels[[g]]
        sup <- areas$parcels < MIN_PARCELS
        for (s in names(masks)) {
          n <- tabulate(match(d[[g]][masks[[s]]], areas$geo_id), nbins = nrow(areas))
          ci <- memequity::poisson_rate_ci(n, areas$parcels, per = 1000)
          out[[length(out) + 1]] <- data.frame(
            geo_type = g, geo_id = areas$geo_id, subgroup = s, variant = variant, n = n,
            value = ifelse(sup, NA_real_, ci$value), ci_low = ifelse(sup, NA_real_, ci$ci_low),
            ci_high = ifelse(sup, NA_real_, ci$ci_high), suppressed = sup,
            window_start = start, window_end = through, stringsAsFactors = FALSE)
        }
      }
    }
  }
  res <- do.call(rbind, out)
  res$metric <- "permits_per_1000_parcels"
  res
}

# ---- declared value per 1,000 parcels -------------------------------------------

value_row <- function(vals, parcels, variant) {
  n <- length(vals)
  if (n < MIN_N_VALUE || parcels < MIN_PARCELS)
    return(data.frame(value = NA_real_, ci_low = NA_real_, ci_high = NA_real_, n = n, suppressed = TRUE))
  if (variant == "median_per_permit") {
    r <- memequity::metric_median(vals, min_n = MIN_N_VALUE)
    est <- r$value; lo <- r$ci_low; hi <- r$ci_high
  } else {
    ci <- memequity::bootstrap_total_ci(vals)
    est <- sum(vals) / parcels * 1000
    lo <- ci$ci_low / parcels * 1000; hi <- ci$ci_high / parcels * 1000
  }
  # A percentile interval over very skewed values can, rarely, leave out the
  # estimate itself; widen it just enough to include it.
  data.frame(value = est, ci_low = min(lo, est), ci_high = max(hi, est), n = n, suppressed = FALSE)
}

compute_declared_value <- function(df, parcels, through) {
  out <- list()
  for (w in names(WINDOW_YEARS)) {
    start <- window_start_years(through, WINDOW_YEARS[[w]])
    inwin <- df[df$issue_date >= start & df$issue_date <= through & !is.na(df$value), ]
    if (!nrow(inwin)) next
    top1 <- stats::quantile(inwin$value, 0.99, names = FALSE, type = 7)
    variants <- list(
      primary = inwin,
      excl_top1pct = inwin[inwin$value <= top1, ],
      cap_10m = transform(inwin, value = pmin(value, CAP_VALUE)),
      median_per_permit = inwin)
    for (variant in names(variants)) {
      d <- variants[[variant]]
      masks <- subgroup_masks(d)
      for (g in intersect(PERMIT_GEOS, names(parcels))) {
        areas <- parcels[[g]]
        for (s in names(masks)) {
          by_area <- split(d$value[masks[[s]]], factor(d[[g]][masks[[s]]], areas$geo_id))
          rows <- do.call(rbind, lapply(seq_len(nrow(areas)), function(i)
            value_row(by_area[[i]], areas$parcels[i], variant)))
          out[[length(out) + 1]] <- cbind(data.frame(geo_type = g, geo_id = areas$geo_id, subgroup = s,
                                                     variant = variant, stringsAsFactors = FALSE), rows,
                                          window_start = start, window_end = through)
        }
      }
    }
  }
  res <- do.call(rbind, out)
  res$metric <- "declared_value_per_1000_parcels"
  res
}

# ---- demolitions per new-construction permit -------------------------------------

# Wilson interval on p = D / (D + N), carried to the ratio p / (1 - p). With
# no new construction the ratio is undefined and the row is suppressed.
demolition_ratio_row <- function(d, n) {
  r <- memequity::proportion_counts(d, d + n, min_n = MIN_N_RATIO)
  if (r$suppressed || n == 0)
    return(data.frame(value = NA_real_, ci_low = NA_real_, ci_high = NA_real_, n = d + n, suppressed = TRUE))
  odds <- function(p) p / (1 - p)
  data.frame(value = odds(r$value), ci_low = odds(r$ci_low), ci_high = odds(r$ci_high), n = d + n,
             suppressed = FALSE)
}

#' @param demo base_permits() rows of demolitions.
#' @param permits base_permits() rows of DPD permits; new construction in both
#'   sectors is the denominator.
compute_demolition_ratio <- function(demo, permits, parcels, through) {
  out <- list()
  new <- permits[permits$category %in% "new", ]
  for (w in names(WINDOW_YEARS)) {
    start <- window_start_years(through, WINDOW_YEARS[[w]])
    inwin <- function(d) d[d$issue_date >= start & d$issue_date <= through, ]
    dw <- inwin(demo); nw <- inwin(new)
    for (g in intersect(PERMIT_GEOS, names(parcels))) {
      ids <- parcels[[g]]$geo_id
      d <- tabulate(match(dw[[g]], ids), nbins = length(ids))
      n <- tabulate(match(nw[[g]], ids), nbins = length(ids))
      rows <- do.call(rbind, lapply(seq_along(ids), function(i) demolition_ratio_row(d[i], n[i])))
      out[[length(out) + 1]] <- cbind(data.frame(geo_type = g, geo_id = ids, subgroup = "all",
                                                 variant = "primary", stringsAsFactors = FALSE), rows,
                                      window_start = start, window_end = through)
    }
  }
  res <- do.call(rbind, out)
  res$metric <- "demolition_to_new_ratio"
  res
}

#' @param parcels named list geo_type -> data.frame(geo_id, parcels).
#' @param demolitions attach_geography_permits() output for normalize_demolitions()
#'   rows, or NULL; @param demolitions_through the last day that source is complete.
compute_metrics_permits <- function(pts, parcels, through, demolitions = NULL, demolitions_through = NULL) {
  df <- base_permits(pts)
  m <- rbind(compute_permit_rates(df, parcels, through), compute_declared_value(df, parcels, through))
  if (!is.null(demolitions)) {
    dthrough <- min(as.Date(through), as.Date(demolitions_through))
    dd <- base_permits(demolitions)
    rates <- compute_permit_rates(dd, parcels, dthrough, masks_fun = demolition_mask)
    m <- rbind(m, rates, compute_demolition_ratio(dd, df, parcels, dthrough))
  }
  m$metric_version <- SPEC_VERSIONS[m$metric]
  m$citywide_median <- memequity::citywide_reference(m)
  m
}
