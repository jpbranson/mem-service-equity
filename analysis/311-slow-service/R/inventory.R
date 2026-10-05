# The data inventory in the report: every candidate source, its unit, coverage,
# denominator and the quality issues that decided whether it was used.
# Counts are computed here, so the report never restates a number by hand.

fmt_n <- function(x) formatC(x, format = "d", big.mark = ",")
fmt_d <- function(x) format(as.Date(x), "%b %Y")

per_tract <- function(tract, all_tracts) {
  v <- as.integer(table(factor(tract, all_tracts)))
  c(median = stats::median(v), q90 = unname(stats::quantile(v, 0.9)))
}

data_inventory <- function(x, p) {
  tracts <- unique(memequity::load_demographic_components("tract")$geo_id)
  sr <- x$sr
  inc <- sr[is.na(sr$exclusion) & sr$in_city %in% TRUE, ]
  base <- inc[is.na(inc$duplicate_of), ]
  cl <- base[base$state == "closed", ]
  miss <- tapply(!is.na(cl$close_problem), format(cl$open_date, "%Y-%m"), mean)
  rows <- list()
  add <- function(...) rows[[length(rows) + 1]] <<- list(...)

  add(source = "311 service requests", origin = "City of Memphis 311 layer (offline copy of 25 Sep 2026)",
      unit = "One request, at its reported location", kind = "Events (points)",
      time = sprintf("%s to %s", fmt_d(min(base$open_date)), fmt_d(max(base$open_date))),
      volume = sprintf("%s requests inside the city, after removing %s City-marked duplicates and %s near-duplicates (D6)",
                       fmt_n(nrow(base)), fmt_n(sum(sr$exclusion %in% "city_duplicate")),
                       fmt_n(sum(!is.na(inc$duplicate_of)))),
      denominator = "None needed: each request is compared with its own type. Requests per resident use ACS population.",
      quality = sprintf("Missing close dates cluster in time: %s of closed requests opened in Dec 2025, %s in Jan 2026, %s in Jun-Aug 2026. %s requests (%s) have no usable location. Resolution codes are undocumented.",
                        pct(miss[["2025-12"]]), pct(miss[["2026-01"]]),
                        pct(mean(!is.na(cl$close_problem[cl$open_date >= as.Date("2026-06-01") & cl$open_date <= as.Date("2026-08-31")])), 1),
                        fmt_n(sum(!sr$located)), pct(mean(!sr$located), 1)),
      used = "Primary data")
  add(source = "Published 311 area metrics", origin = "pipelines/311 outputs (data/published/311)",
      unit = "Area × request type × period", kind = "Area medians, shares and rates",
      time = "Rolling 90-day and 12-month windows ending 24 Sep 2026",
      volume = "ZIP (33), council district (7), super district (2), reference neighborhood (8), H3 cells",
      denominator = "Requests; ACS residents for requests per 1,000",
      quality = "The 12-month window includes Dec 2025-Jan 2026, when about half of closed requests lack a close date. Each H3 row pools a cell with its six neighbors (D16), so neighboring rows overlap and cannot be tested for clustering.",
      used = "Not used; recomputed per tract from the requests")

  pm <- x$permits
  pm <- pm[is.na(pm$exclusion) & pm$in_city %in% TRUE, ]
  res5 <- pm[pm$sector %in% "residential" & pm$issue_date >= p$permits_from & pm$issue_date <= p$permits_to, ]
  ren <- per_tract(res5$tract[res5$category == "renovation"], tracts)
  new <- per_tract(res5$tract[res5$category == "new"], tracts)
  add(source = "Building permits", origin = "City DPD Building Permits layer (offline copy)",
      unit = "One issued permit, at its site", kind = "Events (points)",
      time = sprintf("%s to %s", fmt_d(min(pm$issue_date)), fmt_d(attr(x$permits, "through"))),
      volume = sprintf("%s permits inside the city. Median per tract over five years: %s home renovations, %s new homes",
                       fmt_n(nrow(pm)), ren[["median"]], new[["median"]]),
      denominator = "ACS housing units (parcel counts exist only for ZIPs and districts)",
      quality = "Only permitted work appears, and unpermitted work is likely more common in some areas. Values are self-declared. New construction is too sparse per tract.",
      used = "Context for the clusters (rates per 1,000 homes)")
  if (!is.null(x$demolitions)) {
    dm <- x$demolitions
    dm <- dm[is.na(dm$exclusion) & dm$in_city %in% TRUE, ]
    dpt <- per_tract(dm$tract[dm$issue_date >= p$demolitions_from & dm$issue_date <= p$demolitions_to], tracts)
    add(source = "Demolition permits", origin = "Owner's Data Midsouth snapshot (D30)",
        unit = "One demolition permit, at its site", kind = "Events (points)",
        time = sprintf("%s to %s", fmt_d(min(dm$issue_date)), fmt_d(attr(x$demolitions, "through"))),
        volume = sprintf("%s demolitions inside the city; median %s per tract over five years", fmt_n(nrow(dm)), dpt[["median"]]),
        denominator = "ACS housing units",
        quality = "Dated by the permit's latest status, not its issue date (for closed permits, a median of 201 days later). Duplicate rows removed.",
        used = "Context for the clusters")
  }
  if (!is.null(x$establishments)) {
    es <- x$establishments
    ins <- x$inspections
    ins <- ins[is.na(ins$exclusion), ]
    ec <- es[es$in_city %in% TRUE, ]
    tc <- table(ec$tract)
    sc <- ins$score[ins$kind %in% "routine" & !is.na(ins$score)]
    add(source = "Food-safety inspections", origin = "Owner's collector for the state inspection portal (D29)",
        unit = "One inspection of one restaurant or bar, placed by geocoding its address",
        kind = "Events at fixed facilities",
        time = sprintf("%s to %s", fmt_d(attr(x$inspections, "from")), fmt_d(attr(x$inspections, "through"))),
        volume = sprintf("%s inspections of %s restaurants and bars inside the city, in %d tracts; only %d tracts have 10 or more",
                         fmt_n(nrow(ins)), fmt_n(nrow(ec)), length(tc), sum(tc >= 10)),
        denominator = "Establishments (not residents)",
        quality = sprintf("Scores barely vary (median %s, 5th percentile %s). No closure or risk fields, so closed restaurants look overdue. %s could not be geocoded.",
                          stats::median(sc), stats::quantile(sc, 0.05, names = FALSE),
                          pct(mean(is.na(es$longitude)))),
        used = "Not used: too few per tract, and too little variation")
  }
  add(source = "ACS 2020-2024 demographics", origin = "Census ACS 5-year estimates for the in-city part of each tract (D20)",
      unit = "Area estimate with a margin of error", kind = "Area proportions and counts",
      time = "2020-2024 survey period",
      volume = sprintf("%d tracts with residents inside the city", sum(memequity::area_population("tract")$population > 0)),
      denominator = "Population, households, housing units",
      quality = "Survey estimates; small tracts have large margins of error. Area-level only.",
      used = "Context for the clusters; residents and homes as denominators")
  add(source = "MATA transit, MLGW outages", origin = "Project pollers",
      unit = "Vehicle positions; outage points", kind = "Events",
      time = "Since late Sep 2026", volume = "About a week collected",
      denominator = "-", quality = "Pollers cover about half of the hours (H22); MLGW has no pipeline yet.",
      used = "Not used: not enough coverage")
  do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
}

# The checks quoted in the report: missing close dates, stacked coordinates,
# and requests that fall in no tract.
data_checks <- function(x) {
  sr <- x$sr
  base <- sr[is.na(sr$exclusion) & is.na(sr$duplicate_of) & sr$in_city %in% TRUE, ]
  cl <- base[base$state == "closed", ]
  m <- format(cl$open_date, "%Y-%m")
  win <- cl$open_date >= as.Date("2026-06-01") & cl$open_date <= as.Date("2026-08-31")
  stack <- table(paste(base$longitude, base$latitude))
  list(missing_dec2025 = mean(!is.na(cl$close_problem[m == "2025-12"])),
       missing_jan2026 = mean(!is.na(cl$close_problem[m == "2026-01"])),
       missing_window = mean(!is.na(cl$close_problem[win])),
       max_stack = max(stack), no_tract = sum(is.na(base$tract)))
}

pct <- function(x, digits = 0) paste0(formatC(100 * x, format = "f", digits = digits), "%")
