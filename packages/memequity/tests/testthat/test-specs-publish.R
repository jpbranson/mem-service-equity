spec_text <- function(status = "draft", objections = 3, alternatives = 2) {
  obj <- paste(vapply(seq_len(objections), function(i)
    sprintf("  - objection: Objection %d\n    response: Response %d", i, i), ""), collapse = "\n")
  alts <- paste(sprintf("\"alt%d\"", seq_len(alternatives)), collapse = ", ")
  c("---", "id: demo_metric", "pipeline: demo", "title: Demo metric", "version: \"1.0\"",
    paste0("status: ", status), "unit: proportion", "formula: closed on time / closed",
    "windows: [90d, 12m]", "geographies: [zcta, council_district]", "min_n: 30",
    "promise:", "  kind: official", "  text: Fixed in 3 days", "  source_url: https://example.org",
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

test_that("the repository spec template is itself a valid draft spec", {
  tmpl <- file.path(testthat::test_path(), "..", "..", "..", "..", "specs", "_template", "metric.md")
  skip_if_not(file.exists(tmpl))
  expect_length(spec_problems(read_spec(tmpl)), 0)
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
})

test_that("the publish gate passes when all six conditions hold", {
  d <- withr::local_tempdir()
  spec <- read_spec(write_spec(d, status = "frozen"))
  rep <- finalize_report(add_check(validation_report("demo"), "x", "schema", TRUE))
  m <- as_metrics_table(data.frame(geo_type = "zcta", geo_id = "1", metric = "demo_metric",
    value = 0.5, ci_low = 0.4, ci_high = 0.6, n = 100L, suppressed = FALSE,
    window_start = "2026-01-01", window_end = "2026-03-31"), "1.0", "2026-03-31")
  audit <- file.path(d, "audit.csv"); writeLines("x", audit)
  g <- publish_gate(spec, rep, TRUE, m, list(date = "2026-09-01", gap_documented = TRUE),
                    audit, as_of = as.Date("2026-09-23"))
  expect_true(g$publishable)
  stale <- publish_gate(spec, rep, TRUE, m, list(date = "2026-01-01", gap_documented = TRUE),
                        audit, as_of = as.Date("2026-09-23"))
  expect_match(stale$missing, "older than one quarter")
  path <- write_publish_status(list(g, stale), "demo", d)
  expect_equal(jsonlite::read_json(path)$metrics[[2]]$publishable, FALSE)
})
