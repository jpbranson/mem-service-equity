# Layer 3 tests for the 311 pipeline (plan 5.3): hand-built fixtures with
# known answers, property tests, and golden files.

test_that("normalization flags close-date problems, exclusions and bad locations", {
  raw <- rbind(
    make_raw(status = "closed", created = "2026-06-01 14:00", closed = "2026-06-01 00:00"), # same local day
    make_raw(status = "Closed", closed = NA),                                             # missing close
    make_raw(status = "Closed", closed = "0001-01-01 00:00"),                             # sentinel
    make_raw(status = "Closed", created = "2026-06-05 10:00", closed = "2026-06-02 00:00"), # before open
    make_raw(status = "Open", closed = NA, sysrev = "DUPLICATE"),                         # city duplicate
    make_raw(status = "Open", created = "2026-09-23 08:00", closed = NA),                 # partial day
    make_raw(status = "Open", closed = NA, lon = -168),                                   # bad coordinates
    make_raw(status = "", closed = NA))                                                   # blank status
  raw$INCIDENT_NUMBER <- sprintf("N%d", seq_len(nrow(raw)))
  sr <- normalize_311(raw, cfg, as.Date("2026-09-23"))
  expect_equal(sr$state[1], "closed")
  expect_true(sr$closed[1])
  expect_equal(sr$bd_to_close[1], 0L)
  expect_equal(sr$close_problem[2:4], c("missing_close_date", "sentinel_close_date", "close_before_open"))
  expect_false(any(sr$closed[2:4]))
  expect_equal(sr$exclusion[5:6], c("city_duplicate", "partial_day"))
  expect_equal(sr$match_quality[7], "out_of_area")
  expect_true(is.na(sr$longitude[7]))
  expect_equal(sr$exclusion[8], "unknown_status")
})

test_that("business days follow the city calendar across Labor Day", {
  raw <- make_raw(created = "2026-09-04 09:00", closed = "2026-09-08 16:00")
  sr <- normalize_311(raw, cfg, as.Date("2026-09-23"))
  expect_equal(sr$bd_to_close, 1L)   # Fri -> Tue with Mon 7 Sep a holiday
})

test_that("share within target counts late, open-past-deadline and ineligible requests correctly", {
  # 40 potholes opened Mon 2026-06-01, spread 200 m apart so none are near-duplicates.
  on_time <- make_raw(30, created = "2026-06-01 10:00", closed = "2026-06-12 00:00",
                      east_m = seq(0, by = 200, length.out = 30))            # 9 business days
  late <- make_raw(10, created = "2026-06-01 10:00", closed = "2026-06-17 00:00",
                   east_m = seq(6000, by = 200, length.out = 10))            # 12 business days
  open_late <- make_raw(1, status = "Open", created = "2026-06-01 10:00", closed = NA, east_m = 9000)
  too_new <- make_raw(1, status = "Open", created = "2026-09-18 10:00", closed = NA, east_m = 9400)
  raw <- rbind(on_time, late, open_late, too_new)
  raw$INCIDENT_NUMBER <- sprintf("P%03d", seq_len(nrow(raw)))
  pts <- pipeline_points(raw, "2026-09-23")
  expect_true(all(is.na(pts$duplicate_of)))
  m <- compute_metrics_311(pts, cfg$request_types, as.Date("2026-09-22"))$metrics
  r <- citywide(m, "pct_within_target", window_days = 365)
  expect_equal(r$n, 41L)                 # too_new is not yet eligible
  expect_equal(r$value, 30 / 41)
  low <- citywide(m, "pct_within_target", "lower_bound", 365)
  expect_equal(low$value, 0)             # nothing closed within 5 business days
})

test_that("the censored median matches a direct Kaplan-Meier fit", {
  set.seed(3)
  n <- 60
  days <- sample(0:15, n, TRUE)
  open <- runif(n) < 0.2
  created <- rep("2026-08-03 10:00", n)                       # a Monday
  closed_dates <- as.Date("2026-08-03") + days
  raw <- make_raw(n, status = ifelse(open, "Open", "Closed"), created = created,
                  closed = ifelse(open, NA, paste(format(closed_dates), "00:00")),
                  east_m = seq(0, by = 150, length.out = n))
  pts <- pipeline_points(raw, "2026-09-23")
  m <- compute_metrics_311(pts, cfg$request_types, as.Date("2026-09-22"))$metrics
  r <- citywide(m, "median_business_days_to_close")
  df <- sf::st_drop_geometry(pts)
  ref <- memequity::metric_censored_median(ifelse(df$closed, df$bd_to_close, df$age_bd), df$closed)
  expect_equal(r$value, ref$value)
  expect_equal(r$ci_low, ref$ci_low)
  expect_equal(r$n, n)
})

test_that("re-reports are detected per radius and window variant", {
  # 30 base potholes far apart, closed 2026-06-10; three of them get a new
  # request nearby after closing.
  base <- make_raw(30, created = "2026-06-01 10:00", closed = "2026-06-10 00:00",
                   east_m = seq(0, by = 500, length.out = 30))
  near_10d <- make_raw(1, created = "2026-06-20 10:00", closed = "2026-06-22 00:00", east_m = 0 + 30)
  mid_10d <- make_raw(1, created = "2026-06-20 10:00", closed = "2026-06-22 00:00", east_m = 500 + 80)
  near_45d <- make_raw(1, created = "2026-07-25 10:00", closed = "2026-07-27 00:00", east_m = 1000 + 20)
  raw <- rbind(base, near_10d, mid_10d, near_45d)
  raw$INCIDENT_NUMBER <- sprintf("R%03d", seq_len(nrow(raw)))
  pts <- pipeline_points(raw, "2026-09-23")
  m <- compute_metrics_311(pts, cfg$request_types, as.Date("2026-09-22"))$metrics
  get <- function(v) {
    r <- citywide(m, "reopen_rate", v, 365)
    r$value * r$n
  }
  # Base requests closed 2026-06-10; the re-report requests themselves also
  # count as closed requests in the window, with no re-reports of their own.
  expect_equal(get("primary"), 1)      # 30 m, 10 days
  expect_equal(get("radius_100m"), 2)  # + 80 m
  expect_equal(get("window_60d"), 2)   # + 45 days
  expect_equal(get("window_14d"), 1)
  expect_equal(get("radius_25m"), 0)
})

test_that("metrics are invariant to input order and to added near-duplicates", {
  set.seed(8)
  n <- 80
  raw <- make_raw(n, created = paste(format(as.Date("2026-07-01") + sample(0:30, n, TRUE)), "10:00"),
                  closed = NA, status = "Open", east_m = seq(0, by = 150, length.out = n))
  cl <- runif(n) < 0.8
  raw$REQUEST_STATUS[cl] <- "Closed"
  raw$Closed_Date[cl] <- raw$created_date[cl] + sample(1:20, sum(cl), TRUE) * 86400
  a <- compute_metrics_311(pipeline_points(raw, "2026-09-23"), cfg$request_types, as.Date("2026-09-22"))$metrics
  b <- compute_metrics_311(pipeline_points(raw[sample(n), ], "2026-09-23"), cfg$request_types,
                           as.Date("2026-09-22"))$metrics
  key <- function(m) m[order(m$metric, m$variant, m$geo_type, m$geo_id, m$window_start),
                       c("metric", "variant", "geo_type", "geo_id", "value", "ci_low", "ci_high", "n")]
  expect_equal(key(a), key(b), ignore_attr = TRUE)
  # Duplicates: same type, 10 m away, filed 2 days after an original.
  dup <- raw[1:15, ]
  dup$INCIDENT_NUMBER <- paste0(dup$INCIDENT_NUMBER, "d")
  dup$created_date <- dup$created_date + 2 * 86400
  dup$latitude <- dup$latitude + 10 / M_PER_DEG_LAT  # 10 m north
  c2 <- compute_metrics_311(pipeline_points(rbind(raw, dup), "2026-09-23"), cfg$request_types,
                            as.Date("2026-09-22"))$metrics
  keep <- function(m) key(m[m$metric != "reopen_rate", ])
  expect_equal(keep(a), keep(c2), ignore_attr = TRUE)
})

test_that("golden file: a frozen sample of real data reproduces the frozen outputs", {
  gold_in <- file.path(repo_root, "pipelines", "311", "tests", "golden", "golden_raw.rds")
  gold_out <- file.path(repo_root, "pipelines", "311", "tests", "golden", "golden_metrics.csv")
  skip_if_not(file.exists(gold_in) && file.exists(gold_out), "golden files not built")
  raw <- readRDS(gold_in)
  pts <- pipeline_points(raw, "2025-07-01")
  m <- compute_metrics_311(pts, cfg$request_types, as.Date("2025-06-30"))$metrics
  m <- m[order(m$metric, m$variant, m$subgroup, m$geo_type, m$geo_id, m$window_start),
         c("metric", "variant", "subgroup", "geo_type", "geo_id", "window_start", "value",
           "ci_low", "ci_high", "n", "suppressed")]
  m$window_start <- format(as.Date(m$window_start))
  want <- utils::read.csv(gold_out, stringsAsFactors = FALSE, colClasses = c(geo_id = "character"))
  rownames(m) <- NULL
  expect_equal(nrow(m), nrow(want))
  expect_equal(m$n, want$n)
  expect_equal(m$value, want$value, tolerance = 1e-9)
  expect_equal(m$ci_low, want$ci_low, tolerance = 1e-9)
  expect_equal(m$ci_high, want$ci_high, tolerance = 1e-9)
})

test_that("SPEC_VERSIONS matches the version in each spec", {
  specs <- memequity::read_specs("311", file.path(repo_root, "specs"))
  for (id in names(SPEC_VERSIONS))
    expect_identical(as.character(specs[[id]]$version), SPEC_VERSIONS[[id]], info = id)
})

official_file <- function(rows) {
  path <- tempfile(fileext = ".csv")
  base <- data.frame(figure_id = "f", measure = "requests_created", subgroup = "",
                     period_start = "2026-06-01", period_end = "2026-06-30", value = "0",
                     precision = "1", definition = "requests created", source_title = "Test",
                     source_url = "https://memphistn.gov/test", source_page = "", published = "2026-07-01",
                     transcribed = "2026-09-25", gap_note = "", stringsAsFactors = FALSE)
  out <- base[rep(1, nrow(rows)), ]
  for (col in names(rows)) out[[col]] <- rows[[col]]
  utils::write.csv(out, path, row.names = FALSE)
  path
}

test_that("reconciliation recomputes official counts by local date, type and category", {
  raw <- rbind(
    make_raw(created = "2026-05-31 23:30"),                                   # May, local
    make_raw(created = "2026-06-01 00:30"),                                   # June, local
    make_raw(created = "2026-06-30 23:59", type = "EE-Illegal Dumping"),
    make_raw(created = "2026-06-15 10:00", type = "SWM-Garbage Missed", sysrev = "DUPLICATE"),
    make_raw(created = "2026-07-01 00:01"))                                   # July
  path <- official_file(data.frame(
    figure_id = c("all", "potholes", "two_types", "swm"),
    subgroup = c("", "PW (SM)-Potholes", "PW (SM)-Potholes|EE-Illegal Dumping", "category:SWM"),
    value = c("3", "1", "2", "2")))
  r <- reconcile_311(raw, cfg, path, as.Date("2026-09-25"))
  expect_equal(r$our_value, c(3, 1, 2, 1))          # duplicates count: the City counts records
  expect_equal(r$documented, c(TRUE, TRUE, TRUE, FALSE))
  expect_null(reconcile_311(raw, cfg, tempfile(), as.Date("2026-09-25")))
})

test_that("reconciliation refuses figures from before the 2023 migration", {
  path <- official_file(data.frame(figure_id = "fy24", period_start = "2023-07-01",
                                   period_end = "2024-06-30"))
  expect_error(reconcile_311(make_raw(), cfg, path, as.Date("2026-09-25")), "migration")
  bad <- official_file(data.frame(figure_id = "x", measure = "calls_answered"))
  expect_error(reconcile_311(make_raw(), cfg, bad, as.Date("2026-09-25")), "calls_answered")
})

test_that("requests per 1,000 residents: known counts, zeros and the population floor", {
  through <- as.Date("2026-06-30")
  df <- data.frame(
    request_type = c("PW (SM)-Potholes", "PW (SM)-Potholes", "PW (SM)-Potholes", "EE-Illegal Dumping",
                     "PW (SM)-Potholes"),
    open_date = through - c(1, 10, 40, 5, 200),
    citywide = "4748000", zcta = c("38103", "38103", "38103", "38104", "38103"))
  pops <- list(citywide = data.frame(geo_id = "4748000", population = 10000),
               zcta = data.frame(geo_id = c("38103", "38104", "38131"), population = c(2000, 3000, 14)))
  m <- compute_requests_per_1000(df, pops, through)
  get <- function(g, id, type, days) {
    r <- m[m$geo_type == g & m$geo_id == id & m$subgroup == type &
             as.integer(m$window_end - m$window_start) + 1L == days, ]
    stopifnot(nrow(r) == 1)
    r
  }
  r <- get("zcta", "38103", "PW (SM)-Potholes", 90)
  expect_equal(r$n, 3L)
  expect_equal(r$value, 1.5)
  expect_equal(r$ci_low, qchisq(0.025, 6) / 2 / 2000 * 1000)
  expect_equal(r$ci_high, qchisq(0.975, 8) / 2 / 2000 * 1000)
  expect_equal(r$citywide_median, 0.3)  # 3 per 10,000 residents
  # The request 200 days ago counts only in the 12-month window.
  expect_equal(get("zcta", "38103", "PW (SM)-Potholes", 365)$n, 4L)
  # No potholes in 38104: a zero is a result, with an upper bound.
  z <- get("zcta", "38104", "PW (SM)-Potholes", 90)
  expect_equal(c(z$n, z$value, z$ci_low), c(0, 0, 0))
  expect_gt(z$ci_high, 0)
  # Fewer than 1,000 residents inside the city: suppressed, with its count.
  s <- get("zcta", "38131", "PW (SM)-Potholes", 90)
  expect_true(s$suppressed)
  expect_true(is.na(s$value))
  expect_equal(unique(m$metric_version), SPEC_VERSIONS[["requests_per_1000"]])
})
