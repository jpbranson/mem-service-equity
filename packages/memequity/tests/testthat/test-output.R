rows <- function() data.frame(
  geo_type = c("zcta", "zcta", "citywide"), geo_id = c("38103", "38104", "memphis"),
  metric = "pct_on_time", value = c(0.8, 0.5, 0.7), ci_low = c(0.7, 0.3, 0.65),
  ci_high = c(0.9, 0.7, 0.75), n = c(100L, 5L, 1000L), suppressed = c(FALSE, TRUE, FALSE),
  window_start = as.Date("2026-06-01"), window_end = as.Date("2026-08-30"),
  citywide_median = 0.7)

test_that("as_metrics_table produces the exact schema and blanks suppressed values", {
  m <- as_metrics_table(rows(), "1.0", as.Date("2026-08-30"))
  expect_identical(names(m), METRICS_COLUMNS)
  expect_true(is.na(m$value[2]))
  expect_true(is.na(m$ci_low[2]))
  expect_equal(m$variant, rep("primary", 3))
  expect_length(metrics_problems(m), 0)
})

test_that("metrics_problems catches contract violations", {
  m <- as_metrics_table(rows(), "1.0", as.Date("2026-08-30"))
  bad <- m; bad$value[2] <- 0.5
  expect_match(metrics_problems(bad), "suppressed rows carry a value")
  bad <- m; bad$ci_low[1] <- NA
  expect_match(metrics_problems(bad), "missing value or interval")
  bad <- m; bad$ci_high[1] <- 0.75
  expect_match(metrics_problems(bad), "outside its interval")
  bad <- rbind(m, m[1, ])
  expect_match(metrics_problems(bad), "duplicate")
  bad <- m; bad$geo_type[1] <- "planet"
  expect_match(metrics_problems(bad), "unknown geo_type")
  expect_match(metrics_problems(m[, 1:5]), "columns must be exactly")
})

test_that("write_metrics writes the standard file name and round-trips", {
  d <- withr::local_tempdir()
  m <- as_metrics_table(rows(), "1.0", as.Date("2026-08-30"))
  path <- write_metrics(m, "demo", "zcta", d)
  expect_equal(basename(path), "metrics_demo_by_zcta.csv")
  back <- read.csv(path, stringsAsFactors = FALSE)
  expect_identical(names(back), METRICS_COLUMNS)
  expect_equal(back$suppressed, c(FALSE, TRUE, FALSE))
  bad <- m; bad$value[2] <- 1
  expect_error(write_metrics(bad, "demo", "zcta", d), "invalid")
})

test_that("write_points requires match quality and drops unlocated points", {
  d <- withr::local_tempdir()
  p <- points_from_lonlat(data.frame(id = 1:2, longitude = c(-90.05, NA), latitude = c(35.14, NA)))
  expect_error(write_points(p, "demo", d, "id"), "match_quality")
  p$match_quality <- c("exact", "no_match")
  path <- write_points(p, "demo", d, "id")
  back <- sf::st_read(path, quiet = TRUE)
  expect_equal(nrow(back), 1)
})
