# External reconciliation (plan 5.5, DECISIONS.md D22). No official count of
# Shelby County food inspections has been identified yet, so
# reconciliation/official_figures.csv is empty and the metrics report
# reconciliation as missing. The measure below is ready for such a figure.

MEASURES_FOOD <- list(
  # Inspections of any type conducted in the period (all establishments in
  # the export, located or not). `subgroup` may name inspection kinds
  # separated by "|" (e.g. "routine|follow_up").
  inspection_counts = function(ins, f) {
    keep <- !is.na(ins$inspection_date) & ins$inspection_date >= f$period_start &
      ins$inspection_date <= f$period_end
    if (nzchar(f$subgroup)) keep <- keep & ins$kind %in% strsplit(f$subgroup, "|", fixed = TRUE)[[1]]
    sum(keep)
  }
)

#' Recompute every official food-safety figure from the normalized
#' inspections. Returns NULL when there are none.
reconcile_food <- function(ins, official_path, as_of) {
  if (!file.exists(official_path)) return(NULL)
  off <- memequity::read_official_figures(official_path)
  if (!nrow(off)) return(NULL)
  unknown <- setdiff(off$measure, names(MEASURES_FOOD))
  if (length(unknown))
    stop("no food-safety computation for measure(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  ours <- vapply(seq_len(nrow(off)), function(i)
    as.numeric(MEASURES_FOOD[[off$measure[i]]](ins, off[i, ])), numeric(1))
  memequity::reconcile_figures(off, ours, as_of)
}
