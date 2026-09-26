# Official figures for the permits reconciliation (plan 5.5, DECISIONS.md
# D14, D22): new residential buildings authorized in the joint
# Memphis/Shelby permitting jurisdiction, from the Census Bureau Building
# Permits Survey place files. Memphis does not report as a place; the joint
# Construction Code Enforcement office reports as "Shelby County
# Unincorporated Area" (state 47, county 157, place 99990).
#
# Rewrites official_figures.csv from the annual files, keeping any gap_note
# already recorded for a figure_id. Run it once a year after the Census
# publishes the previous year's annual file.
#
# Usage (from the repository root):
#   Rscript pipelines/permits/reconciliation/fetch_bps.R [first_year] [last_year]

args <- commandArgs(trailingOnly = TRUE)
first <- if (length(args) >= 1) as.integer(args[1]) else 2021L
last <- if (length(args) >= 2) as.integer(args[2]) else as.integer(format(Sys.Date(), "%Y")) - 1L
BASE <- "https://www2.census.gov/econ/bps/Place/South%20Region/"
UA <- "memphis-service-equity (https://github.com/jpbranson/mem-service-equity)"
here <- file.path("pipelines", "permits", "reconciliation")
path <- file.path(here, "official_figures.csv")

bps_row <- function(year) {
  url <- sprintf("%sso%da.txt", BASE, year)
  resp <- httr2::request(url) |> httr2::req_user_agent(UA) |> httr2::req_retry(max_tries = 4) |>
    httr2::req_error(is_error = function(r) FALSE) |> httr2::req_perform()
  if (httr2::resp_status(resp) != 200) return(NULL)
  lines <- strsplit(httr2::resp_body_string(resp), "\r?\n")[[1]]
  f <- strsplit(lines, ",", fixed = TRUE)
  hit <- Filter(function(x) length(x) >= 29 && x[2] == "47" && trimws(x[4]) == "157" &&
                  trimws(x[6]) == "99990", f)
  if (length(hit) != 1) stop("expected one Shelby County Unincorporated row in ", url, call. = FALSE)
  x <- hit[[1]]
  # Columns 18, 21, 24, 27: buildings with 1, 2, 3-4 and 5+ units (the
  # estimates, which include imputation for unreported months).
  bldgs <- sum(as.integer(x[c(18, 21, 24, 27)]))
  modified <- httr2::resp_header(resp, "last-modified")
  data.frame(
    figure_id = sprintf("bps_%d", year), measure = "census_bps_new_residential", subgroup = "",
    period_start = sprintf("%d-01-01", year), period_end = sprintf("%d-12-31", year),
    value = bldgs, precision = 1,
    definition = paste("New privately owned residential buildings authorized by building permits",
                       "(1, 2, 3-4 and 5+ units), Shelby County Unincorporated Area (place 99990),",
                       sprintf("which covers the joint Memphis/Shelby permitting office; %s months reported.",
                               trimws(x[16]))),
    source_title = sprintf("Census Bureau Building Permits Survey, place annual file so%da.txt", year),
    source_url = url, source_page = "",
    published = if (is.null(modified)) "" else format(as.Date(modified, "%a, %d %b %Y"), "%Y-%m-%d"),
    transcribed = format(Sys.Date()), gap_note = "", stringsAsFactors = FALSE)
}

rows <- Filter(Negate(is.null), lapply(first:last, bps_row))
new <- do.call(rbind, rows)
if (file.exists(path)) {
  old <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character", na.strings = "")
  keep <- old$gap_note[match(new$figure_id, old$figure_id)]
  new$gap_note <- ifelse(is.na(keep), "", keep)
}
utils::write.csv(new, path, row.names = FALSE, na = "")
message(nrow(new), " annual figures (", paste(range(first:last), collapse = "-"), ") -> ", path)
print(new[, c("figure_id", "value", "published")])
