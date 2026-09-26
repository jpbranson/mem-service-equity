# Build the permits golden files (plan 5.3): a frozen sample of real source
# data, the parcel counts used with it, and the metrics computed from them.
# Every pipeline change must reproduce these outputs
# (tests/testthat/test-permits.R). Rebuild ONLY when a spec version changes,
# and say why in the commit message.
#
# Usage: Rscript pipelines/permits/tests/build_golden.R <raw.rds>

args <- commandArgs(trailingOnly = TRUE)
raw <- readRDS(args[1])
for (f in list.files(file.path("pipelines", "permits", "R"), full.names = TRUE)) source(f)
source(file.path("pipelines", "permits", "tests", "golden.R"))
cfg <- read_permits_config(file.path("pipelines", "permits", "config"))

# Three ZIP codes (by the source's own ZIP field), issued 2021-2025, with the
# data complete through the end of 2025.
through <- as.Date("2025-12-31")
keep <- raw$ZIP_Code %in% c("38104", "38106", "38112") &
  memequity::local_date(raw$Issued_Date) <= through
gold <- raw[keep, ]
dir <- file.path("pipelines", "permits", "tests", "golden")
dir.create(dir, showWarnings = FALSE, recursive = TRUE)
saveRDS(gold, file.path(dir, "golden_raw.rds"), compress = "xz")
writeLines(format(through), file.path(dir, "golden_through.txt"))

parcels <- do.call(rbind, lapply(PERMIT_GEOS, function(g)
  cbind(geo_type = g, memequity::area_parcels(g, "geography"))))
utils::write.csv(parcels, file.path(dir, "golden_parcels.csv"), row.names = FALSE)

pts <- attach_geography_permits(normalize_permits(gold, cfg, through), "geography")
m <- golden_order(compute_metrics_permits(pts, golden_parcels(dir), through))
utils::write.csv(m, file.path(dir, "golden_metrics.csv"), row.names = FALSE)
message(nrow(gold), " golden input rows; ", nrow(m), " golden metric rows")
