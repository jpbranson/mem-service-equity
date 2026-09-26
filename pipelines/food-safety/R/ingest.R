# Ingest: read the records-request export from inbox/ and rename its columns
# to the canonical fields in config/column_map.yml (DECISIONS.md H11, D13).
# Nothing is fetched from the web: the state portal forbids automated
# access (D11).

read_food_config <- function(dir) {
  types <- utils::read.csv(file.path(dir, "inspection_types.csv"), stringsAsFactors = FALSE,
                           na.strings = character(), encoding = "UTF-8")
  list(column_map = yaml::read_yaml(file.path(dir, "column_map.yml")),
       inspection_types = types,
       rules = yaml::read_yaml(file.path(dir, "rules.yml")))
}

#' The export file for one table: the first file in `inbox` whose name
#' contains the table's file_pattern. NULL if there is none.
find_export_file <- function(inbox, pattern) {
  files <- sort(list.files(inbox, pattern = "\\.(csv|xlsx)$", ignore.case = TRUE, full.names = TRUE))
  hit <- files[grepl(pattern, basename(files), ignore.case = TRUE)]
  if (length(hit)) hit[1] else NULL
}

read_export_file <- function(path) {
  if (grepl("\\.xlsx$", path, ignore.case = TRUE)) {
    if (!requireNamespace("readxl", quietly = TRUE))
      stop("reading ", basename(path), " needs the readxl package", call. = FALSE)
    return(as.data.frame(readxl::read_xlsx(path, col_types = "text")))
  }
  utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE,
                  na.strings = c("", "NA", "NULL"), encoding = "UTF-8")
}

#' Parse dates written in any of `formats` (first plausible match wins per
#' value). as.Date() ignores trailing characters and "%Y" accepts two-digit
#' years, so a parse is kept only when its year is plausible (1990-2100).
parse_dates <- function(x, formats) {
  out <- as.Date(rep(NA_character_, length(x)))
  x <- trimws(x)
  for (f in formats) {
    todo <- is.na(out) & !is.na(x) & nzchar(x)
    if (!any(todo)) break
    d <- suppressWarnings(as.Date(x[todo], format = f))
    yr <- as.integer(format(d, "%Y"))
    d[is.na(yr) | yr < 1990 | yr > 2100] <- NA
    out[todo] <- d
  }
  out
}

#' Read one table and return it with canonical column names. Returns NULL
#' when the export has no file for the table; `attr(, "absent")` lists
#' canonical fields that could not be found.
read_canonical_table <- function(inbox, spec, date_formats) {
  path <- find_export_file(inbox, spec$file_pattern)
  if (is.null(path)) return(NULL)
  raw <- read_export_file(path)
  cols <- spec$columns
  out <- data.frame(row.names = seq_len(nrow(raw)))
  absent <- character()
  for (field in names(cols)) {
    src <- cols[[field]]
    if (is.null(src) || !src %in% names(raw)) { absent <- c(absent, field); next }
    out[[field]] <- trimws(raw[[src]])
  }
  for (f in intersect(c("inspection_date", "closed_date"), names(out)))
    out[[f]] <- parse_dates(out[[f]], date_formats)
  attr(out, "file") <- basename(path)
  attr(out, "absent") <- absent
  attr(out, "missing_required") <- intersect(unlist(spec$required), absent)
  out
}

#' Read every table the column map names.
ingest_export <- function(inbox, config) {
  cm <- config$column_map
  stats::setNames(lapply(names(cm$tables), function(t)
    read_canonical_table(inbox, cm$tables[[t]], unlist(cm$date_formats))), names(cm$tables))
}
