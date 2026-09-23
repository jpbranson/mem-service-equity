# Worksheets for the human audits in plan 5.6 (DECISIONS.md H3, H4).
# They are regenerated on every run; a reviewer copies one into
# pipelines/311/audits/, fills in the blank columns and commits it. The
# committed audit is what the publish gate looks for.

write_audit_worksheets <- function(pts, raw, dir, as_of, n = 100L) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  df <- sf::st_drop_geometry(pts)
  pool <- which(is.na(df$exclusion) & df$in_city)
  seed <- as.integer(format(as.Date(as_of), "%Y%m%d"))
  set.seed(seed)
  pick <- pool[sample.int(length(pool), min(n, length(pool)))]
  s <- df[pick, ]
  sheet <- data.frame(
    sr_id = s$sr_id, request_type = s$request_type, status = s$status,
    opened_local = format(s$opened_at, tz = "America/Chicago", "%Y-%m-%d %H:%M"),
    close_date = format(s$close_date), close_problem = s$close_problem,
    business_days_to_close = s$bd_to_close, age_business_days = s$age_bd,
    zcta = s$zcta, council_district = s$council_district, h3_cell = s$h3,
    duplicate_of = s$duplicate_of,
    `1_found_in_source` = "", `2_dates_match` = "", `3_location_matches` = "",
    `4_business_days_correct` = "", `5_geography_correct` = "", auditor = "", notes = "",
    check.names = FALSE)
  utils::write.csv(sheet, file.path(dir, sprintf("audit_sample_%s.csv", as_of)), row.names = FALSE, na = "")

  # Disposition worksheet: every (resolution code, sub-status) combination
  # among closed requests, with counts and sample incident numbers to read.
  closed <- df[df$state == "closed" & is.na(df$exclusion), c("sr_id", "request_type")]
  closed$RESOLUTION_CODE <- raw$RESOLUTION_CODE[match(closed$sr_id, raw$INCIDENT_NUMBER)]
  closed$Request_Sub_Status <- raw$Request_Sub_Status[match(closed$sr_id, raw$INCIDENT_NUMBER)]
  closed$RESOLUTION_CODE[is.na(closed$RESOLUTION_CODE) | closed$RESOLUTION_CODE == ""] <- "(blank)"
  closed$Request_Sub_Status[is.na(closed$Request_Sub_Status) | closed$Request_Sub_Status == ""] <- "(blank)"
  key <- paste(closed$RESOLUTION_CODE, closed$Request_Sub_Status, sep = "\r")
  groups <- split(seq_len(nrow(closed)), key)
  disp <- do.call(rbind, lapply(groups, function(ix) data.frame(
    resolution_code = closed$RESOLUTION_CODE[ix[1]],
    sub_status = closed$Request_Sub_Status[ix[1]],
    closed_requests = length(ix),
    top_request_types = paste(utils::head(names(sort(table(closed$request_type[ix]), decreasing = TRUE)), 3),
                              collapse = "; "),
    sample_incident_numbers = paste(utils::head(closed$sr_id[ix][sample.int(length(ix))], 5), collapse = " "),
    proposed_disposition = "", notes = "")))
  disp <- disp[order(-disp$closed_requests), ]
  utils::write.csv(disp, file.path(dir, sprintf("disposition_worksheet_%s.csv", as_of)), row.names = FALSE)
  invisible(dir)
}
