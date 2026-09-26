#!/usr/bin/env Rscript
# Food-safety pipeline: ingest the records-request export -> validate ->
# normalize -> geocode -> attach geography -> compute metrics -> write flat
# files + validation report (plan 6.4, DECISIONS.md H11, D13).
#
# Usage (from the repository root):
#   Rscript pipelines/food-safety/run.R [--inbox DIR] [--through YYYY-MM-DD]
#                                       [--as-of YYYY-MM-DD] [--out DIR]
#                                       [--geocode-cache FILE]
#
# --through is the date the export is complete through (from the agency's
# cover letter). Without it, the latest inspection date in the export is used.
# Geocodes are cached (default data/cache/food-safety/geocode.csv); only
# addresses missing from the cache go to the Census geocoder.
# Set TESTS_PASSED=true when the metric tests have passed in the same CI run.

suppressPackageStartupMessages({
  library(memequity)
  library(sf)
})

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) {
  i <- match(paste0("--", name), args)
  if (is.na(i)) default else args[i + 1]
}
here <- file.path("pipelines", "food-safety")
as_of <- as.Date(arg("as-of", format(Sys.time(), tz = "America/Chicago", "%Y-%m-%d")))
inbox <- arg("inbox", file.path(here, "inbox"))
out_dir <- arg("out", file.path("data", "published", "food-safety"))
for (f in list.files(file.path(here, "R"), full.names = TRUE)) source(f)
log <- function(...) message(format(Sys.time(), "%H:%M:%S"), "  ", ...)
cfg <- read_food_config(file.path(here, "config"))

# ---- ingest ------------------------------------------------------------------
tables <- ingest_export(inbox, cfg)
if (is.null(tables$inspections)) {
  message("No inspections file in ", inbox, ". The records request (DECISIONS.md H11) ",
          "has not been answered, or the file name does not contain '",
          cfg$column_map$tables$inspections$file_pattern, "'. Nothing to do.")
  quit(save = "no", status = 0)
}
log("inspections from ", attr(tables$inspections, "file"), ": ", nrow(tables$inspections), " rows")
through <- as.Date(arg("through", format(max(tables$inspections$inspection_date, na.rm = TRUE))))
log("data complete through ", format(through))

# ---- validate the export -----------------------------------------------------
rep <- validation_report("food-safety", as_of, source = paste("records-request export:",
  paste(vapply(Filter(Negate(is.null), tables), function(t) attr(t, "file"), ""), collapse = ", ")))
for (t in names(tables)) {
  tb <- tables[[t]]
  rep <- add_check(rep, sprintf("export has a %s file", t), "schema", !is.null(tb),
                   list(file_pattern = cfg$column_map$tables[[t]]$file_pattern),
                   severity = if (t == "inspections") "error" else "warning")
  if (is.null(tb)) next
  rep <- add_check(rep, sprintf("%s: every required field is mapped", t), "schema",
                   !length(attr(tb, "missing_required")),
                   list(missing = as.list(attr(tb, "missing_required")), absent = as.list(attr(tb, "absent"))))
}
ins_raw <- tables$inspections
rep <- check_min_rows(rep, ins_raw, 1000)
rep <- add_check(rep, "inspection dates parse", "schema",
                 mean(is.na(ins_raw$inspection_date)) <= 0.01,
                 list(unparsed = sum(is.na(ins_raw$inspection_date)), rows = nrow(ins_raw)))
rep <- check_referential(rep, ins_raw$inspection_type, cfg$inspection_types$inspection_type,
                         "every inspection type is mapped in config/inspection_types.csv")
score <- suppressWarnings(as.numeric(ins_raw$score))
rep <- add_check(rep, "scores are between 0 and 100", "range",
                 all(is.na(score) | (score >= 0 & score <= 100)),
                 list(out_of_range = sum(!is.na(score) & (score < 0 | score > 100))))
if ("inspection_id" %in% names(ins_raw))
  rep <- check_unique(rep, ins_raw$inspection_id, "unique inspection_id")
rep <- add_check(rep, "export is less than 60 days old", "freshness",
                 as.integer(as_of - through) <= 60, list(through = format(through)), severity = "warning")

# ---- normalize, geocode and attach geography ------------------------------------
log("normalizing")
ins <- normalize_inspections(tables, cfg, through)
est <- normalize_establishments(tables, ins)
log("geocoding ", nrow(est), " establishments")
est <- geocode_establishments(est, cache_path = arg("geocode-cache",
                                                   file.path("data", "cache", "food-safety", "geocode.csv")))
rep <- check_geocoding(rep, est$match_quality, accepted = c("exact", "non_exact"))
pts <- attach_geography_food(est, geography_dir())
rep <- add_count(rep, "inspections", nrow(ins))
for (reason in sort(unique(na.omit(ins$exclusion))))
  rep <- add_count(rep, paste0("excluded_", reason), sum(ins$exclusion == reason, na.rm = TRUE))
rep <- add_count(rep, "establishments", nrow(est))
rep <- add_count(rep, "establishments_in_city", sum(pts$in_city))
rep$geography <- lapply(c("zcta", "council_district"), function(g) assignment_summary(pts[pts$in_city, ], g))

path <- write_validation_report(finalize_report(rep), out_dir)
log("validation: ", finalize_report(rep)$status, " -> ", path)
stop_if_failed(rep)

# ---- metrics ----------------------------------------------------------------
m <- as_metrics_table(compute_metrics_food(pts, ins, cfg$rules, through), NA, through)
for (g in unique(m$geo_type)) {
  f <- write_metrics(m[m$geo_type == g, ], "food-safety", g, out_dir)
  log("wrote ", f, " (", sum(m$geo_type == g), " rows)")
}

# ---- methodology, audit worksheet, publish status -----------------------------
specs_dir <- "specs"
recon <- reconcile_food(ins, file.path(here, "reconciliation", "official_figures.csv"), as_of)
if (!is.null(recon)) write_reconciliation(recon, "food-safety", out_dir)
render_methodology("food-safety", specs_dir, out_dir, title = "Food safety", reconciliation = recon,
                   reconciliation_note = if (is.null(recon)) paste(
                     "No official inspection count for Shelby County has been identified yet, so these",
                     "metrics cannot be reconciled. Plan 5.5 names WREG's weekly roundups, which are not",
                     "an official source."))
write_food_audit(pts, ins, cfg$rules, through, file.path(out_dir, "audit"), as_of)
specs <- read_specs("food-safety", specs_dir)
audit_file <- sort(list.files(file.path(here, "audits"), pattern = "^audit_.*\\.csv$", full.names = TRUE),
                   decreasing = TRUE)
gates <- lapply(specs, function(s) publish_gate(
  s, finalize_report(rep), tests_passed = identical(Sys.getenv("TESTS_PASSED"), "true"),
  metrics = m[m$metric == s$id, ], reconciliation = spec_reconciliation(s, recon),
  audit_path = if (length(audit_file)) audit_file[1] else NULL, as_of = as_of))
write_publish_status(gates, "food-safety", out_dir)
log("done")
