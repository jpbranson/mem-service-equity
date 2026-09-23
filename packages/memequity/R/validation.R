# Source-data validation harness (design plan 5.2).
#
# A pipeline builds one report per run, adds checks to it, writes it to disk,
# and then calls stop_if_failed(). The report is written even when the run
# fails, so a halted run still leaves evidence of why it halted.

#' Start a validation report for one pipeline run.
#' @export
validation_report <- function(pipeline, run_date = Sys.Date(), source = NULL) {
  structure(list(
    pipeline = pipeline,
    source = source,
    run_date = format(as.Date(run_date)),
    run_at = format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
    status = NA_character_,
    checks = list(),
    record_counts = list(),
    freshness = NULL,
    geocoding = NULL
  ), class = "mse_validation_report")
}

#' Add a check result to a report.
#'
#' @param severity "error" checks fail the run; "warning" checks are recorded
#'   but do not halt.
#' @export
add_check <- function(report, name, type, passed, details = list(), severity = "error") {
  stopifnot(severity %in% c("error", "warning"))
  report$checks[[length(report$checks) + 1]] <- list(
    name = name, type = type, passed = isTRUE(passed), severity = severity, details = details)
  report
}

#' Record a named count (raw rows, deduplicated rows, excluded rows ...).
#' @export
add_count <- function(report, name, value) {
  report$record_counts[[name]] <- as.integer(value)
  report
}

#' Read a schema contract (YAML) describing expected columns.
#'
#' Format:
#' ```
#' columns:
#'   status:
#'     type: character
#'     required: true
#'     nullable: false
#'     allowed: [Open, Closed]
#' allow_extra_columns: false
#' ```
#' @export
read_contract <- function(path) yaml::read_yaml(path)

type_ok <- function(x, type) {
  switch(type,
    character = is.character(x),
    numeric = is.numeric(x),
    integer = is.integer(x) || (is.numeric(x) && all(is.na(x) | x == round(x))),
    logical = is.logical(x),
    date = inherits(x, "Date"),
    datetime = inherits(x, "POSIXct") ||
      (is.character(x) && all(is.na(x) | grepl("^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}", x))),
    stop("Unknown contract type: ", type, call. = FALSE))
}

#' Check a data frame against a schema contract.
#'
#' Fails on missing required columns, wrong types, nulls in non-nullable
#' columns, and -- the important one -- any category value not in the
#' contract's allowed set. A new 311 status code fails the run until it is
#' mapped.
#' @export
check_schema <- function(report, df, contract) {
  cols <- contract$columns
  if (inherits(df, "sf")) df <- sf::st_drop_geometry(df)
  df <- as.data.frame(df)
  for (nm in names(cols)) {
    spec <- cols[[nm]]
    required <- isTRUE(spec$required %||% TRUE)
    if (!nm %in% names(df)) {
      report <- add_check(report, paste0("column present: ", nm), "schema", !required,
                          list(column = nm), if (required) "error" else "warning")
      next
    }
    x <- df[[nm]]
    if (!is.null(spec$type))
      report <- add_check(report, paste0("column type: ", nm), "schema", type_ok(x, spec$type),
                          list(column = nm, expected = spec$type, actual = class(x)[1]))
    if (identical(spec$nullable, FALSE)) {
      nulls <- sum(is.na(x) | (is.character(x) & x == ""))
      report <- add_check(report, paste0("not null: ", nm), "schema", nulls == 0,
                          list(column = nm, null_count = nulls))
    }
    if (!is.null(spec$allowed)) {
      seen <- unique(x[!is.na(x)])
      unknown <- setdiff(as.character(seen), as.character(unlist(spec$allowed)))
      report <- add_check(report, paste0("allowed values: ", nm), "schema", !length(unknown),
                          list(column = nm, unknown_values = as.list(sort(unknown))))
    }
  }
  if (!isTRUE(contract$allow_extra_columns)) {
    extra <- setdiff(names(df), names(cols))
    report <- add_check(report, "no unexpected columns", "schema", !length(extra),
                        list(extra_columns = as.list(extra)), "warning")
  }
  report
}

#' Freshness: the newest record must be within the expected lag.
#' @export
check_freshness <- function(report, timestamps, max_lag_days, as_of = Sys.Date()) {
  newest <- max(local_date(timestamps), na.rm = TRUE)
  if (!is.finite(newest)) newest <- NA
  lag <- as.integer(as.Date(as_of) - newest)
  passed <- !is.na(lag) && lag <= max_lag_days
  report$freshness <- list(data_current_through = format(newest), lag_days = lag,
                           max_lag_days = max_lag_days)
  add_check(report, "freshness", "freshness", passed,
            list(data_current_through = format(newest), lag_days = lag, max_lag_days = max_lag_days))
}

#' Volume bounds: daily record counts must fall within median +/- k * MAD of
#' the trailing window.
#'
#' Checks the `check_days` most recent complete days before `as_of`. When
#' `by_day_type` is TRUE the band for a weekday is built from weekdays only
#' (and weekends from weekends), because most civic data is far quieter on
#' weekends. A zero MAD is floored at 1 record so a perfectly flat history
#' does not fail on a single-record change. Days whose comparison pool has
#' fewer than `min_pool` days are skipped and reported as such.
#' @export
check_volume <- function(report, timestamps, as_of = Sys.Date(), window = 60L, k = 3,
                         check_days = 1L, by_day_type = TRUE, min_pool = 8L) {
  d <- local_date(timestamps)
  as_of <- as.Date(as_of)
  days <- seq(as_of - window - check_days, as_of - 1, by = "day")
  counts <- tabulate(match(d, days), nbins = length(days))
  hist_idx <- seq_len(length(days) - check_days)
  target_idx <- setdiff(seq_along(days), hist_idx)
  weekend <- iso_wday(days) >= 6
  results <- lapply(target_idx, function(i) {
    pool <- hist_idx
    if (by_day_type) pool <- pool[weekend[pool] == weekend[i]]
    if (length(pool) < min_pool)
      return(list(date = format(days[i]), count = counts[i], skipped = "insufficient history"))
    med <- stats::median(counts[pool])
    spread <- max(stats::mad(counts[pool]), 1)
    list(date = format(days[i]), count = counts[i], median = med, mad = spread,
         low = med - k * spread, high = med + k * spread,
         in_band = counts[i] >= med - k * spread && counts[i] <= med + k * spread)
  })
  passed <- all(vapply(results, function(r) is.null(r$in_band) || isTRUE(r$in_band), logical(1)))
  add_check(report, "daily volume within band", "volume", passed, list(days = results, k = k, window = window))
}

#' Exact duplicates on a set of key columns.
#' @export
check_exact_duplicates <- function(report, df, keys, max_share = 0, severity = "error") {
  df <- if (inherits(df, "sf")) sf::st_drop_geometry(df) else df
  dup <- duplicated(df[, keys, drop = FALSE])
  share <- if (nrow(df)) mean(dup) else 0
  add_check(report, paste0("exact duplicates on ", paste(keys, collapse = "+")), "duplicates",
            share <= max_share, list(duplicates = sum(dup), share = share, max_share = max_share),
            severity)
}

#' Flag near-duplicate records: same type, within `meters` and within `days`
#' after an earlier primary record.
#'
#' Rule (deterministic, non-transitive): records are processed in time order
#' within each type. A record is a duplicate if an earlier *primary* record of
#' the same type lies within `meters` and no more than `days` before it; it
#' then points to that primary (the earliest qualifying one). Otherwise it is
#' a primary. Unlocated records are always primaries.
#'
#' @return integer vector: row index of the primary each record duplicates,
#'   or NA for primaries.
#' @export
near_duplicates <- function(points, type, time, meters = 50, days = 7) {
  n <- nrow(points)
  out <- rep(NA_integer_, n)
  if (!n) return(out)
  t <- as.numeric(as.POSIXct(time)) / 86400
  p <- sf::st_transform(sf::st_geometry(points), MSE_CRS_METERS)
  empty <- sf::st_is_empty(p)
  for (ty in unique(type)) {
    ix <- which(type == ty & !empty & !is.na(t))
    if (length(ix) < 2) next
    ix <- ix[order(t[ix], ix)]
    near <- sf::st_is_within_distance(p[ix], p[ix], dist = meters)
    primary <- rep(FALSE, length(ix))
    for (j in seq_along(ix)) {
      cand <- near[[j]]
      cand <- cand[cand < j & primary[cand] & (t[ix[j]] - t[ix[cand]]) <= days]
      if (length(cand)) out[ix[j]] <- ix[min(cand)] else primary[j] <- TRUE
    }
  }
  out
}

#' Geocoding quality: records below the accepted match levels are excluded
#' from spatial metrics and published as the unlocated share.
#' @export
check_geocoding <- function(report, match_quality, accepted = c("exact", "non_exact"),
                            max_unlocated_share = 0.10) {
  unlocated <- is.na(match_quality) | !match_quality %in% accepted
  share <- if (length(match_quality)) mean(unlocated) else 0
  report$geocoding <- list(total = length(match_quality), unlocated = sum(unlocated),
                           unlocated_share = share, accepted = as.list(accepted),
                           by_quality = as.list(table(ifelse(is.na(match_quality), "missing", match_quality))))
  add_check(report, "unlocated share", "geocoding", share <= max_unlocated_share,
            list(unlocated_share = share, max_unlocated_share = max_unlocated_share))
}

#' Referential check: every value must map to a known key.
#' @export
check_referential <- function(report, values, known, name, severity = "error") {
  unknown <- setdiff(unique(values[!is.na(values)]), known)
  add_check(report, name, "referential", !length(unknown),
            list(unknown_values = as.list(utils::head(sort(as.character(unknown)), 50)),
                 unknown_count = length(unknown)), severity)
}

#' Primary-key uniqueness.
#' @export
check_unique <- function(report, ids, name = "unique record id") {
  d <- sum(duplicated(ids[!is.na(ids)]))
  add_check(report, name, "uniqueness", d == 0 && !anyNA(ids),
            list(duplicate_ids = d, missing_ids = sum(is.na(ids))))
}

#' Row-count floor, so an empty or truncated fetch never publishes.
#' @export
check_min_rows <- function(report, df, min_rows) {
  add_check(report, "minimum row count", "volume", nrow(df) >= min_rows,
            list(rows = nrow(df), min_rows = min_rows))
}

#' Compute overall status: "pass" unless any error-severity check failed.
#' @export
finalize_report <- function(report) {
  failed <- vapply(report$checks, function(c) !c$passed && c$severity == "error", logical(1))
  report$status <- if (any(failed)) "fail" else "pass"
  report$summary <- list(checks_run = length(report$checks),
                         checks_passed = sum(vapply(report$checks, `[[`, logical(1), "passed")),
                         errors = sum(failed))
  report
}

#' Names of the error-severity checks that failed.
#' @export
failed_checks <- function(report) {
  Filter(Negate(is.null), lapply(report$checks, function(c)
    if (!c$passed && c$severity == "error") c$name))
}

#' Write the report as validation_<pipeline>_<run_date>.json.
#' @export
write_validation_report <- function(report, dir) {
  if (is.na(report$status)) report <- finalize_report(report)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, sprintf("validation_%s_%s.json", report$pipeline, report$run_date))
  jsonlite::write_json(unclass(report), path, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", na = "null", digits = NA)
  invisible(path)
}

#' Halt the pipeline if any error-severity check failed. Never publish a
#' partial result.
#' @export
stop_if_failed <- function(report) {
  if (is.na(report$status)) report <- finalize_report(report)
  if (report$status == "fail")
    stop("Validation failed for ", report$pipeline, ": ",
         paste(unlist(failed_checks(report)), collapse = "; "), call. = FALSE)
  invisible(report)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
