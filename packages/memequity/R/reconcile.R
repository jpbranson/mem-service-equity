# External reconciliation (design plan 5.5, publication condition 5 in 5.7;
# DECISIONS.md D22). Official figures are transcribed by hand from official
# documents into pipelines/<pipeline>/reconciliation/official_figures.csv.
# Each pipeline recomputes every figure from its own data, using the
# definition the source states, and these helpers compare the two. A metric's
# spec names the measures it is reconciled against (`reconciliation.measures`).

RECONCILIATION_TOLERANCE <- 0.02

OFFICIAL_FIGURE_COLUMNS <- c("figure_id", "measure", "subgroup", "period_start", "period_end",
                             "value", "precision", "definition", "source_title", "source_url",
                             "source_page", "published", "transcribed", "gap_note")

#' Read and check a pipeline's hand-transcribed official figures.
#'
#' Every row needs a measure, a numeric value, a period and a source URL.
#' `precision` is the rounding unit of the published value (1 for an exact
#' count, 1000 for "about 250,000"). `gap_note` stays empty unless a gap was
#' investigated and explained.
#' @export
read_official_figures <- function(path) {
  f <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"),
                       encoding = "UTF-8", colClasses = "character")
  missing <- setdiff(OFFICIAL_FIGURE_COLUMNS, names(f))
  if (length(missing)) stop("official figures file lacks columns: ", paste(missing, collapse = ", "),
                            call. = FALSE)
  f$value <- as.numeric(f$value)
  f$precision <- as.numeric(ifelse(is.na(f$precision), "1", f$precision))
  f$period_start <- as.Date(f$period_start)
  f$period_end <- as.Date(f$period_end)
  bad <- is.na(f$figure_id) | is.na(f$measure) | is.na(f$value) | is.na(f$period_start) |
    is.na(f$period_end) | is.na(f$source_url) | f$period_end < f$period_start
  if (any(bad)) stop("official figures rows are incomplete: ",
                     paste(which(bad), collapse = ", "), call. = FALSE)
  if (anyDuplicated(f$figure_id)) stop("official figures have duplicate figure_id", call. = FALSE)
  f$subgroup[is.na(f$subgroup)] <- ""
  f$gap_note[is.na(f$gap_note)] <- ""
  f
}

#' Compare official figures with the pipeline's own values.
#'
#' A gap is within tolerance when it is no larger than `tolerance` of the
#' official value or half the published rounding unit, whichever is larger.
#' A larger gap counts as documented only when the figure has a `gap_note`
#' (plan 5.5: a discrepancy is investigated and documented before anything is
#' published).
#' @param official data.frame from read_official_figures().
#' @param our_value numeric, the pipeline's value for each row of `official`.
#' @export
reconcile_figures <- function(official, our_value, as_of = Sys.Date(),
                              tolerance = RECONCILIATION_TOLERANCE) {
  stopifnot(length(our_value) == nrow(official))
  gap <- our_value - official$value
  allowed <- pmax(tolerance * abs(official$value), official$precision / 2)
  within <- !is.na(gap) & abs(gap) <= allowed
  data.frame(
    figure_id = official$figure_id, measure = official$measure, subgroup = official$subgroup,
    period_start = format(official$period_start), period_end = format(official$period_end),
    official_value = official$value, our_value = our_value, gap = gap,
    relative_gap = ifelse(official$value == 0, NA_real_, gap / official$value),
    within_tolerance = within,
    documented = within | nzchar(official$gap_note),
    gap_note = official$gap_note, source_title = official$source_title,
    source_url = official$source_url, source_page = official$source_page,
    date = format(as.Date(as_of)), stringsAsFactors = FALSE)
}

#' The reconciliation record the publish gate needs for one spec.
#'
#' Collects every result whose measure the spec lists under
#' `reconciliation.measures`. Returns NULL when there is none, so the gate
#' reports reconciliation as missing.
#' @param results data.frame from reconcile_figures(), or NULL.
#' @export
spec_reconciliation <- function(spec, results) {
  measures <- unlist(spec$reconciliation$measures)
  if (is.null(results) || !length(measures)) return(NULL)
  r <- results[results$measure %in% measures, , drop = FALSE]
  if (!nrow(r)) return(NULL)
  list(date = min(as.Date(r$date)), gap_documented = all(r$documented), figures = r$figure_id)
}

#' Write reconciliation_<pipeline>.csv.
#' @export
write_reconciliation <- function(results, pipeline, dir) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, sprintf("reconciliation_%s.csv", pipeline))
  utils::write.csv(results, path, row.names = FALSE, na = "")
  invisible(path)
}
