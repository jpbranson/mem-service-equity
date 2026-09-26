#!/usr/bin/env Rscript
# Permits pipeline: fetch -> validate -> normalize -> attach geography ->
# compute metrics -> write flat files + validation report (plan 6.5).
#
# Usage (from the repository root):
#   Rscript pipelines/permits/run.R [--as-of YYYY-MM-DD] [--raw-cache FILE] [--out DIR]
#
# --raw-cache reuses a previously fetched raw .rds (and writes one if the
# file does not exist), which is useful for development.
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
as_of <- as.Date(arg("as-of", format(Sys.time(), tz = "America/Chicago", "%Y-%m-%d")))
out_dir <- arg("out", file.path("data", "published", "permits"))
raw_cache <- arg("raw-cache")
here <- file.path("pipelines", "permits")
for (f in list.files(file.path(here, "R"), full.names = TRUE)) source(f)

log <- function(...) message(format(Sys.time(), "%H:%M:%S"), "  ", ...)
cfg <- read_permits_config(file.path(here, "config"))

# ---- fetch -----------------------------------------------------------------
if (!is.null(raw_cache) && file.exists(raw_cache)) {
  log("reading cached raw data ", raw_cache)
  raw <- readRDS(raw_cache)
  info <- list(count = attr(raw, "layer_count"), last_edit = attr(raw, "last_edit"))
} else {
  log("fetching DPD permits layer")
  info <- permits_layer_info()
  raw <- fetch_permits()
  attr(raw, "layer_count") <- info$count
  attr(raw, "last_edit") <- info$last_edit
  if (!is.null(raw_cache)) { dir.create(dirname(raw_cache), FALSE, TRUE); saveRDS(raw, raw_cache) }
}
through <- permits_through(info$last_edit, as_of)
log(nrow(raw), " permits; layer last edited ", format(info$last_edit), "; complete through ", format(through))

# ---- validate the source ---------------------------------------------------
rep <- validation_report("permits", as_of, source = PERMITS_LAYER)
rep <- add_check(rep, "fetch complete", "volume", nrow(raw) >= info$count,
                 list(layer_count_before_fetch = info$count, rows_fetched = nrow(raw)))
rep <- check_min_rows(rep, raw, 25000)
rep <- check_schema(rep, raw, cfg$contract)
rep <- check_unique(rep, raw$Record_ID, "unique Record_ID")
# Monthly refresh: the newest permit is normally 25-40 days old.
rep <- check_freshness(rep, raw$Issued_Date, max_lag_days = 62, as_of = as_of)
rep <- check_referential(rep, raw$Sub_Type, cfg$sector_map$sub_type,
                         "every Sub_Type is mapped in config/sector_map.csv")
rep <- check_referential(rep, raw$Construction_Type, cfg$category_map$construction_type,
                         "every Construction_Type is mapped in config/category_map.csv")
# The last complete month should look like the twelve before it.
issue_month <- format(local_date(raw$Issued_Date), "%Y-%m")
months <- format(seq(as.Date(format(through, "%Y-%m-01")), by = "-1 month", length.out = 13), "%Y-%m")
last_n <- sum(issue_month == months[1])
prior <- stats::median(vapply(months[-1], function(m) sum(issue_month == m), 1L))
rep <- add_check(rep, "last complete month's volume is within half to twice the prior 12-month median",
                 "volume", prior > 0 && last_n >= prior / 2 && last_n <= prior * 2,
                 list(month = months[1], permits = last_n, prior_median = prior), severity = "warning")

# ---- external reconciliation (plan 5.5, DECISIONS.md D14, D22) ---------------
recon <- reconcile_permits(raw, cfg, file.path(here, "reconciliation", "official_figures.csv"), as_of)
for (i in seq_len(NROW(recon)))
  rep <- add_check(rep, paste("reproduces official figure", recon$figure_id[i]), "reconciliation",
                   recon$documented[i],
                   as.list(recon[i, c("official_value", "our_value", "gap", "relative_gap",
                                      "within_tolerance")]),
                   severity = "warning")

# ---- normalize and attach geography ----------------------------------------
log("normalizing")
p <- normalize_permits(raw, cfg, through)
rep <- check_geocoding(rep, p$match_quality, accepted = "source_point", max_unlocated_share = 0.03)
log("attaching geography")
pts <- attach_geography_permits(p, geography_dir())
rep <- add_count(rep, "raw_rows", nrow(raw))
for (reason in sort(unique(na.omit(pts$exclusion))))
  rep <- add_count(rep, paste0("excluded_", reason), sum(pts$exclusion == reason, na.rm = TRUE))
rep <- add_count(rep, "unlocated", sum(!pts$located))
rep <- add_count(rep, "outside_city_limits", sum(!pts$in_city & pts$located))
rep <- add_count(rep, "no_declared_value", sum(is.na(pts$value)))
rep <- add_count(rep, "included_in_city", sum(is.na(pts$exclusion) & pts$in_city))
rep$geography <- lapply(c("zcta", "council_district"), function(g)
  assignment_summary(pts[pts$in_city, ], g))
parcels <- sapply(PERMIT_GEOS, function(g) area_parcels(g, geography_dir()), simplify = FALSE)
rep <- add_check(rep, "every council district with permits has a parcel count", "referential",
                 all(na.omit(unique(pts$council_district[pts$in_city])) %in% parcels$council_district$geo_id),
                 list(parcels = parcels_registry(geography_dir())$file[1]))

path <- write_validation_report(finalize_report(rep), out_dir)
log("validation: ", finalize_report(rep)$status, " -> ", path)
stop_if_failed(rep)

# ---- metrics ----------------------------------------------------------------
log("computing metrics")
m <- as_metrics_table(compute_metrics_permits(pts, parcels, through), NA, through)
for (g in unique(m$geo_type)) {
  f <- write_metrics(m[m$geo_type == g, ], "permits", g, out_dir)
  log("wrote ", f, " (", sum(m$geo_type == g), " rows)")
}

# ---- methodology, audit worksheet, publish status -----------------------------
specs_dir <- "specs"
if (!is.null(recon)) write_reconciliation(recon, "permits", out_dir)
render_methodology("permits", specs_dir, out_dir, title = "Investment (building permits)",
                   reconciliation = recon,
                   reconciliation_note = paste(
                     "Each figure below is the Census Bureau's count of new residential buildings",
                     "authorized in the joint Memphis/Shelby permitting jurisdiction (DECISIONS.md D14),",
                     "recomputed from the same permit records on every run (D22). The Census revised",
                     "its own 2024 and 2025 counts between its year-to-date and annual files."))
write_permits_audit(pts, file.path(out_dir, "audit"), as_of)

specs <- read_specs("permits", specs_dir)
audit_file <- sort(list.files(file.path(here, "audits"), pattern = "^audit_.*\\.csv$", full.names = TRUE),
                   decreasing = TRUE)
gates <- lapply(specs, function(s) publish_gate(
  s, finalize_report(rep), tests_passed = identical(Sys.getenv("TESTS_PASSED"), "true"),
  metrics = m[m$metric == s$id, ], reconciliation = spec_reconciliation(s, recon),
  audit_path = if (length(audit_file)) audit_file[1] else NULL, as_of = as_of))
write_publish_status(gates, "permits", out_dir)
log("done")
