# Statistical treatment (design plan 5.4).
#
# Every metric function returns the same one-row shape -- value, ci_low,
# ci_high, n, suppressed -- so pipelines never hand-roll suppression or
# intervals. Below the minimum n the value and interval are NA, never zero.

MIN_N_PROPORTION <- 30L
MIN_N_MEDIAN <- 20L
DEFAULT_SEED <- 20260923L
DEFAULT_REPS <- 2000L

metric_row <- function(value, ci_low, ci_high, n, suppressed) {
  data.frame(value = as.numeric(value), ci_low = as.numeric(ci_low),
             ci_high = as.numeric(ci_high), n = as.integer(n),
             suppressed = as.logical(suppressed))
}

suppressed_row <- function(n) metric_row(NA, NA, NA, n, TRUE)

dedupe_by_id <- function(x, id) {
  if (is.null(id)) return(x)
  if (length(id) != length(x)) stop("`id` must be the same length as the data", call. = FALSE)
  x[!duplicated(id)]
}

#' Wilson score interval for a binomial proportion.
#' @export
wilson_ci <- function(x, n, conf = 0.95) {
  z <- stats::qnorm(1 - (1 - conf) / 2)
  p <- ifelse(n > 0, x / n, NA_real_)
  denom <- 1 + z^2 / n
  centre <- (p + z^2 / (2 * n)) / denom
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denom
  data.frame(ci_low = pmax(0, centre - half), ci_high = pmin(1, centre + half))
}

with_seed <- function(seed, code) {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (had) old <- get(".Random.seed", envir = globalenv())
  on.exit(if (had) assign(".Random.seed", old, envir = globalenv())
          else rm(".Random.seed", envir = globalenv()))
  set.seed(seed)
  code
}

#' Percentile bootstrap interval for the median.
#'
#' The data are sorted before resampling and the seed is fixed, so the result
#' is reproducible and invariant to record order.
#' @export
bootstrap_median_ci <- function(x, conf = 0.95, reps = DEFAULT_REPS, seed = DEFAULT_SEED) {
  x <- sort(x[!is.na(x)])
  if (!length(x)) return(data.frame(ci_low = NA_real_, ci_high = NA_real_))
  meds <- with_seed(seed, vapply(seq_len(reps), function(i)
    stats::median(x[sample.int(length(x), replace = TRUE)]), numeric(1)))
  q <- stats::quantile(meds, c((1 - conf) / 2, 1 - (1 - conf) / 2), names = FALSE, type = 7)
  data.frame(ci_low = q[1], ci_high = q[2])
}

#' Exact (Garwood) Poisson interval for a count, optionally as a rate.
#' @export
poisson_rate_ci <- function(count, exposure = 1, per = 1, conf = 0.95) {
  a <- 1 - conf
  lo <- ifelse(count == 0, 0, stats::qchisq(a / 2, 2 * count) / 2)
  hi <- stats::qchisq(1 - a / 2, 2 * (count + 1)) / 2
  data.frame(value = count / exposure * per, ci_low = lo / exposure * per,
             ci_high = hi / exposure * per)
}

#' Proportion metric with Wilson interval and minimum-n suppression.
#'
#' @param success logical vector; NA entries are dropped (not counted as
#'   failures).
#' @param id optional record ids; duplicates are dropped before computing.
#' @export
metric_proportion <- function(success, min_n = MIN_N_PROPORTION, conf = 0.95, id = NULL) {
  success <- dedupe_by_id(success, id)
  success <- success[!is.na(success)]
  n <- length(success)
  if (n < min_n) return(suppressed_row(n))
  x <- sum(success)
  ci <- wilson_ci(x, n, conf)
  metric_row(x / n, ci$ci_low, ci$ci_high, n, FALSE)
}

#' Median metric with bootstrap percentile interval and minimum-n suppression.
#' @export
metric_median <- function(x, min_n = MIN_N_MEDIAN, conf = 0.95, reps = DEFAULT_REPS,
                          seed = DEFAULT_SEED, id = NULL) {
  x <- dedupe_by_id(x, id)
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < min_n) return(suppressed_row(n))
  ci <- bootstrap_median_ci(x, conf, reps, seed)
  metric_row(stats::median(x), ci$ci_low, ci$ci_high, n, FALSE)
}

#' Median of right-censored durations (Kaplan-Meier), for requests or
#' outages still open at computation time.
#'
#' @param time duration (e.g. business days open so far, or to close).
#' @param event TRUE if the duration ended (closed), FALSE if still open.
#' @return A metric row. The median (or an interval bound) is NA when the
#'   survival curve does not drop to 0.5 within the observed data; if the
#'   point estimate itself is not reached the row is suppressed.
#' @export
metric_censored_median <- function(time, event, min_n = MIN_N_MEDIAN, conf = 0.95, id = NULL) {
  if (!is.null(id)) {
    keep <- !duplicated(id)
    time <- time[keep]; event <- event[keep]
  }
  ok <- !is.na(time) & !is.na(event)
  time <- time[ok]; event <- as.logical(event[ok])
  n <- length(time)
  if (n < min_n) return(suppressed_row(n))
  fit <- survival::survfit(survival::Surv(time, event) ~ 1, conf.int = conf,
                           conf.type = "log-log")
  q <- stats::quantile(fit, probs = 0.5)
  med <- unname(q$quantile); lo <- unname(q$lower); hi <- unname(q$upper)
  if (is.na(med)) return(suppressed_row(n))
  metric_row(med, lo, hi, n, FALSE)
}

#' Rate per `per` units of exposure (e.g. per 1,000 residents) with an exact
#' Poisson interval. Suppressed when the count or exposure is below minimum.
#' @export
metric_rate <- function(count, exposure, per = 1000, min_count = 0L, min_exposure = 1,
                        conf = 0.95) {
  if (is.na(exposure) || exposure < min_exposure || is.na(count) || count < min_count)
    return(suppressed_row(if (is.na(count)) 0L else count))
  r <- poisson_rate_ci(count, exposure, per, conf)
  metric_row(r$value, r$ci_low, r$ci_high, count, FALSE)
}

#' Smallest rolling window (in days) that clears the minimum n.
#'
#' Design plan 5.4 "small-area stability": a quiet area may legitimately be
#' reported over 12 months where a busy one uses 90 days. Returns NA when no
#' candidate window clears `min_n`.
#' @export
choose_window <- function(event_dates, window_end, min_n,
                          windows = c(90L, 180L, 365L)) {
  event_dates <- as.Date(event_dates)
  window_end <- as.Date(window_end)
  for (w in sort(windows)) {
    n <- sum(event_dates > window_end - w & event_dates <= window_end, na.rm = TRUE)
    if (n >= min_n) return(as.integer(w))
  }
  NA_integer_
}

#' Compare two intervals. The site never declares "significant" differences;
#' overlapping intervals are labelled "not clearly different".
#' @export
compare_intervals <- function(a_low, a_high, b_low, b_high) {
  out <- ifelse(a_low > b_high, "higher",
         ifelse(a_high < b_low, "lower", "not clearly different"))
  out[is.na(a_low) | is.na(a_high) | is.na(b_low) | is.na(b_high)] <- "insufficient data"
  out
}
