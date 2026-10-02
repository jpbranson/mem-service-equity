# Metric computation for the MLGW pipeline. Specs: specs/mlgw/*.md (v0.2,
# restated for point outages, awaiting H19).
#
# Unit: an outage event (R/events.R), placed at its first observed point.
# Only events inside the city count, as in the other pipelines.
# Geographies: citywide, ZCTA, council district, and for event counts the
# H3 resolution-9 disk around an address (DECISIONS.md D16).

SPEC_VERSIONS <- c(outage_events_per_year = "0.2", customer_hours_per_1000 = "0.2",
                   restoration_vs_estimate = "0.2")
WINDOW_DAYS <- c("12m" = 365L)
AREA_GEOS <- c("citywide", "zcta", "council_district")
MIN_POPULATION <- 1000      # customer_hours_per_1000 (spec min_population)
MIN_N_RESTORATION <- 20L

# outage_events_per_year thresholds (spec "minimum event size").
EVENT_VARIANTS <- list(
  primary = function(e) e$max_cust >= 1,
  min_10_customers = function(e) e$max_cust >= 10,
  min_5_minutes = function(e) e$duration_s >= 300)

# restoration_vs_estimate reference estimates (spec "reference estimate").
ETR_VARIANTS <- c(primary = "first_etr", etr_60m = "etr_60m", final_etr = "final_etr")

#' Unplanned events form "all"; planned outages are their own series.
SUBGROUPS <- list(all = function(e) !e$planned, planned = function(e) e$planned)

in_window <- function(ev, through, days) {
  d <- as.Date(format(ev$start, tz = "America/Chicago", "%Y-%m-%d"))
  ev[d > through - days & d <= through]
}

# One row per event and geography it falls in (geo_type, geo_id).
explode_areas <- function(ev) {
  rbindlist(lapply(AREA_GEOS, function(g) {
    d <- ev[!is.na(ev[[g]])]
    if (nrow(d)) d[, `:=`(geo_type = g, geo_id = d[[g]])]
    d
  }), fill = TRUE)
}

# Every area gets a row, so an area with no outages reads 0, not missing.
with_all_areas <- function(r, areas, fill) {
  all <- rbindlist(lapply(names(areas), function(g) data.table(geo_type = g, geo_id = areas[[g]])))
  r <- merge(all, r, by = c("geo_type", "geo_id"), all = TRUE)
  for (col in names(fill)) set(r, which(is.na(r[[col]])), col, fill[[col]])
  r
}

# Per-cell counts summed over each cell's disk (D16): the row for a cell
# covers the cell and its six neighbours.
hex_counts <- function(ev) {
  d <- ev[!is.na(h3_9)]
  if (!nrow(d)) return(data.table(geo_id = character(), n = integer()))
  per <- d[, .(n = .N), by = .(member = h3_9)]
  targets <- unique(unlist(h3jsr::get_disk(per$member, ring_size = 1L)))
  disks <- h3jsr::get_disk(targets, ring_size = 1L)
  pairs <- data.table(target = rep(targets, lengths(disks)), member = unlist(disks))
  pairs[per, on = "member", nomatch = NULL][, .(n = sum(n)), by = .(geo_id = target)]
}

# ---- outage events per year ---------------------------------------------------

#' Counts with an exact Poisson interval, scaled to a year. min_n is 0, so no
#' row is suppressed. No citywide reference: a citywide count is not
#' comparable with an area's count.
compute_events <- function(ev, areas, through, windows = WINDOW_DAYS) {
  out <- list()
  for (w in names(windows)) {
    days <- windows[[w]]
    e <- in_window(ev, through, days)
    for (v in names(EVENT_VARIANTS)) for (sg in names(SUBGROUPS)) {
      d <- if (nrow(e)) e[EVENT_VARIANTS[[v]](e) & SUBGROUPS[[sg]](e)] else e
      r <- if (nrow(d)) explode_areas(d)[, .(n = .N), by = .(geo_type, geo_id)] else
        data.table(geo_type = character(), geo_id = character(), n = integer())
      r <- with_all_areas(r, areas, list(n = 0L))
      h <- hex_counts(d)
      if (nrow(h)) r <- rbind(r, h[, .(geo_type = "h3_9", geo_id, n)])
      ci <- memequity::poisson_rate_ci(r$n, exposure = days / 365)
      r[, `:=`(value = ci$value, ci_low = ci$ci_low, ci_high = ci$ci_high, suppressed = FALSE,
               variant = v, subgroup = sg, window_start = through - days + 1, window_end = through)]
      out[[length(out) + 1]] <- r
    }
  }
  res <- rbindlist(out)
  if (nrow(res)) res[, `:=`(metric = "outage_events_per_year", citywide_median = NA_real_)]
  res[]
}

# ---- customer-hours per 1,000 customers -----------------------------------------

#' Customer-hours over ACS households inside the city (D20), per 1,000 and
#' per year. The value uses the midpoint of each restoration; the interval
#' is the spec's poll-timing bounds: restoration right after the last
#' snapshot showing the outage (low) or right before the first without it
#' (high). It does not include the households' margin of error.
#' @param denominators data.table(geo_type, geo_id, households, population).
compute_customer_hours <- function(ev, denominators, through, windows = WINDOW_DAYS) {
  areas <- split(denominators$geo_id, denominators$geo_type)
  out <- list()
  for (w in names(windows)) {
    days <- windows[[w]]
    e <- in_window(ev, through, days)
    for (sg in names(SUBGROUPS)) {
      d <- if (nrow(e)) e[SUBGROUPS[[sg]](e)] else e
      r <- if (nrow(d)) explode_areas(d)[, .(n = .N, lo = sum(cust_hours_lo), hi = sum(cust_hours_hi)),
                                         by = .(geo_type, geo_id)] else
        data.table(geo_type = character(), geo_id = character(), n = integer(), lo = numeric(), hi = numeric())
      r <- with_all_areas(r, areas, list(n = 0L, lo = 0, hi = 0))
      r <- merge(r, denominators, by = c("geo_type", "geo_id"), all.x = TRUE)
      k <- 1000 * 365 / days
      r[, suppressed := is.na(population) | population < MIN_POPULATION | is.na(households) | households <= 0]
      r[, `:=`(value = fifelse(suppressed, NA_real_, (lo + hi) / 2 / households * k),
               ci_low = fifelse(suppressed, NA_real_, lo / households * k),
               ci_high = fifelse(suppressed, NA_real_, hi / households * k))]
      r[, `:=`(variant = "primary", subgroup = sg, window_start = through - days + 1, window_end = through)]
      out[[length(out) + 1]] <- r[, .(geo_type, geo_id, n, value, ci_low, ci_high, suppressed,
                                      variant, subgroup, window_start, window_end)]
    }
  }
  res <- rbindlist(out)
  if (nrow(res)) res[, metric := "customer_hours_per_1000"]
  res[]
}

# ---- restoration vs. estimate ------------------------------------------------------

#' Median minutes between the midpoint restoration and the reference
#' estimate (positive: later than estimated), with a bootstrap interval.
#' Unplanned events only, with an estimate and a confirmed restoration that
#' does not fall in a poller gap of more than 30 minutes.
compute_restoration <- function(ev, areas, through, windows = WINDOW_DAYS) {
  out <- list()
  for (w in names(windows)) {
    days <- windows[[w]]
    e <- in_window(ev, through, days)
    e <- e[!planned & confirmed & restoration_span_s <= RESTORATION_SPAN_MAX_S]
    for (v in names(ETR_VARIANTS)) {
      col <- ETR_VARIANTS[[v]]
      d <- e[!is.na(e[[col]])]
      d[, late_min := as.numeric(restored_mid - d[[col]], units = "mins")]
      x <- explode_areas(d)
      r <- if (nrow(x)) x[, {
        m <- memequity::metric_median(late_min, min_n = MIN_N_RESTORATION)
        list(value = m$value, ci_low = m$ci_low, ci_high = m$ci_high, n = m$n, suppressed = m$suppressed)
      }, by = .(geo_type, geo_id)] else
        data.table(geo_type = character(), geo_id = character(), value = numeric(), ci_low = numeric(),
                   ci_high = numeric(), n = integer(), suppressed = logical())
      r <- with_all_areas(r, areas, list(n = 0L, suppressed = TRUE))
      r[, `:=`(variant = v, subgroup = "all", window_start = through - days + 1, window_end = through)]
      out[[length(out) + 1]] <- r
    }
  }
  res <- rbindlist(out)
  if (nrow(res)) res[, metric := "restoration_vs_estimate"]
  res[]
}

#' All three metrics, with versions and citywide references.
#' @param ev events with citywide, zcta, council_district and h3_9 columns,
#'   inside the city only.
#' @param denominators data.table(geo_type, geo_id, households, population)
#'   for every in-city area.
compute_metrics_mlgw <- function(ev, denominators, through, windows = WINDOW_DAYS) {
  areas <- split(denominators$geo_id, denominators$geo_type)
  areas <- areas[intersect(AREA_GEOS, names(areas))]
  m <- rbindlist(list(
    compute_events(ev, areas, through, windows),
    compute_customer_hours(ev, denominators, through, windows),
    compute_restoration(ev, areas, through, windows)), fill = TRUE)
  if (!nrow(m)) return(m)
  m[, metric_version := SPEC_VERSIONS[metric]]
  ref <- memequity::citywide_reference(m)
  m[, citywide_median := fifelse(metric == "outage_events_per_year", NA_real_, ref)]
  m[]
}
