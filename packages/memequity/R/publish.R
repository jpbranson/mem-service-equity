# The publish gate (design plan 5.7). A metric appears on the site only when
# every condition holds; otherwise the panel shows what is missing and why.

RECONCILIATION_MAX_AGE_DAYS <- 92L

#' Evaluate the six publication conditions for one metric.
#'
#' @param spec a spec from read_spec().
#' @param report the current run's validation report (finalized).
#' @param tests_passed TRUE if the metric tests and golden files passed.
#' @param metrics the metric's rows from the metrics table.
#' @param reconciliation list(date = , gap_documented = TRUE/FALSE) or NULL.
#' @param audit_path path to the committed pre-launch audit sheet, or NULL.
#' @return list(publishable = TRUE/FALSE, missing = character())
#' @export
publish_gate <- function(spec, report, tests_passed, metrics, reconciliation = NULL,
                         audit_path = NULL, as_of = Sys.Date()) {
  missing <- character()
  # A spec can say it cannot be computed yet and why (e.g. no data source).
  if (nzchar(spec$blocked %||% ""))
    missing <- c(missing, paste("blocked:", trimws(spec$blocked)))
  if (!identical(spec$status, "frozen") || length(spec_problems(spec)))
    missing <- c(missing, "spec is not frozen and versioned")
  if (is.na(report$status)) report <- finalize_report(report)
  if (!identical(report$status, "pass"))
    missing <- c(missing, "source validation did not pass for the current run")
  if (!isTRUE(tests_passed))
    missing <- c(missing, "metric tests or golden files have not passed")
  pub <- metrics[!metrics$suppressed, , drop = FALSE]
  if (!nrow(pub) || anyNA(pub$ci_low) || anyNA(pub$ci_high))
    missing <- c(missing, "no cell clears the minimum n with an interval")
  if (is.null(reconciliation) ||
      as.integer(as.Date(as_of) - as.Date(reconciliation$date)) > RECONCILIATION_MAX_AGE_DAYS)
    missing <- c(missing, "reconciliation is missing or older than one quarter")
  else if (!isTRUE(reconciliation$gap_documented))
    missing <- c(missing, "reconciliation gap is not documented")
  if (is.null(audit_path) || !file.exists(audit_path))
    missing <- c(missing, "pre-launch manual audit is not committed")
  else if (length(ap <- audit_problems(audit_path)))
    missing <- c(missing, paste("pre-launch manual audit is incomplete:", ap[1]))
  list(metric = spec$id, publishable = !length(missing), missing = missing)
}

AUDIT_MIN_RECORDS <- 100L
AUDIT_ANSWERS <- c("yes", "no", "n/a")

#' Problems with a committed manual-audit sheet (empty when complete).
#'
#' Plan 5.6: at least 100 records traced by hand. The check columns are the
#' ones whose names start with a digit and an underscore (e.g.
#' `1_found_in_source`). A complete sheet answers every check on every row
#' with yes, no or n/a, names the auditor on every row, and explains every
#' "no" in `notes`. A blank worksheet copied into place is not an audit.
#' @export
audit_problems <- function(path, min_records = AUDIT_MIN_RECORDS) {
  a <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character",
                       na.strings = character(), check.names = FALSE, encoding = "UTF-8")
  checks <- grep("^[0-9]+_", names(a), value = TRUE)
  p <- character()
  if (nrow(a) < min_records) p <- c(p, sprintf("%d records traced, %d needed", nrow(a), min_records))
  if (!length(checks)) return(c(p, "no check columns (named like 1_found_in_source)"))
  if (!"auditor" %in% names(a) || any(!nzchar(trimws(a$auditor))))
    p <- c(p, "auditor is missing on some rows")
  answers <- tolower(trimws(unlist(a[checks], use.names = FALSE)))
  if (any(!answers %in% AUDIT_ANSWERS))
    p <- c(p, sprintf("%d check answers are blank or not yes/no/n/a", sum(!answers %in% AUDIT_ANSWERS)))
  no <- apply(a[checks], 1, function(r) any(tolower(trimws(r)) == "no"))
  notes <- if ("notes" %in% names(a)) nzchar(trimws(a$notes)) else rep(FALSE, nrow(a))
  if (any(no & !notes)) p <- c(p, sprintf("%d rows answer no without a note", sum(no & !notes)))
  p
}

#' Write publish_status_<pipeline>.json for the front end.
#' @export
write_publish_status <- function(gates, pipeline, dir) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, sprintf("publish_status_%s.json", pipeline))
  jsonlite::write_json(list(pipeline = pipeline,
                            evaluated_at = format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
                            metrics = lapply(gates, function(g) list(
                              metric = g$metric, publishable = g$publishable,
                              missing = as.list(g$missing)))),
                       path, auto_unbox = TRUE, pretty = TRUE)
  invisible(path)
}
