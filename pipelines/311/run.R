#!/usr/bin/env Rscript
# 311 pipeline: fetch -> validate -> normalize -> attach geography ->
# compute metrics -> write flat files + validation report (plan section 6).
#
# Usage (from the repository root):
#   Rscript pipelines/311/run.R [--as-of YYYY-MM-DD] [--raw-cache FILE] [--out DIR]
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
out_dir <- arg("out", file.path("data", "published", "311"))
raw_cache <- arg("raw-cache")
here <- file.path("pipelines", "311")
for (f in list.files(file.path(here, "R"), full.names = TRUE)) source(f)

log <- function(...) message(format(Sys.time(), "%H:%M:%S"), "  ", ...)
through <- as_of - 1
cfg <- read_311_config(file.path(here, "config"))

# ---- fetch -----------------------------------------------------------------
if (!is.null(raw_cache) && file.exists(raw_cache)) {
  log("reading cached raw data ", raw_cache)
  raw <- readRDS(raw_cache)
  expected <- attr(raw, "layer_count")
} else {
  log("fetching 311 layer")
  expected <- count_311()
  raw <- fetch_311()
  attr(raw, "layer_count") <- expected
  if (!is.null(raw_cache)) { dir.create(dirname(raw_cache), FALSE, TRUE); saveRDS(raw, raw_cache) }
}
log(nrow(raw), " rows")

# ---- validate the source ---------------------------------------------------
rep <- validation_report("311", as_of, source = SR_LAYER)
if (!is.null(expected))
  rep <- add_check(rep, "fetch complete", "volume", nrow(raw) >= expected,
                   list(layer_count_before_fetch = expected, rows_fetched = nrow(raw)))
rep <- check_min_rows(rep, raw, 300000)
rep <- check_schema(rep, raw, cfg$contract)
rep <- check_unique(rep, raw$INCIDENT_NUMBER, "unique INCIDENT_NUMBER")
rep <- check_freshness(rep, raw$created_date, max_lag_days = 2, as_of = as_of)
rep <- check_volume(rep, raw$created_date, as_of = as_of)
types_seen <- raw$REQUEST_TYPE[!is.na(raw$REQUEST_TYPE) & raw$REQUEST_TYPE != ""]
rep <- check_referential(rep, types_seen, cfg$request_types$request_type,
                         "every request type is mapped in config/request_types.csv")
rep <- check_referential(rep, ifelse(is.na(raw$REQUEST_STATUS), "", raw$REQUEST_STATUS),
                         cfg$status_map$status, "every status is mapped in config/status_map.csv")

# ---- normalize and attach geography ----------------------------------------
log("normalizing")
sr <- normalize_311(raw, cfg, as_of)
rep <- check_geocoding(rep, sr$match_quality, accepted = "source_point", max_unlocated_share = 0.02)
log("attaching geography and deduplicating")
pts <- attach_geography_311(sr, geography_dir())
rep <- add_count(rep, "raw_rows", nrow(raw))
for (reason in sort(unique(na.omit(pts$exclusion))))
  rep <- add_count(rep, paste0("excluded_", reason), sum(pts$exclusion == reason, na.rm = TRUE))
for (p in sort(unique(na.omit(pts$close_problem))))
  rep <- add_count(rep, paste0("close_problem_", p), sum(pts$close_problem == p, na.rm = TRUE))
rep <- add_count(rep, "outside_city_limits", sum(!pts$in_city & pts$located))
rep <- add_count(rep, "near_duplicates", sum(!is.na(pts$duplicate_of)))
rep <- add_count(rep, "included_primary_in_city",
                 sum(is.na(pts$exclusion) & is.na(pts$duplicate_of) & pts$in_city))
rep$geography <- lapply(c("zcta", "council_district", "super_district"), function(g)
  assignment_summary(pts[pts$in_city, ], g))
# Cross-check: our council district vs the city's own field (a sanity check
# on both the boundary file and the point locations).
agree <- mean(as.character(pts$source_council_district) == pts$council_district, na.rm = TRUE)
rep <- add_check(rep, "council district agrees with source cd_name", "referential", agree >= 0.95,
                 list(agreement = agree), severity = "warning")

# Every area a request can be counted in needs an ACS population (D20).
pop_ids <- area_population("council_district", geography_dir())$geo_id
rep <- add_check(rep, "every council district has an ACS population", "referential",
                 all(na.omit(unique(pts$council_district[pts$in_city])) %in% pop_ids),
                 list(demographics = demographics_registry(geography_dir())$file[1]))

path <- write_validation_report(finalize_report(rep), out_dir)
log("validation: ", finalize_report(rep)$status, " -> ", path)
stop_if_failed(rep)

# ---- metrics ----------------------------------------------------------------
log("computing district metrics")
res <- compute_metrics_311(pts, cfg$request_types, through)
headline <- cfg$request_types$request_type[cfg$request_types$headline %in% TRUE]
log("computing hex metrics")
hex <- compute_hex_metrics(pts, res$rereport, cfg$request_types, headline, through)
hex$metric_version <- SPEC_VERSIONS[hex$metric]
city <- res$metrics[res$metrics$geo_type == "citywide", ]
key <- function(d) paste(d$metric, d$variant, d$subgroup, format(as.Date(d$window_start)), sep = "\r")
hex$citywide_median <- city$value[match(key(hex), key(city))]

log("computing requests per 1,000 residents")
populations <- sapply(RATE_GEOS, function(g) area_population(g, geography_dir()), simplify = FALSE)
rates <- compute_requests_per_1000(base_records(pts), populations, through)

all_m <- rbind(res$metrics[, names(hex)], hex, rates[, names(hex)])
current_through <- format(through)
m <- as_metrics_table(all_m, NA, current_through)
for (g in unique(m$geo_type)) {
  f <- write_metrics(m[m$geo_type == g, ], "311", g, out_dir)
  log("wrote ", f, " (", sum(m$geo_type == g), " rows)")
}

# ---- points for display ----------------------------------------------------
recent <- pts[is.na(pts$exclusion) & pts$in_city & pts$request_type %in% headline &
                pts$open_date > through - 365, ]
recent$open_date <- format(recent$open_date)
recent$close_date <- format(recent$close_date)
recent$duplicate <- !is.na(recent$duplicate_of)
write_points(recent, "311", out_dir,
             c("sr_id", "request_type", "open_date", "close_date", "state", "bd_to_close", "duplicate"))

# ---- methodology, audit worksheets, publish status --------------------------
specs_dir <- "specs"
render_methodology("311", specs_dir, out_dir, title = "City services (311)",
                   reconciliation = list(
                     date = format(as_of), reference = "No official citywide on-time figure found (DECISIONS.md H14)",
                     reference_value = "n/a", our_value = "n/a", gap = "n/a",
                     note = "The figures sometimes quoted (82% on-time) come from a non-city domain and are not used."))
write_audit_worksheets(pts, raw, file.path(out_dir, "audit"), as_of)

specs <- read_specs("311", specs_dir)
audit_file <- list.files(file.path(here, "audits"), pattern = "^audit_.*\\.csv$", full.names = TRUE)
gates <- lapply(specs, function(s) publish_gate(
  s, finalize_report(rep), tests_passed = identical(Sys.getenv("TESTS_PASSED"), "true"),
  metrics = m[m$metric == s$id, ], reconciliation = NULL,
  audit_path = if (length(audit_file)) audit_file[1] else NULL, as_of = as_of))
write_publish_status(gates, "311", out_dir)
log("done")
