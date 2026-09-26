spec_text <- function(status = "draft", objections = 3, alternatives = 2) {
  obj <- paste(vapply(seq_len(objections), function(i)
    sprintf("  - objection: Objection %d\n    response: Response %d", i, i), ""), collapse = "\n")
  alts <- paste(sprintf("\"alt%d\"", seq_len(alternatives)), collapse = ", ")
  c("---", "id: demo_metric", "pipeline: demo", "title: Demo metric", "version: \"1.0\"",
    paste0("status: ", status), "unit: proportion", "formula: closed on time / closed",
    "windows: [90d, 12m]", "geographies: [zcta, council_district]", "min_n: 30",
    "promise:", "  kind: official", "  text: Fixed in 3 days", "  source_url: https://example.org",
    "reconciliation:", "  measures: [on_time_rate]", "  text: The agency's own on-time rate",
    "thresholds:", "  - name: on-time window", "    primary: \"3 business days\"",
    paste0("    alternatives: [", alts, "]"), "    arbitrary: true",
    "inclusions: [closed requests]", "exclusions: [duplicates]", "confounders: [who calls]",
    "objections:", obj, "---", "", "## Notes", "", "Prose body.")
}

write_spec <- function(dir, ...) {
  dir.create(file.path(dir, "demo"), showWarnings = FALSE)
  writeLines(spec_text(...), file.path(dir, "demo", "demo_metric.md"))
  file.path(dir, "demo", "demo_metric.md")
}

write_audit <- function(d, n = 100, answer = "yes", auditor = "A. Reviewer", notes = "",
                        name = "audit.csv") {
  path <- file.path(d, name)
  a <- data.frame(sr_id = seq_len(n), `1_found_in_source` = answer, `2_dates_match` = answer,
                  auditor = auditor, notes = notes, check.names = FALSE)
  utils::write.csv(a, path, row.names = FALSE)
  path
}

test_that("an audit sheet counts only when complete", {
  d <- withr::local_tempdir()
  expect_length(audit_problems(write_audit(d)), 0)
  expect_match(audit_problems(write_audit(d, n = 99)), "99 records traced, 100 needed", all = FALSE)
  expect_match(audit_problems(write_audit(d, answer = "")), "200 check answers", all = FALSE)
  expect_match(audit_problems(write_audit(d, auditor = "")), "auditor", all = FALSE)
  expect_match(audit_problems(write_audit(d, answer = "No")), "100 rows answer no without a note",
               all = FALSE)
  expect_length(audit_problems(write_audit(d, answer = "No", notes = "fixed in 1a2b3c")), 0)
  expect_length(audit_problems(write_audit(d, answer = "N/A")), 0)
})

test_that("specs parse and draft specs validate", {
  d <- withr::local_tempdir()
  s <- read_spec(write_spec(d))
  expect_equal(s$id, "demo_metric")
  expect_match(s$body, "Prose body")
  expect_length(spec_problems(s), 0)
})

test_that("frozen specs need answered objections and threshold alternatives", {
  d <- withr::local_tempdir()
  expect_length(spec_problems(read_spec(write_spec(d, status = "frozen"))), 0)
  expect_match(spec_problems(read_spec(write_spec(d, "frozen", objections = 2))), "objections")
  expect_match(spec_problems(read_spec(write_spec(d, "frozen", alternatives = 1))), "alternatives")
})

test_that("specs must declare a reconciliation, and frozen ones must fill it in", {
  d <- withr::local_tempdir()
  path <- write_spec(d, status = "frozen")
  txt <- readLines(path)
  writeLines(txt[!grepl("^reconciliation:|^  measures:|^  text: The agency", txt)], path)
  expect_match(spec_problems(read_spec(path)), "missing fields: reconciliation", all = FALSE)
  writeLines(sub("measures: \\[on_time_rate\\]", "measures: []", spec_text("frozen")), path)
  expect_match(spec_problems(read_spec(path)), "reconciliation.measures", all = FALSE)
})

official_csv <- function(d, gap_note = "") {
  path <- file.path(d, "official_figures.csv")
  utils::write.csv(data.frame(
    figure_id = c("fy25_total", "fy25_potholes"), measure = c("requests_created", "requests_created"),
    subgroup = c("", "Potholes"), period_start = "2024-07-01", period_end = "2025-06-30",
    value = c("250000", "18000"), precision = c("1000", "1"), definition = "requests created",
    source_title = "Budget book", source_url = "https://memphistn.gov/x.pdf", source_page = c("12", ""),
    published = "2025-07-01", transcribed = "2026-09-25", gap_note = c("", gap_note)),
    path, row.names = FALSE)
  path
}

test_that("official figures are read and checked", {
  d <- withr::local_tempdir()
  f <- read_official_figures(official_csv(d))
  expect_equal(f$value, c(250000, 18000))
  expect_equal(f$precision, c(1000, 1))
  expect_s3_class(f$period_start, "Date")
  bad <- f; bad$source_url[1] <- NA
  utils::write.csv(bad, file.path(d, "bad.csv"), row.names = FALSE)
  expect_error(read_official_figures(file.path(d, "bad.csv")), "incomplete")
  utils::write.csv(f[, -1], file.path(d, "short.csv"), row.names = FALSE)
  expect_error(read_official_figures(file.path(d, "short.csv")), "figure_id")
})

test_that("reconciliation tolerance is 2% or half the rounding unit, and gaps need a note", {
  d <- withr::local_tempdir()
  f <- read_official_figures(official_csv(d))
  # 250,000 +/- max(5,000, 500); 18,000 +/- max(360, 0.5)
  r <- reconcile_figures(f, c(254999, 18361), as_of = as.Date("2026-09-25"))
  expect_equal(r$within_tolerance, c(TRUE, FALSE))
  expect_equal(r$documented, c(TRUE, FALSE))
  expect_equal(r$gap, c(4999, 361))
  f2 <- read_official_figures(official_csv(d, gap_note = "Re-typed requests; see note"))
  r2 <- reconcile_figures(f2, c(250000, 18361), as_of = as.Date("2026-09-25"))
  expect_equal(r2$documented, c(TRUE, TRUE))
  missing_ours <- reconcile_figures(f, c(NA, 18000))
  expect_false(missing_ours$within_tolerance[1])
  expect_false(missing_ours$documented[1])
})

test_that("each spec gets the reconciliation of the measures it names", {
  d <- withr::local_tempdir()
  spec <- read_spec(write_spec(d))
  f <- read_official_figures(official_csv(d))
  r <- reconcile_figures(f, c(250000, 18000), as_of = as.Date("2026-09-25"))
  expect_null(spec_reconciliation(spec, r))          # names on_time_rate; none exists
  spec$reconciliation$measures <- list("requests_created")
  rec <- spec_reconciliation(spec, r)
  expect_true(rec$gap_documented)
  expect_equal(rec$date, as.Date("2026-09-25"))
  expect_equal(rec$figures, c("fy25_total", "fy25_potholes"))
  r$documented[2] <- FALSE
  expect_false(spec_reconciliation(spec, r)$gap_documented)
  expect_null(spec_reconciliation(spec, NULL))
})

test_that("methodology lists each reconciled figure", {
  d <- withr::local_tempdir()
  write_spec(d)
  f <- read_official_figures(official_csv(d))
  r <- reconcile_figures(f, c(251234, 18500), as_of = as.Date("2026-09-25"))
  out <- render_methodology("demo", d, file.path(d, "out"), reconciliation = r,
                            reconciliation_note = "No official on-time figure exists.")
  txt <- paste(readLines(out), collapse = "\n")
  expect_match(txt, "No official on-time figure exists.")
  expect_match(txt, "official 250,000")
  expect_match(txt, "within tolerance")
  expect_match(txt, "outside tolerance and not yet explained")
  expect_match(txt, "Reconciled against:.*on_time_rate")
})

test_that("the repository spec template is itself a valid draft spec", {
  tmpl <- file.path(testthat::test_path(), "..", "..", "..", "..", "specs", "_template", "metric.md")
  skip_if_not(file.exists(tmpl))
  expect_length(spec_problems(read_spec(tmpl)), 0)
})

test_that("every repository spec parses and has no problems", {
  root <- file.path(testthat::test_path(), "..", "..", "..", "..", "specs")
  skip_if_not(dir.exists(root))
  pipelines <- setdiff(list.dirs(root, full.names = FALSE, recursive = FALSE), "_template")
  expect_gt(length(pipelines), 0)
  for (p in pipelines) for (s in read_specs(p, root)) {
    expect_identical(spec_problems(s), character(), info = s$path)
    expect_identical(as.character(s$pipeline), p, info = s$path)
    expect_identical(s$id, tools::file_path_sans_ext(basename(s$path)), info = s$path)
  }
})

test_that("methodology is generated from specs", {
  d <- withr::local_tempdir()
  write_spec(d)
  out <- render_methodology("demo", d, file.path(d, "out"),
                            reconciliation = list(date = "2026-09-01", reference = "City", reference_value = "82%",
                                                  our_value = "81%", gap = "1 pt", note = "ok"))
  txt <- paste(readLines(out), collapse = "\n")
  expect_match(txt, "Demo metric")
  expect_match(txt, "Objection 1")
  expect_match(txt, "82%")
  expect_match(txt, "No pre-launch audit")
})

test_that("the publish gate lists everything that is missing", {
  d <- withr::local_tempdir()
  spec <- read_spec(write_spec(d))
  rep <- finalize_report(add_check(validation_report("demo"), "x", "schema", FALSE))
  m <- as_metrics_table(data.frame(geo_type = "zcta", geo_id = "1", metric = "demo_metric",
    value = NA, ci_low = NA, ci_high = NA, n = 3L, suppressed = TRUE,
    window_start = "2026-01-01", window_end = "2026-03-31"), "1.0", "2026-03-31")
  g <- publish_gate(spec, rep, FALSE, m)
  expect_false(g$publishable)
  expect_length(g$missing, 6)
  spec$blocked <- "No source of demolition permits (H21)."
  b <- publish_gate(spec, rep, FALSE, m)
  expect_length(b$missing, 7)
  expect_equal(b$missing[1], "blocked: No source of demolition permits (H21).")
})

test_that("the publish gate passes when all six conditions hold", {
  d <- withr::local_tempdir()
  spec <- read_spec(write_spec(d, status = "frozen"))
  rep <- finalize_report(add_check(validation_report("demo"), "x", "schema", TRUE))
  m <- as_metrics_table(data.frame(geo_type = "zcta", geo_id = "1", metric = "demo_metric",
    value = 0.5, ci_low = 0.4, ci_high = 0.6, n = 100L, suppressed = FALSE,
    window_start = "2026-01-01", window_end = "2026-03-31"), "1.0", "2026-03-31")
  audit <- write_audit(d)
  g <- publish_gate(spec, rep, TRUE, m, list(date = "2026-09-01", gap_documented = TRUE),
                    audit, as_of = as.Date("2026-09-23"))
  expect_true(g$publishable)
  blank <- write_audit(d, answer = "", auditor = "", name = "blank.csv")
  g_blank <- publish_gate(spec, rep, TRUE, m, list(date = "2026-09-01", gap_documented = TRUE),
                          blank, as_of = as.Date("2026-09-23"))
  expect_false(g_blank$publishable)
  expect_match(g_blank$missing, "audit is incomplete")
  stale <- publish_gate(spec, rep, TRUE, m, list(date = "2026-01-01", gap_documented = TRUE),
                        audit, as_of = as.Date("2026-09-23"))
  expect_match(stale$missing, "older than one quarter")
  path <- write_publish_status(list(g, stale), "demo", d)
  expect_equal(jsonlite::read_json(path)$metrics[[2]]$publishable, FALSE)
})
