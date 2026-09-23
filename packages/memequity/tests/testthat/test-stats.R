test_that("Wilson interval matches a hand-computed value", {
  ci <- wilson_ci(8, 10)
  expect_equal(ci$ci_low, 0.4902, tolerance = 1e-4)
  expect_equal(ci$ci_high, 0.9433, tolerance = 1e-4)
  ci0 <- wilson_ci(0, 30)
  expect_equal(ci0$ci_low, 0)
  expect_gt(ci0$ci_high, 0)
})

test_that("proportions below the minimum n are suppressed as NA, never zero", {
  r <- metric_proportion(c(TRUE, FALSE, TRUE), min_n = 30)
  expect_true(r$suppressed)
  expect_true(is.na(r$value))
  expect_true(is.na(r$ci_low))
  expect_equal(r$n, 3L)
  r0 <- metric_proportion(logical(), min_n = 30)
  expect_true(r0$suppressed)
  expect_equal(r0$n, 0L)
})

test_that("proportion drops NA and computes value with interval", {
  x <- c(rep(TRUE, 24), rep(FALSE, 6), NA, NA)
  r <- metric_proportion(x, min_n = 30)
  expect_false(r$suppressed)
  expect_equal(r$n, 30L)
  expect_equal(r$value, 0.8)
  expect_lt(r$ci_low, 0.8)
  expect_gt(r$ci_high, 0.8)
})

test_that("metrics are invariant to record order", {
  set.seed(42)
  x <- rexp(200)
  p <- runif(200) > 0.3
  perm <- sample(200)
  expect_equal(metric_median(x), metric_median(x[perm]))
  expect_equal(metric_proportion(p), metric_proportion(p[perm]))
  ev <- runif(200) > 0.2
  expect_equal(metric_censored_median(x, ev), metric_censored_median(x[perm], ev[perm]))
})

test_that("metrics do not change when duplicate records are added (given ids)", {
  set.seed(7)
  x <- rexp(50); id <- seq_along(x)
  dup <- c(x, x[1:10]); dup_id <- c(id, id[1:10])
  expect_equal(metric_median(dup, id = dup_id), metric_median(x, id = id))
  p <- runif(50) > 0.5
  expect_equal(metric_proportion(c(p, p[1:10]), id = dup_id), metric_proportion(p, id = id))
  ev <- rep(TRUE, 50)
  expect_equal(metric_censored_median(dup, c(ev, ev[1:10]), id = dup_id),
               metric_censored_median(x, ev, id = id))
})

test_that("bootstrap median interval is reproducible and brackets the median", {
  x <- c(1:40, 100, 200)
  a <- metric_median(x); b <- metric_median(x)
  expect_identical(a, b)
  expect_lte(a$ci_low, a$value)
  expect_gte(a$ci_high, a$value)
  expect_equal(a$value, median(x))
  expect_true(metric_median(1:19)$suppressed)
})

test_that("bootstrap leaves the caller's RNG state untouched", {
  set.seed(99); before <- runif(1)
  set.seed(99); invisible(metric_median(1:50)); after <- runif(1)
  expect_equal(before, after)
})

test_that("censored median equals the sample median with no censoring (odd n)", {
  x <- c(3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3, 2, 3, 8, 4, 6)
  r <- metric_censored_median(x, rep(TRUE, length(x)))
  expect_equal(r$value, median(x))
  expect_false(r$suppressed)
})

test_that("censored median is suppressed when the curve never reaches 0.5", {
  x <- 1:30
  ev <- c(rep(TRUE, 10), rep(FALSE, 20))
  expect_true(metric_censored_median(x, ev)$suppressed)
})

test_that("censoring pushes the median above the naive closed-only median", {
  closed <- c(1:20)
  open_so_far <- rep(25, 15)
  r <- metric_censored_median(c(closed, open_so_far), c(rep(TRUE, 20), rep(FALSE, 15)))
  expect_gt(r$value, median(closed))
})

test_that("Poisson rate intervals", {
  r <- poisson_rate_ci(0, 1)
  expect_equal(r$ci_low, 0)
  expect_equal(r$ci_high, 3.689, tolerance = 1e-3)
  m <- metric_rate(50, 10000, per = 1000)
  expect_equal(m$value, 5)
  expect_lt(m$ci_low, 5); expect_gt(m$ci_high, 5)
  expect_true(metric_rate(5, 0, per = 1000)$suppressed)
})

test_that("choose_window picks the smallest window that clears min n", {
  end <- as.Date("2026-09-01")
  busy <- end - rep(0:89, each = 2)
  quiet <- end - seq(0, 360, by = 12)
  expect_equal(choose_window(busy, end, 30), 90L)
  expect_equal(choose_window(quiet, end, 25), 365L)
  expect_true(is.na(choose_window(end - 1:5, end, 30)))
  # A record exactly `window` days before the end is outside the window.
  expect_equal(choose_window(end - c(rep(0, 29), 90), end, 30, windows = 90), NA_integer_)
})

test_that("interval comparison never over-claims", {
  expect_equal(compare_intervals(0.5, 0.7, 0.6, 0.8), "not clearly different")
  expect_equal(compare_intervals(0.8, 0.9, 0.5, 0.7), "higher")
  expect_equal(compare_intervals(0.1, 0.2, 0.5, 0.7), "lower")
  expect_equal(compare_intervals(NA, 0.2, 0.5, 0.7), "insufficient data")
})
