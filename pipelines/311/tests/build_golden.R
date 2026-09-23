# Build the 311 golden files (plan 5.3): a frozen sample of real source data
# and the metrics computed from it. Every pipeline change must reproduce
# these outputs (tests/testthat/test-311.R). Rebuild ONLY when a spec
# version changes, and say why in the commit message.
#
# Usage: Rscript pipelines/311/tests/build_golden.R <raw.rds>

args <- commandArgs(trailingOnly = TRUE)
raw <- readRDS(args[1])
for (f in list.files(file.path("pipelines", "311", "R"), full.names = TRUE)) source(f)
cfg <- read_311_config(file.path("pipelines", "311", "config"))

# Council District 5, three request types, created 2024-10-01..2025-06-30.
keep <- raw$REQUEST_TYPE %in% c("PW (SM)-Potholes", "SWM-Missed Bulk Trash", "EE-Illegal Dumping") &
  raw$cd_name %in% 5L &
  raw$created_date >= as.POSIXct("2024-10-01", tz = "UTC") &
  raw$created_date < as.POSIXct("2025-07-01", tz = "UTC")
gold <- raw[keep, ]
dir <- file.path("pipelines", "311", "tests", "golden")
dir.create(dir, showWarnings = FALSE, recursive = TRUE)
saveRDS(gold, file.path(dir, "golden_raw.rds"), compress = "xz")

sr <- normalize_311(gold, cfg, as.Date("2025-07-01"))
pts <- attach_geography_311(sr, "geography")
m <- compute_metrics_311(pts, cfg$request_types, as.Date("2025-06-30"))$metrics
m <- m[order(m$metric, m$variant, m$subgroup, m$geo_type, m$geo_id, m$window_start),
       c("metric", "variant", "subgroup", "geo_type", "geo_id", "window_start", "value",
         "ci_low", "ci_high", "n", "suppressed")]
m$window_start <- format(as.Date(m$window_start))
utils::write.csv(m, file.path(dir, "golden_metrics.csv"), row.names = FALSE)
message(nrow(gold), " golden input rows; ", nrow(m), " golden metric rows")
