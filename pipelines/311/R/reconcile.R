# External reconciliation (plan 5.5, DECISIONS.md D22). Each row of
# reconciliation/official_figures.csv is a figure the City published, copied
# by hand from the cited document. The pipeline recomputes it from the raw
# layer using the definition the City states, and the publish gate needs the
# result for every metric whose spec names that measure.

# A figure's `subgroup` is "" (all requests), request types separated by "|",
# or "category:<prefix>" for every type in that category of
# config/request_types.csv.
subgroup_filter <- function(raw, subgroup, request_types) {
  if (!nzchar(subgroup)) return(rep(TRUE, nrow(raw)))
  if (startsWith(subgroup, "category:")) {
    cat <- sub("^category:", "", subgroup)
    return(raw$REQUEST_TYPE %in% request_types$request_type[request_types$category %in% cat])
  }
  raw$REQUEST_TYPE %in% strsplit(subgroup, "|", fixed = TRUE)[[1]]
}

in_period <- function(dates, f) !is.na(dates) & dates >= f$period_start & dates <= f$period_end

# How each measure is computed from the raw layer. Official counts include
# every record the City's system holds, so nothing is deduplicated or
# excluded here beyond what the figure's definition says.
MEASURES_311 <- list(
  # Service requests created in the period (local dates), all statuses.
  requests_created = function(raw, f, cfg) {
    sum(in_period(memequity::local_date(raw$created_date), f) &
          subgroup_filter(raw, f$subgroup, cfg$request_types))
  }
)

#' Recompute every official 311 figure. Returns NULL when there are none.
reconcile_311 <- function(raw, cfg, official_path, as_of) {
  if (!file.exists(official_path)) return(NULL)
  off <- memequity::read_official_figures(official_path)
  if (!nrow(off)) return(NULL)
  unknown <- setdiff(off$measure, names(MEASURES_311))
  if (length(unknown))
    stop("no 311 computation for measure(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  # The current system went live on 2023-10-16; a figure that starts earlier
  # cannot be reproduced from this layer (plan 6.3: never across the migration).
  early <- off$period_start < MIGRATION_DATE
  if (any(early))
    stop("official figures start before the 2023-10-16 migration: ",
         paste(off$figure_id[early], collapse = ", "), call. = FALSE)
  ours <- vapply(seq_len(nrow(off)), function(i)
    as.numeric(MEASURES_311[[off$measure[i]]](raw, off[i, ], cfg)), numeric(1))
  memequity::reconcile_figures(off, ours, as_of)
}
