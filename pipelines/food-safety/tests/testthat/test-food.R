# Layer 3 tests for the food-safety pipeline (plan 5.3), on a synthetic
# export: the real one has not arrived (DECISIONS.md H11). Golden files come
# once it does.

test_that("dates parse in any configured format, and implausible years are rejected", {
  f <- unlist(cfg$column_map$date_formats)
  d <- parse_dates(c("03/01/2026", "2026-03-01", "03/01/2026 14:05:00", "03/01/26", "", NA, "13/45/2026"), f)
  expect_equal(d[1:4], as.Date(rep("2026-03-01", 4)))
  expect_true(all(is.na(d[5:7])))
})

test_that("the column map renames the export and reports absent fields", {
  ins <- make_inspections(1:2, c("2026-01-05", "2026-02-05"), "Routine", c(90, 85))
  ins$name <- NULL                                     # the export lacks a name column
  inbox <- write_export(ins)
  t <- ingest_export(inbox, cfg)
  expect_equal(attr(t$inspections, "file"), "inspections_export.csv")
  expect_true(all(c("establishment_id", "inspection_date", "score") %in% names(t$inspections)))
  expect_s3_class(t$inspections$inspection_date, "Date")
  expect_true("name" %in% attr(t$inspections, "absent"))
  expect_length(attr(t$inspections, "missing_required"), 0)
  expect_null(t$establishments)
  ins$score <- NULL                                    # a required field
  expect_equal(attr(ingest_export(write_export(ins), cfg)$inspections, "missing_required"), "score")
})

test_that("establishments are keyed on the permit number, else on name and address", {
  k <- establishment_key(c("123", NA, ""), c("A", "Test Grill", "Test Grill"),
                         c("1 X ST", "5 TEST ST.", "5 test st"))
  expect_equal(k[1], "permit:123")
  expect_equal(k[2], k[3])                             # same normalized name and address
  expect_match(k[2], "^name_address:")
})

test_that("inspection kinds are mapped, and unusable inspections are flagged", {
  ins <- make_inspections(1:4, c("2026-01-05", "2026-01-06", "2026-09-10", "2026-01-07"),
                          c("Routine", "Follow-Up", "Routine", "Mystery Visit"), c(90, 88, 91, NA))
  t <- ingest_export(write_export(ins), cfg)
  n <- normalize_inspections(t, cfg, as.Date("2026-08-31"))
  expect_equal(n$kind, c("routine", "follow_up", "routine", NA))
  expect_equal(n$exclusion, c(NA, NA, "after_data_through", "unmapped_inspection_type"))
})

# Thirty establishments at 10-300 m east of downtown (all in ZIP 38103), each
# with a routine inspection a year back (score 90) and a latest routine
# inspection on 2026-03-01 scoring 65 (x6), 75 (x6), 82 (x6) or 95 (x12).
# Numbers 26-30 had their latest routine on 2025-12-15 instead (overdue by
# 2026-08-31 unless allowed 90 days' grace). Numbers 1-6 got a follow-up.
# Number 31 has only a pre-opening inspection, on 2026-07-01.
fixture <- function() {
  ids <- 1:30
  latest <- ifelse(ids >= 26, "2025-12-15", "2026-03-01")
  scores <- c(rep(65, 6), rep(75, 6), rep(82, 6), rep(95, 12))
  rbind(
    make_inspections(ids, "2025-03-01", "Routine", 90),
    make_inspections(ids, latest, "Routine", scores),
    make_inspections(1:6, "2026-03-10", "Follow-Up", 88),
    make_inspections(31, "2026-07-01", "Pre-Opening", NA))
}

test_that("food-safety metrics on a known fixture", {
  ins <- fixture()
  ins$inspection_id <- sprintf("I%05d", seq_len(nrow(ins)))
  r <- food_pipeline(write_export(ins), "2026-08-31")
  expect_true(all(r$est$zcta == "38103"))
  m <- r$m
  med <- get_food(m, "median_latest_score")
  expect_equal(med$value, 82)
  expect_equal(med$n, 30L)
  expect_equal(get_food(m, "pct_below_followup_threshold")$value, 6 / 30)
  expect_equal(get_food(m, "pct_below_followup_threshold", variant = "below_80")$value, 12 / 30)
  expect_equal(get_food(m, "pct_below_followup_threshold", variant = "below_85")$value, 18 / 30)
  # 60 routine inspections and 6 follow-ups in the 24 months.
  rr <- get_food(m, "reinspection_rate")
  expect_equal(c(rr$value, rr$n), c(6 / 66, 66))
  # 31 active establishments; numbers 26-30 are overdue unless given 90 days.
  expect_equal(get_food(m, "pct_overdue_inspection")$value, 5 / 31)
  expect_equal(get_food(m, "pct_overdue_inspection", variant = "grace_30d")$value, 5 / 31)
  expect_equal(get_food(m, "pct_overdue_inspection", variant = "grace_90d")$value, 0)
  # Every row carries the citywide reference, and the table meets the contract.
  expect_equal(unique(m$citywide_median[m$metric == "median_latest_score"]), 82)
  tab <- memequity::as_metrics_table(m, NA, as.Date("2026-08-31"))
  expect_length(memequity::metrics_problems(tab), 0)
})

test_that("unlocated and closed establishments drop out, and order does not matter", {
  ins <- fixture()
  ins$address[ins$establishment_id == "P1"] <- "NOWHERE"          # the stub cannot place it
  est <- data.frame(establishment_id = "P2", name = "Test Grill 2", address = "2 TEST ST",
                    city = "Memphis", zip = "38103", establishment_type = "Restaurant",
                    risk_category = NA, closed_date = "06/01/2026")
  a <- food_pipeline(write_export(ins, est), "2026-08-31")
  expect_equal(get_food(a$m, "median_latest_score")$n, 29L)      # P1 is unlocated
  expect_equal(get_food(a$m, "pct_overdue_inspection")$n, 29L)   # ... and P2 closed
  set.seed(9)
  b <- food_pipeline(write_export(ins[sample(nrow(ins)), ], est), "2026-08-31")
  key <- function(m) m[order(m$metric, m$variant, m$geo_type, m$geo_id),
                       c("metric", "variant", "geo_id", "value", "ci_low", "ci_high", "n")]
  expect_equal(key(a$m), key(b$m), ignore_attr = TRUE)
})

test_that("reconciliation counts inspections by kind and period", {
  ins <- fixture()
  t <- ingest_export(write_export(ins), cfg)
  n <- normalize_inspections(t, cfg, as.Date("2026-08-31"))
  path <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(
    figure_id = c("all_2025", "routine_2025"), measure = "inspection_counts",
    subgroup = c("", "routine"), period_start = "2025-01-01", period_end = "2025-12-31",
    value = c("35", "35"), precision = "1", definition = "d", source_title = "t",
    source_url = "https://example.org", source_page = "", published = "", transcribed = "",
    gap_note = ""), path, row.names = FALSE)
  r <- reconcile_food(n, path, as.Date("2026-09-25"))
  expect_equal(r$our_value, c(35, 35))   # 30 on 2025-03-01 and 5 on 2025-12-15
})

test_that("SPEC_VERSIONS matches the version in each spec", {
  specs <- memequity::read_specs("food-safety", file.path(repo_root, "specs"))
  for (id in names(SPEC_VERSIONS))
    expect_identical(as.character(specs[[id]]$version), SPEC_VERSIONS[[id]], info = id)
})
