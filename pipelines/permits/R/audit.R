# Worksheet for the pre-launch manual audit (plan 5.6, DECISIONS.md H3 for
# the permits panel). Regenerated on every run; a reviewer copies one into
# pipelines/permits/audits/, fills in the check columns and commits it. The
# publish gate counts it only when complete (D23).

write_permits_audit <- function(pts, dir, as_of, n = 100L) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  df <- sf::st_drop_geometry(pts)
  pool <- which(is.na(df$exclusion) & df$in_city)
  set.seed(as.integer(format(as.Date(as_of), "%Y%m%d")))
  s <- df[pool[sample.int(length(pool), min(n, length(pool)))], ]
  sheet <- data.frame(
    permit_id = s$permit_id, issue_date = format(s$issue_date), sector = s$sector, work = s$work,
    category = s$category, declared_value = s$value, zcta = s$zcta,
    council_district = s$council_district, longitude = round(s$longitude, 6),
    latitude = round(s$latitude, 6),
    `1_found_in_source` = "", `2_issue_date_matches` = "", `3_category_correct` = "",
    `4_location_matches` = "", `5_geography_correct` = "", auditor = "", notes = "",
    check.names = FALSE)
  path <- file.path(dir, sprintf("audit_sample_%s.csv", as_of))
  utils::write.csv(sheet, path, row.names = FALSE, na = "")
  invisible(path)
}
