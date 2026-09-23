contract <- list(
  columns = list(
    id = list(type = "character", nullable = FALSE),
    status = list(type = "character", allowed = c("Open", "Closed")),
    opened = list(type = "datetime"),
    optional_col = list(type = "numeric", required = FALSE)
  ),
  allow_extra_columns = FALSE
)

good_df <- function() data.frame(id = c("1", "2"), status = c("Open", "Closed"),
                                 opened = c("2026-09-01T10:00:00", "2026-09-02T11:00:00"))

test_that("a conforming frame passes the schema contract", {
  r <- finalize_report(check_schema(validation_report("t"), good_df(), contract))
  expect_equal(r$status, "pass")
})

test_that("a new category value fails the run until mapped", {
  df <- good_df(); df$status[2] <- "Pending Review"
  r <- finalize_report(check_schema(validation_report("t"), df, contract))
  expect_equal(r$status, "fail")
  expect_match(unlist(failed_checks(r)), "allowed values: status")
  expect_error(stop_if_failed(r), "Validation failed")
})

test_that("missing required columns, wrong types and nulls fail", {
  df <- good_df(); df$status <- NULL
  expect_equal(finalize_report(check_schema(validation_report("t"), df, contract))$status, "fail")
  df <- good_df(); df$opened <- c("yesterday", "today")
  expect_equal(finalize_report(check_schema(validation_report("t"), df, contract))$status, "fail")
  df <- good_df(); df$id[1] <- NA
  expect_equal(finalize_report(check_schema(validation_report("t"), df, contract))$status, "fail")
})

test_that("unexpected extra columns warn but do not halt", {
  df <- good_df(); df$surprise <- 1
  r <- finalize_report(check_schema(validation_report("t"), df, contract))
  expect_equal(r$status, "pass")
  expect_false(all(vapply(r$checks, `[[`, logical(1), "passed")))
})

test_that("freshness uses local dates and the stated lag", {
  r <- check_freshness(validation_report("t"), c("2026-09-20T12:00:00", "2026-09-10T00:00:00"),
                       max_lag_days = 3, as_of = as.Date("2026-09-23"))
  expect_equal(finalize_report(r)$status, "pass")
  expect_equal(r$freshness$data_current_through, "2026-09-20")
  r2 <- check_freshness(validation_report("t"), "2026-09-01T00:00:00", 3, as.Date("2026-09-23"))
  expect_equal(finalize_report(r2)$status, "fail")
})

volume_ts <- function(as_of, weekday_n, weekend_n, last_day_n = NULL) {
  days <- seq(as_of - 61, as_of - 1, by = "day")
  n <- ifelse(as.integer(format(days, "%u")) >= 6, weekend_n, weekday_n)
  if (!is.null(last_day_n)) n[length(n)] <- last_day_n
  as.POSIXct(paste(rep(days, n), "12:00:00"), tz = "America/Chicago")
}

test_that("volume band passes normal days and catches a collapse", {
  as_of <- as.Date("2026-09-23") # a Wednesday; checks Tuesday 22nd
  ok <- check_volume(validation_report("t"), volume_ts(as_of, 100, 20), as_of)
  expect_equal(finalize_report(ok)$status, "pass")
  bad <- check_volume(validation_report("t"), volume_ts(as_of, 100, 20, last_day_n = 3), as_of)
  expect_equal(finalize_report(bad)$status, "fail")
})

test_that("weekend lows are not flagged when bands are split by day type", {
  as_of <- as.Date("2026-09-21") # Monday; checks Sunday 20th
  r <- check_volume(validation_report("t"), volume_ts(as_of, 100, 20), as_of)
  expect_equal(finalize_report(r)$status, "pass")
  r2 <- check_volume(validation_report("t"), volume_ts(as_of, 100, 20), as_of, by_day_type = FALSE)
  expect_equal(finalize_report(r2)$status, "fail")
})

test_that("near-duplicate rule: same type, 50 m, 7 days after a primary", {
  base <- as.POSIXct("2026-09-01 09:00:00", tz = "America/Chicago")
  df <- data.frame(
    id = 1:6,
    type = c("pothole", "pothole", "pothole", "streetlight", "pothole", "pothole"),
    # ~0.0003 deg lat = 33 m; 0.002 deg = 222 m.
    latitude = c(35.1400, 35.1403, 35.1400, 35.1400, 35.1420, 35.1401),
    longitude = -90.05,
    t = base + c(0, 3, 10, 1, 2, 12) * 86400)
  p <- points_from_lonlat(df)
  d <- near_duplicates(p, p$type, p$t, meters = 50, days = 7)
  # 2 duplicates 1 (33 m, 3 days). 3 is 10 days after 1: new primary.
  # 4 is another type. 5 is 222 m away. 6 is 2 days after primary 3.
  expect_equal(d, c(NA, 1L, NA, NA, NA, 3L))
})

test_that("near-duplicate detection is independent of input order", {
  base <- as.POSIXct("2026-09-01 09:00:00", tz = "America/Chicago")
  df <- data.frame(id = 1:4, type = "pothole", latitude = c(35.14, 35.1401, 35.1402, 35.20),
                   longitude = -90.05, t = base + c(0, 1, 2, 3) * 86400)
  p <- points_from_lonlat(df)
  d1 <- near_duplicates(p, p$type, p$t)
  perm <- c(3, 1, 4, 2)
  d2 <- near_duplicates(p[perm, ], p$type[perm], p$t[perm])
  primary_ids_1 <- sort(p$id[is.na(d1)])
  primary_ids_2 <- sort(p$id[perm][is.na(d2)])
  expect_equal(primary_ids_1, primary_ids_2)
})

test_that("geocoding, referential, uniqueness and min-row checks", {
  r <- validation_report("t")
  r <- check_geocoding(r, c(rep("exact", 95), rep("no_match", 5)), max_unlocated_share = 0.1)
  expect_equal(r$geocoding$unlocated, 5)
  r <- check_referential(r, c("r1", "r2"), c("r1", "r2", "r3"), "routes known")
  r <- check_unique(r, c("a", "b"))
  r <- check_min_rows(r, data.frame(x = 1:10), 5)
  expect_equal(finalize_report(r)$status, "pass")
  expect_equal(finalize_report(check_referential(r, "r9", "r1", "routes"))$status, "fail")
  expect_equal(finalize_report(check_unique(r, c("a", "a")))$status, "fail")
})

test_that("the report is written as JSON even when the run fails", {
  d <- withr::local_tempdir()
  df <- good_df(); df$status[1] <- "Weird"
  r <- check_schema(validation_report("demo", as.Date("2026-09-23")), df, contract)
  path <- write_validation_report(r, d)
  expect_equal(basename(path), "validation_demo_2026-09-23.json")
  j <- jsonlite::read_json(path)
  expect_equal(j$status, "fail")
  expect_equal(j$pipeline, "demo")
})
