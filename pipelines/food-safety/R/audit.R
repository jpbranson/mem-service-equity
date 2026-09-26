# Worksheet for the pre-launch manual audit (plan 5.6; H3 for this panel):
# 100 random establishments with the latest routine inspection the metrics
# use for them. A reviewer traces each to the export and the state portal
# (by hand, in a browser), fills in the check columns and commits the sheet
# to pipelines/food-safety/audits/; the gate counts it only when complete (D23).

write_food_audit <- function(est, ins, rules, through, dir, as_of, n = 100L) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  start <- months_back(through, rules$score_window_months)
  lr <- latest_routine(usable(ins), start, through)
  e <- located_in_city(est, rules)
  d <- merge(e, lr, by = "establishment_key")
  set.seed(as.integer(format(as.Date(as_of), "%Y%m%d")))
  s <- d[sample.int(nrow(d), min(n, nrow(d))), ]
  sheet <- data.frame(
    establishment_key = s$establishment_key, name = s$name, address = s$address,
    latest_routine_date = format(s$inspection_date), latest_routine_score = s$score,
    zcta = s$zcta, council_district = s$council_district, longitude = round(s$longitude, 6),
    latitude = round(s$latitude, 6),
    `1_found_in_export` = "", `2_latest_routine_correct` = "", `3_score_matches_state_portal` = "",
    `4_location_matches` = "", `5_geography_correct` = "", auditor = "", notes = "",
    check.names = FALSE)
  path <- file.path(dir, sprintf("audit_sample_%s.csv", as_of))
  utils::write.csv(sheet, path, row.names = FALSE, na = "")
  invisible(path)
}
