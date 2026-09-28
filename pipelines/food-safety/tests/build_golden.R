# Build the food-safety golden files (plan 5.3): a frozen sample of real
# source data in the collector's layout (DECISIONS.md D29), the geocodes for
# its establishments, and the metrics computed from them. Every pipeline
# change must reproduce these outputs (tests/testthat/test-food.R). Rebuild
# ONLY when a spec version changes, and say why in the commit message.
#
# Usage: Rscript pipelines/food-safety/tests/build_golden.R <inspections.csv>
# Addresses missing from data/cache/food-safety/geocode.csv go to the Census
# geocoder once; the test only reads the frozen geocodes.

args <- commandArgs(trailingOnly = TRUE)
here <- file.path("pipelines", "food-safety")
for (f in list.files(file.path(here, "R"), full.names = TRUE)) source(f)
source(file.path(here, "tests", "golden.R"))
cfg <- read_food_config(file.path(here, "config"))
cols <- unlist(cfg$column_map$tables$inspections$columns)
raw <- read_export_file(args[1])

# Three ZIP codes (by the source's own ZIP field), every program, inspected
# 2025-01-01 through 2026-06-30. Only the mapped columns are kept: the free
# text comments can hold operators' e-mail addresses and phone numbers.
# Permit types that can be a private home are left out of the sample (the
# pipeline never geocodes them either), so no home address is committed.
from <- as.Date("2025-01-01")
through <- as.Date("2026-06-30")
homes <- c("Commercial Food <51 (Mobile)", "Family Child Care Home (Fee Exempt)", "Fee Exempt",
           "Group Child Care Home")
date <- parse_dates(raw[[cols[["inspection_date"]]]], unlist(cfg$column_map$date_formats))
keep <- (substr(raw[[cols[["zip"]]]], 1, 5) %in% c("38104", "38106", "38117") &
  !raw[[cols[["establishment_type"]]]] %in% homes & date >= from & date <= through) %in% TRUE
gold <- raw[keep, unname(cols)]
gold <- gold[order(gold[[cols[["inspection_id"]]]]), ]
dir <- file.path(here, "tests", "golden")
dir.create(file.path(dir, "inbox"), showWarnings = FALSE, recursive = TRUE)
utils::write.csv(gold, file.path(dir, "inbox", "inspections.csv"), row.names = FALSE, na = "",
                 fileEncoding = "UTF-8")
writeLines(format(from), file.path(dir, "golden_from.txt"))
writeLines(format(through), file.path(dir, "golden_through.txt"))

# Geocode as run.R does (through the cache), recording each answer.
seen <- NULL
recorder <- function(street, city = "Memphis", state = "TN", zip = "", cache_path = NULL) {
  g <- memequity::geocode_addresses(street, city = city, state = state, zip = zip,
                                    cache_path = file.path("data", "cache", "food-safety", "geocode.csv"))
  seen <<- data.frame(address = street, city = city, zip = zip, longitude = g$longitude,
                      latitude = g$latitude, match_quality = g$match_quality, stringsAsFactors = FALSE)
  g
}
invisible(golden_food(dir, cfg, "geography", geocoder = recorder))
seen <- seen[order(seen$address, seen$city, seen$zip), ]
utils::write.csv(unique(seen), file.path(dir, "golden_geocodes.csv"), row.names = FALSE, na = "",
                 fileEncoding = "UTF-8")

# The frozen outputs come from the frozen inputs alone, as the test runs.
m <- golden_order(golden_food(dir, cfg, "geography"))
utils::write.csv(m, file.path(dir, "golden_metrics.csv"), row.names = FALSE)
message(nrow(gold), " golden input rows; ", nrow(unique(seen)), " geocodes; ", nrow(m), " golden metric rows")
