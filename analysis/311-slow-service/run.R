#!/usr/bin/env Rscript
# Where do 311 requests take longer to close than the same request types do
# citywide, and are those places clustered?
#
# Usage (from the repository root):
#   Rscript analysis/311-slow-service/run.R [--rebuild-prep]
#
# Reads the offline caches listed in PARAMS, writes everything to
# analysis/311-slow-service/output/. See README.md.

suppressPackageStartupMessages({
  library(memequity)
  library(sf)
})
here <- file.path("analysis", "311-slow-service")
for (f in list.files(file.path(here, "R"), full.names = TRUE)) source(f)
say <- function(...) message(format(Sys.time(), "%H:%M:%S"), "  ", ...)

# Every parameter, fixed before any result was looked at. The sensitivity
# specifications are listed here too; none was added after seeing results.
PARAMS <- list(
  as_of = as.Date("2026-09-25"),                  # caches fetched this day; data through 2026-09-24
  raw_311 = "data/cache/311/raw_2026-09-25.rds",
  raw_permits = "data/cache/permits/raw_2026-09-25.rds",
  demolitions_file = "../mem-demo-permits/shelby_permits.csv",
  inspections_dir = "../tn-health-inspections/data",
  geocode_cache = "data/cache/food-safety/geocode.csv",
  prep_cache = "data/cache/analysis/311-slow-service/prep_2026-09-25.rds",
  # Primary window: the most recent three months whose closed requests
  # nearly all carry a close date (see README, "Data checks").
  window = as.Date(c("2026-06-01", "2026-08-31")),
  # Sensitivity window: the same season one year earlier (June-July 2025;
  # August 2025 is left out because 12% of its closed requests have no date).
  window_2025 = as.Date(c("2025-06-01", "2025-07-31")),
  min_type_n = 20L,         # a type needs 20 requests for a citywide median (spec min_n)
  min_tract_n = 30L,        # a tract needs 30 eligible requests (project MIN_N_PROPORTION)
  contiguity_tol_m = 10,    # boundaries within 10 m count as touching
  knn_k = 6L,               # sensitivity: six nearest tracts
  nsim_global = 9999L,
  nsim_local = 99999L,
  alpha = 0.05,             # Benjamini-Hochberg false discovery rate for local results
  seed = 20260923L,         # memequity DEFAULT_SEED
  context_measures = c("pct_black_nh", "pct_poverty", "pct_renter", "pct_vacant", "pct_no_vehicle"),
  permits_from = as.Date("2021-09-01"), permits_to = as.Date("2026-08-31"),
  demolitions_from = as.Date("2021-08-01"), demolitions_to = as.Date("2026-07-31"),
  top_types = 10L
)

args <- commandArgs(trailingOnly = TRUE)
out_dir <- file.path(here, "output")
dir.create(file.path(out_dir, "figures"), FALSE, TRUE)
dir.create(file.path(out_dir, "results"), FALSE, TRUE)

say("preparing data")
x <- prep_data(PARAMS, rebuild = "--rebuild-prep" %in% args)
demo_ids <- unique(load_demographic_components("tract")$geo_id)
tg <- city_tracts(demo_ids)
say(nrow(tg), " tracts overlapping the city")
if ("--report-only" %in% args) {
  # Rebuild the page and figures from saved results, without the statistics.
  res <- readRDS(file.path(out_dir, "results", "results.rds"))
  res$inventory <- data_inventory(x, PARAMS)   # cheap; keeps the text current
  res$data_checks <- data_checks(x)
  build_report(res, tg, x, out_dir)
  say("done: ", file.path(out_dir, "report.html"))
  quit(save = "no")
}

say("primary: ", format(PARAMS$window[1]), " to ", format(PARAMS$window[2]), ", contiguity")
prim <- run_spec(x, tg, PARAMS, PARAMS$window[1], PARAMS$window[2], "contiguity")
say("sensitivity: six nearest neighbors")
knn <- run_spec(x, tg, PARAMS, PARAMS$window[1], PARAMS$window[2], "knn")
say("sensitivity: June-July 2025")
y25 <- run_spec(x, tg, PARAMS, PARAMS$window_2025[1], PARAMS$window_2025[2], "contiguity")
# Interpretation check, added after the per-service breakdown showed solid
# waste dominates: is there any clustering left without it?
say("check: without solid-waste request types")
noswm <- run_spec(x, tg, PARAMS, PARAMS$window[1], PARAMS$window[2], "contiguity",
                  exclude_categories = "SWM")

groups <- cluster_groups(prim)
top <- names(sort(table(prim$eligible$request_type), decreasing = TRUE))[seq_len(PARAMS$top_types)]
res <- list(
  params = PARAMS, prim = prim, knn = knn, y25 = y25, noswm = noswm, groups = groups, top_types = top,
  group_ratios = group_ratios(prim, groups),
  type_groups = rbind(type_group_table(prim$requests, prim$eligible, groups, top),
                      type_group_table(prim$requests, prim$eligible, all_city(prim), top)),
  context = group_context(x, prim, groups, PARAMS),
  codes = closure_codes(prim$requests, groups, "SWM-Missed Bulk Trash"),
  inventory = data_inventory(x, PARAMS),
  data_checks = data_checks(x)
)
saveRDS(res, file.path(out_dir, "results", "results.rds"))
write_results(res, tg, x, file.path(out_dir, "results"))
say("figures and report")
build_report(res, tg, x, out_dir)
say("done: ", file.path(out_dir, "report.html"))
