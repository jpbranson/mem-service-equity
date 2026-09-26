# Export City of Memphis holiday dates for the independent checks
# (trace_audit.py). Same years as normalize_311() for a run in `year`:
# 2023 through year + 1.
#
# Usage: Rscript pipelines/311/tests/independent/export_holidays.R <out.csv> [year]

args <- commandArgs(trailingOnly = TRUE)
year <- if (length(args) >= 2) as.integer(args[2]) else as.integer(format(Sys.Date(), "%Y"))
hol <- memequity::holiday_calendar(2023:(year + 1))
utils::write.csv(data.frame(date = format(hol$date)), args[1], row.names = FALSE)
message(nrow(hol), " holidays, 2023-", year + 1, " -> ", args[1])
