#!/usr/bin/env Rscript
# Food-safety pipeline: ingest the inspection data -> validate -> keep the
# food program -> normalize -> geocode -> attach geography -> compute metrics
# -> write flat files + validation report (plan 6.4, DECISIONS.md H11, D32, D13).
#
# Usage (from the repository root):
#   Rscript pipelines/food-safety/run.R [--inbox DIR] [--from YYYY-MM-DD]
#                                       [--through YYYY-MM-DD]
#                                       [--as-of YYYY-MM-DD] [--out DIR]
#                                       [--geocode-cache FILE]
#
# --inbox holds TDH's records-request export (H11, D32; default
# pipelines/food-safety/inbox). --from and --through are the first and last
# days the data are complete for (the agency's cover letter). Without them,
# the earliest and latest inspection dates are used; no window starts before
# --from.
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
  message("No inspections file in ", inbox, ". Put TDH's export there (DECISIONS.md H11), ",
          "or pass --inbox with a directory holding a file whose name matches '",
          cfg$column_map$tables$inspections$file_pattern, "'. Nothing to do.")
  quit(save = "no", status = 0)
}
log("inspections from ", attr(tables$inspections, "file"), ": ", nrow(tables$inspections), " rows")

# ---- validate the data -------------------------------------------------------
files <- Filter(Negate(is.null), tables)
rep <- validation_report("food-safety", as_of, source = paste0(trimws(cfg$column_map$source), ": ",
  paste(vapply(unique(vapply(files, attr, "", "file")), function(f)
    sprintf("%s (md5 %s)", f, unname(tools::md5sum(file.path(inbox, f)))), ""), collapse = ", ")))
if ("program" %in% names(tables$inspections))
  rep <- check_referential(rep, tables$inspections$program, cfg$programs$program,
                           "every program is listed in config/programs.csv")
tables <- food_program_only(tables, cfg)
log("food-program inspections: ", nrow(tables$inspections), " (",
    attr(tables$inspections, "other_program"), " from other programs left out)")
through <- as.Date(arg("through", format(max(tables$inspections$inspection_date, na.rm = TRUE))))
from <- as.Date(arg("from", format(min(tables$inspections$inspection_date, na.rm = TRUE))))
log("data cover ", format(from), " through ", format(through))
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
for (t in Filter(function(t) !is.null(t) && "establishment_type" %in% names(t), tables))
  rep <- check_referential(rep, t$establishment_type, cfg$establishment_types$establishment_type,
                           sprintf("%s: every permit type is listed in config/establishment_types.csv",
                                   attr(t, "file")))
score <- suppressWarnings(as.numeric(ins_raw$score))
rep <- add_check(rep, "scores are between 0 and 100", "range",
                 all(is.na(score) | (score >= 0 & score <= 100)),
                 list(out_of_range = sum(!is.na(score) & (score < 0 | score > 100))))
if ("inspection_id" %in% names(ins_raw))
  rep <- check_unique(rep, ins_raw$inspection_id, "unique inspection_id")
rep <- add_check(rep, "data are less than 60 days old", "freshness",
                 as.integer(as_of - through) <= 60, list(through = format(through)), severity = "warning")
longest <- months_back(through, max(cfg$rules$score_window_months, cfg$rules$active_months))
rep <- add_check(rep, "data cover the longest metric window", "coverage", from <= longest,
                 list(from = format(from), window_start = format(longest)), severity = "warning")

# ---- normalize, geocode and attach geography ------------------------------------
log("normalizing")
ins <- normalize_inspections(tables, cfg, through, from)
est <- normalize_establishments(tables, ins, cfg)
excluded_type <- attr(est, "excluded_type")
log("geocoding ", nrow(est), " establishments (", excluded_type, " of excluded permit types left out)")
est <- geocode_establishments(est, cache_path = arg("geocode-cache",
                                                   file.path("data", "cache", "food-safety", "geocode.csv")))
rep <- check_geocoding(rep, est$match_quality, accepted = c("exact", "non_exact"))
pts <- attach_geography_food(est, geography_dir())
rep <- add_count(rep, "inspections_other_program", attr(tables$inspections, "other_program"))
rep <- add_count(rep, "inspections_exact_duplicates", attr(tables$inspections, "exact_duplicates"))
rep <- add_count(rep, "inspections", nrow(ins))
for (reason in sort(unique(na.omit(ins$exclusion))))
  rep <- add_count(rep, paste0("excluded_", reason), sum(ins$exclusion == reason, na.rm = TRUE))
rep <- add_count(rep, "establishments_excluded_type", excluded_type)
rep <- add_count(rep, "establishments", nrow(est))
rep <- add_count(rep, "establishments_in_city", sum(pts$in_city))
rep$geography <- lapply(c("zcta", "council_district"), function(g) assignment_summary(pts[pts$in_city, ], g))

path <- write_validation_report(finalize_report(rep), out_dir)
log("validation: ", finalize_report(rep)$status, " -> ", path)
stop_if_failed(rep)

# ---- metrics ----------------------------------------------------------------
m <- as_metrics_table(compute_metrics_food(pts, ins, cfg$rules, through, from), NA, through)
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
gate_pipeline("food-safety", rep, m, recon, as_of, out_dir)
log("done")
