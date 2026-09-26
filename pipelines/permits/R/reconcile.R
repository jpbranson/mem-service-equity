# External reconciliation (plan 5.5, DECISIONS.md D14, D22). The official
# figures are the Census Building Permits Survey's annual counts of new
# residential buildings for the joint Memphis/Shelby permitting office
# (reconciliation/fetch_bps.R). The Survey counts the whole jurisdiction,
# so this counts every permit in the layer, inside the city or not.

MEASURES_PERMITS <- list(
  # New residential permits issued in the period (local dates). The Survey
  # counts buildings; a permit is issued per building.
  census_bps_new_residential = function(raw, f, cfg) {
    sector <- cfg$sector_map$sector[match(raw$Sub_Type, cfg$sector_map$sub_type)]
    category <- cfg$category_map$category[match(raw$Construction_Type, cfg$category_map$construction_type)]
    d <- memequity::local_date(raw$Issued_Date)
    sum(!is.na(d) & d >= f$period_start & d <= f$period_end & sector %in% "residential" &
          category %in% "new")
  }
)

#' Recompute every official permits figure. Returns NULL when there are none.
reconcile_permits <- function(raw, cfg, official_path, as_of) {
  if (!file.exists(official_path)) return(NULL)
  off <- memequity::read_official_figures(official_path)
  if (!nrow(off)) return(NULL)
  unknown <- setdiff(off$measure, names(MEASURES_PERMITS))
  if (length(unknown))
    stop("no permits computation for measure(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  ours <- vapply(seq_len(nrow(off)), function(i)
    as.numeric(MEASURES_PERMITS[[off$measure[i]]](raw, off[i, ], cfg)), numeric(1))
  memequity::reconcile_figures(off, ours, as_of)
}
