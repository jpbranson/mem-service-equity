# Metric computation for the food-safety pipeline. Specs:
# specs/food-safety/*.md; rules and their sources: config/rules.yml.
#
# The unit is the establishment (a place a resident might eat), except for
# reinspection_rate, whose unit is the inspection. Only establishments with an
# accepted geocode inside the city are counted. Windows end on the day the
# export is complete through.

SPEC_VERSIONS <- c(median_latest_score = "0.2", pct_below_followup_threshold = "0.2",
                   pct_overdue_inspection = "0.2", reinspection_rate = "0.2")

months_back <- function(through, months)
  seq(as.Date(through) + 1L, by = paste0("-", months, " months"), length.out = 2L)[2]

# Adds calendar months; a day that does not exist rolls into the next month.
add_months <- function(d, months) {
  lt <- as.POSIXlt(d)
  lt$mon <- lt$mon + months
  as.Date(lt)
}

located_in_city <- function(est, rules) {
  e <- if (inherits(est, "sf")) sf::st_drop_geometry(est) else est
  keep <- e$in_city %in% TRUE
  types <- unlist(rules$excluded_establishment_types)
  if (length(types)) keep <- keep & !e$establishment_type %in% types
  e[keep, ]
}

usable <- function(ins) ins[is.na(ins$exclusion), ]

# Apply fun(rows) -> one-row data.frame to each area of each geography.
by_area <- function(d, fun) {
  out <- list()
  for (g in FOOD_GEOS) {
    ok <- !is.na(d[[g]])
    if (!any(ok)) next
    groups <- split(which(ok), d[[g]][ok])
    rows <- do.call(rbind, lapply(names(groups), function(id) {
      r <- fun(d[groups[[id]], , drop = FALSE])
      r$geo_type <- g
      r$geo_id <- id
      r
    }))
    out[[g]] <- rows
  }
  do.call(rbind, out)
}

#' Each establishment's latest routine inspection with a score in the window.
latest_routine <- function(ins, start, through) {
  r <- ins[ins$kind %in% "routine" & !is.na(ins$score) & ins$inspection_date >= start &
             ins$inspection_date <= through, ]
  r <- r[order(r$establishment_key, r$inspection_date, r$score, decreasing = TRUE), ]
  r[!duplicated(r$establishment_key), c("establishment_key", "inspection_date", "score")]
}

compute_scores <- function(est, ins, rules, through) {
  start <- months_back(through, rules$score_window_months)
  lr <- latest_routine(usable(ins), start, through)
  d <- merge(lr, located_in_city(est, rules), by = "establishment_key")
  if (!nrow(d)) return(NULL)
  med <- by_area(d, function(s) memequity::metric_median(s$score, min_n = 20L))
  med$metric <- "median_latest_score"; med$variant <- "primary"
  th <- rules$follow_up_threshold
  variants <- c(stats::setNames(th$primary, "primary"),
                stats::setNames(unlist(th$alternatives), paste0("below_", unlist(th$alternatives))))
  below <- do.call(rbind, lapply(names(variants), function(v) {
    r <- by_area(d, function(s) memequity::proportion_counts(sum(s$score < variants[[v]]), nrow(s)))
    r$variant <- v
    r
  }))
  below$metric <- "pct_below_followup_threshold"
  res <- rbind(med, below)
  res$window_start <- start; res$window_end <- through
  res
}

#' Overdue: an active establishment whose latest routine or pre-opening
#' inspection (or, with neither, its first inspection) is more than the
#' required interval, plus any grace, before the data-through date.
compute_overdue <- function(est, ins, rules, through) {
  start <- months_back(through, rules$active_months)
  u <- usable(ins)
  u <- u[u$inspection_date <= through, ]
  seen <- u[u$inspection_date >= start, ]
  e <- located_in_city(est, rules)
  e <- e[e$establishment_key %in% seen$establishment_key &
           (is.na(e$closed_date) | e$closed_date > through), ]
  if (!nrow(e)) return(NULL)
  clock <- u[u$kind %in% c("routine", "pre_opening"), ]
  last_clock <- tapply(clock$inspection_date, clock$establishment_key, max)
  first_any <- tapply(u$inspection_date, u$establishment_key, min)
  ref <- as.Date(ifelse(e$establishment_key %in% names(last_clock),
                        last_clock[e$establishment_key], first_any[e$establishment_key]),
                 origin = "1970-01-01")
  due <- add_months(ref, rules$required_interval$months)
  graces <- c(primary = 0, stats::setNames(unlist(rules$required_interval$grace_days_alternatives),
                                           paste0("grace_", unlist(rules$required_interval$grace_days_alternatives), "d")))
  res <- do.call(rbind, lapply(names(graces), function(v) {
    e$overdue <- through > due + graces[[v]]
    r <- by_area(e, function(s) memequity::proportion_counts(sum(s$overdue), nrow(s)))
    r$variant <- v
    r
  }))
  res$metric <- "pct_overdue_inspection"
  res$window_start <- start; res$window_end <- through
  res
}

compute_reinspection <- function(est, ins, rules, through) {
  start <- months_back(through, rules$score_window_months)
  u <- usable(ins)
  u <- u[u$kind %in% c("routine", "follow_up") & u$inspection_date >= start & u$inspection_date <= through, ]
  d <- merge(u, located_in_city(est, rules), by = "establishment_key")
  if (!nrow(d)) return(NULL)
  res <- by_area(d, function(s) memequity::proportion_counts(sum(s$kind == "follow_up"), nrow(s)))
  res$metric <- "reinspection_rate"; res$variant <- "primary"
  res$window_start <- start; res$window_end <- through
  res
}

add_citywide_reference <- function(m) {
  city <- m[m$geo_type == "citywide", ]
  key <- function(d) paste(d$metric, d$variant, format(as.Date(d$window_start)), sep = "\r")
  m$citywide_median <- city$value[match(key(m), key(city))]
  m
}

compute_metrics_food <- function(est, ins, rules, through) {
  m <- rbind(compute_scores(est, ins, rules, through), compute_overdue(est, ins, rules, through),
             compute_reinspection(est, ins, rules, through))
  m$subgroup <- "all"
  m$metric_version <- SPEC_VERSIONS[m$metric]
  add_citywide_reference(m)
}
