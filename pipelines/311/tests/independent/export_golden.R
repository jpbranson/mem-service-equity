# Export the golden input for the independent recomputation (DECISIONS.md
# H20). Writes plain CSVs only: no pipeline code runs here, so the Python
# check in recompute_golden.py shares nothing with the R metrics except the
# raw records, the config files and the holiday dates.
#
# Usage (from the repository root):
#   Rscript pipelines/311/tests/independent/export_golden.R <out_dir>

args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args)) args[1] else tempfile("golden_export_")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

raw <- readRDS(file.path("pipelines", "311", "tests", "golden", "golden_raw.rds"))
iso <- function(x) ifelse(is.na(x), "", format(x, tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"))
for (f in names(raw)) if (inherits(raw[[f]], "POSIXct")) raw[[f]] <- iso(raw[[f]])
raw$longitude <- sprintf("%.8f", raw$longitude)
raw$latitude <- sprintf("%.8f", raw$latitude)
utils::write.csv(raw, file.path(out, "golden_raw.csv"), row.names = FALSE, na = "")

# The calendar itself is checked separately (DECISIONS.md D10, H13); the
# recomputation takes its dates as given. Same years as normalize_311().
hol <- memequity::holiday_calendar(2023:2026)
utils::write.csv(data.frame(date = format(hol$date)), file.path(out, "holidays.csv"), row.names = FALSE)
message("exported ", nrow(raw), " golden rows and ", nrow(hol), " holidays to ", out)
cat(out, "\n")
