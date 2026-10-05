# The tract measure: how many requests missed the citywide typical time for
# their request type, against how many would be expected from the tract's own
# mix of request types (indirect standardization).
#
# For request type t, the threshold m_t is the citywide Kaplan-Meier median of
# business days to close over the window (open requests censored, D9). A
# request is "slow" if it was not closed within m_t business days. It is
# eligible only once its m_t-th business day has been fully observed, the same
# rule pipelines/311 uses for pct_within_target; eligibility depends on the
# open date alone, never on the outcome.

#' Requests counted by the 311 pipeline's timing metrics (deduplicated,
#' in-city, no close-date problem) opened in [from, to].
window_requests <- function(sr, from, to) {
  base <- sr[is.na(sr$exclusion) & is.na(sr$duplicate_of) & sr$in_city %in% TRUE &
               sr$open_date >= from & sr$open_date <= to, ]
  flow <- c(in_window = nrow(base), close_problem = sum(!is.na(base$close_problem)))
  d <- base[is.na(base$close_problem), ]
  d$time <- ifelse(d$closed, d$bd_to_close, d$age_bd)
  d <- d[!is.na(d$time), ]
  attr(d, "flow") <- flow
  d
}

#' Citywide threshold per request type: KM median business days to close.
type_thresholds <- function(d, min_n = 20L) {
  types <- sort(unique(d$request_type))
  rows <- lapply(types, function(t) {
    s <- d[d$request_type == t, ]
    r <- memequity::metric_censored_median(s$time, s$closed, min_n = min_n)
    data.frame(request_type = t, n = nrow(s), threshold = r$value,
               status = if (nrow(s) < min_n) "too_few" else if (is.na(r$value)) "median_not_reached" else "ok",
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

#' Flag each request slow / not slow and keep the eligible ones.
flag_slow <- function(d, thr) {
  ok <- thr[thr$status == "ok", ]
  d <- d[d$request_type %in% ok$request_type, ]
  d$threshold <- ok$threshold[match(d$request_type, ok$request_type)]
  d <- d[d$age_bd >= d$threshold, ]
  d$slow <- !(d$closed & d$bd_to_close <= d$threshold)
  p <- tapply(d$slow, d$request_type, mean)
  d$p_type <- as.numeric(p[d$request_type])
  d
}

#' Observed and expected slow requests per area, with the ratio and a 95%
#' interval (Wilson on the observed share, divided by the expected share,
#' which is fixed by the area's type mix).
area_ratios <- function(e, geo = "tract", min_n = 30L) {
  e <- e[!is.na(e[[geo]]), ]
  g <- e[[geo]]
  t <- data.frame(geo_id = sort(unique(g)), stringsAsFactors = FALSE)
  t$n <- as.integer(tapply(e$slow, g, length)[t$geo_id])
  t$observed <- as.numeric(tapply(e$slow, g, sum)[t$geo_id])
  t$expected <- as.numeric(tapply(e$p_type, g, sum)[t$geo_id])
  t$null_var <- as.numeric(tapply(e$p_type * (1 - e$p_type), g, sum)[t$geo_id])
  t$ratio <- t$observed / t$expected
  ci <- memequity::wilson_ci(t$observed, t$n)
  t$ci_low <- ci$ci_low / (t$expected / t$n)
  t$ci_high <- ci$ci_high / (t$expected / t$n)
  t$suppressed <- t$n < min_n
  t
}

#' How requests of one type were closed, by group: shares of resolution codes
#' among closed requests (codes below `min_share` in every group are pooled).
closure_codes <- function(d, groups, type, min_share = 0.05) {
  s <- d[d$request_type == type & d$closed, ]
  s$group <- groups[s$tract]
  s <- s[!is.na(s$group), ]
  code <- ifelse(is.na(s$resolution_code) | !nzchar(trimws(s$resolution_code)), "(no code)",
                 trimws(s$resolution_code))
  tab <- prop.table(table(code, s$group), 2)
  keep <- rownames(tab)[apply(tab, 1, max) >= min_share]
  code[!code %in% keep] <- "other codes"
  tab <- as.data.frame(prop.table(table(code, s$group), 2), stringsAsFactors = FALSE)
  names(tab) <- c("code", "group", "share")
  n <- table(s$group)
  tab$n_group <- as.integer(n[tab$group])
  tab
}

#' Per request type and group: observed/expected ratio and KM median days.
type_group_table <- function(d_all, e, group_of, types) {
  out <- list()
  for (ty in types) for (gname in unique(stats::na.omit(group_of))) {
    ids <- names(group_of)[group_of %in% gname]
    s <- e[e$request_type == ty & e$tract %in% ids, ]
    k <- d_all[d_all$request_type == ty & d_all$tract %in% ids, ]
    km <- memequity::metric_censored_median(k$time, k$closed, min_n = 20L)
    ci <- memequity::wilson_ci(sum(s$slow), nrow(s))
    pe <- mean(s$p_type)
    out[[length(out) + 1]] <- data.frame(
      request_type = ty, group = gname, n = nrow(s), ratio = mean(s$slow) / pe,
      ci_low = ci$ci_low / pe, ci_high = ci$ci_high / pe,
      median_days = km$value, median_n = km$n, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}
