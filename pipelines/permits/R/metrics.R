# Metric computation for the permits pipeline. Specs: specs/permits/*.md.
#
# Every metric is computed per category subgroup, over windows ending on the
# last day the data are complete through, for every area with parcels inside
# the city (a zero is a result). Only permits inside the city limits and not
# excluded in normalization are counted. demolition_to_new_ratio is not
# computed: there is no permitted source of demolition permits (H21).

SPEC_VERSIONS <- c(permits_per_1000_parcels = "0.2", declared_value_per_1000_parcels = "0.2",
                   demolition_to_new_ratio = "0.1")

WINDOW_YEARS <- c("12m" = 1L, "5y" = 5L)
MIN_PARCELS <- 250L      # suppression floor for areas with few in-city parcels
MIN_N_VALUE <- 20L       # permits with a declared value, for the value metric
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

# Citywide value for the same metric, variant, subgroup and window (D4).
add_citywide_reference <- function(m) {
  city <- m[m$geo_type == "citywide", ]
  key <- function(d) paste(d$metric, d$variant, d$subgroup, format(as.Date(d$window_start)), sep = "\r")
  m$citywide_median <- city$value[match(key(m), key(city))]
  m
}

# ---- permits per 1,000 parcels ------------------------------------------------

compute_permit_rates <- function(df, parcels, through) {
  out <- list()
  for (w in names(WINDOW_YEARS)) {
    start <- window_start_years(through, WINDOW_YEARS[[w]])
    inwin <- df[df$issue_date >= start & df$issue_date <= through, ]
    for (variant in c("primary", "excl_minor")) {
      # excl_minor drops permits declared under $5,000; an unknown value is kept.
      d <- if (variant == "excl_minor") inwin[is.na(inwin$value) | inwin$value >= MINOR_VALUE, ] else inwin
      masks <- subgroup_masks(d)
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

#' @param parcels named list geo_type -> data.frame(geo_id, parcels).
compute_metrics_permits <- function(pts, parcels, through) {
  df <- base_permits(pts)
  m <- rbind(compute_permit_rates(df, parcels, through), compute_declared_value(df, parcels, through))
  m$metric_version <- SPEC_VERSIONS[m$metric]
  add_citywide_reference(m)
}
