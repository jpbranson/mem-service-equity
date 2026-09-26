# Layer 3 tests for the permits pipeline (plan 5.3): hand-built fixtures
# with known answers, property tests, and golden files.

test_that("data run through the end of the month before the last data edit", {
  expect_equal(permits_through(as.POSIXct("2026-09-01 14:16:20", tz = "UTC"), as.Date("2026-09-25")),
               as.Date("2026-08-31"))
  expect_equal(permits_through(as.POSIXct("2026-09-15 12:00:00", tz = "UTC"), as.Date("2026-09-25")),
               as.Date("2026-08-31"))
  # 03:00 UTC on October 1 is still September 30 in Memphis.
  expect_equal(permits_through(as.POSIXct("2026-10-01 03:00:00", tz = "UTC"), as.Date("2026-10-05")),
               as.Date("2026-08-31"))
  # Never past the day before the run.
  expect_equal(permits_through(as.POSIXct("2026-10-02 12:00:00", tz = "UTC"), as.Date("2026-09-20")),
               as.Date("2026-09-19"))
})

test_that("windows are whole years ending on the data-through date", {
  expect_equal(window_start_years(as.Date("2026-08-31"), 1), as.Date("2025-09-01"))
  expect_equal(window_start_years(as.Date("2026-08-31"), 5), as.Date("2021-09-01"))
  expect_equal(window_start_years(as.Date("2024-02-29"), 1), as.Date("2023-03-01"))
})

test_that("both codings map, and exclusions and bad locations are flagged", {
  raw <- rbind(
    make_permits(sub_type = "RES", construction_type = "NEW"),
    make_permits(sub_type = "Residential", construction_type = "New"),
    make_permits(sub_type = "COM", construction_type = "ALT"),
    make_permits(sub_type = "Commercial", construction_type = "Addition"),
    make_permits(sub_type = "RES", construction_type = "ACC", value = 0),
    make_permits(construction_type = "DEMO"),                  # not mapped
    make_permits(issued = "2026-09-02"),                       # after the data-through date
    make_permits(lon = 0, lat = 0))                            # placeholder location
  raw$Record_ID <- sprintf("X%d", seq_len(nrow(raw)))
  p <- normalize_permits(raw, cfg, as.Date("2026-08-31"))
  expect_equal(p$sector[1:5], c("residential", "residential", "commercial", "commercial", "residential"))
  expect_equal(p$category[1:5], c("new", "new", "renovation", "renovation", "accessory"))
  expect_true(is.na(p$value[5]))                               # a zero value is no declared value
  expect_equal(p$exclusion[6:7], c("unmapped_type", "after_data_through"))
  expect_true(all(is.na(p$exclusion[c(1:5, 8)])))
  expect_equal(p$match_quality[8], "out_of_area")
  expect_true(is.na(p$longitude[8]))
})

test_that("subgroups nest: each category by sector, pooled, and all", {
  df <- data.frame(category = c("new", "new", "renovation", "accessory"),
                   sector = c("residential", "commercial", "residential", "commercial"))
  s <- subgroup_masks(df)
  expect_setequal(names(s), c(outer(c("new", "renovation", "accessory", "all"),
                                    c("_residential", "_commercial", ""), paste0)))
  expect_equal(which(s$new), 1:2)
  expect_equal(which(s$all_residential), c(1L, 3L))
  expect_equal(which(s$accessory_commercial), 4L)
  expect_true(all(s$all))
})

test_that("permit rates: known counts, zeros, the parcel floor and the citywide reference", {
  through <- as.Date("2026-08-31")
  raw <- rbind(
    make_permits(3, issued = "2026-06-01", east_m = c(0, 100, 200)),               # new residential
    make_permits(1, construction_type = "ALT", issued = "2026-07-01", value = 3000), # minor renovation
    make_permits(1, issued = "2023-01-15"))                                          # 5-year window only
  raw$Record_ID <- sprintf("P%d", seq_len(nrow(raw)))
  pts <- permit_points(raw, through)
  expect_true(all(pts$zcta == "38103"))
  m <- compute_metrics_permits(pts, fake_parcels(), through)
  r <- get_row(m, "permits_per_1000_parcels", "zcta", "38103", "new_residential")
  expect_equal(r$n, 3L)
  expect_equal(r$value, 3 / 2000 * 1000)
  expect_equal(r$ci_low, qchisq(0.025, 6) / 2 / 2000 * 1000)
  expect_equal(r$ci_high, qchisq(0.975, 8) / 2 / 2000 * 1000)
  expect_equal(r$citywide_median, 3 / 10000 * 1000)
  expect_equal(get_row(m, "permits_per_1000_parcels", "zcta", "38103", "new_residential", years = 5)$n, 4L)
  expect_equal(get_row(m, "permits_per_1000_parcels", "zcta", "38103", "all")$n, 4L)
  # excl_minor drops the $3,000 renovation.
  expect_equal(get_row(m, "permits_per_1000_parcels", "zcta", "38103", "all", "excl_minor")$n, 3L)
  # 38105 has too few parcels: suppressed, with its count.
  z <- get_row(m, "permits_per_1000_parcels", "zcta", "38105", "all")
  expect_true(z$suppressed)
  expect_equal(z$n, 0L)
  # A zero in an area above the floor is a result, not a gap.
  zc <- get_row(m, "permits_per_1000_parcels", "zcta", "38103", "new_commercial")
  expect_false(zc$suppressed)
  expect_equal(c(zc$n, zc$value, zc$ci_low), c(0, 0, 0))
  expect_gt(zc$ci_high, 0)
})

test_that("declared value: totals, the 20-permit floor, the variants and the median", {
  through <- as.Date("2026-08-31")
  vals <- c(rep(10000, 24), 5e7)                                 # 25 permits, one very large
  big <- make_permits(25, issued = "2026-05-01", value = vals, east_m = seq(0, by = 5, length.out = 25))
  few <- make_permits(5, sub_type = "COM", issued = "2026-05-01", value = 1000, east_m = 30)
  raw <- rbind(big, few)
  raw$Record_ID <- sprintf("V%d", seq_len(nrow(raw)))
  pts <- permit_points(raw, through)
  expect_true(all(pts$zcta == "38103"))
  m <- compute_metrics_permits(pts, fake_parcels(), through)
  r <- get_row(m, "declared_value_per_1000_parcels", "zcta", "38103", "new_residential")
  expect_equal(r$n, 25L)
  expect_equal(r$value, sum(vals) / 2000 * 1000)
  expect_lte(r$ci_low, r$value)
  expect_gte(r$ci_high, r$value)
  cap <- get_row(m, "declared_value_per_1000_parcels", "zcta", "38103", "new_residential", "cap_10m")
  expect_equal(cap$value, (24 * 10000 + 1e7) / 2000 * 1000)
  # The $50M permit is above the citywide 99th percentile of the window.
  top <- get_row(m, "declared_value_per_1000_parcels", "zcta", "38103", "new_residential", "excl_top1pct")
  expect_equal(top$value, 24 * 10000 / 2000 * 1000)
  med <- get_row(m, "declared_value_per_1000_parcels", "zcta", "38103", "new_residential", "median_per_permit")
  expect_equal(med$value, 10000)
  # Five commercial permits: too few for the value metric, still counted as permits.
  expect_true(get_row(m, "declared_value_per_1000_parcels", "zcta", "38103", "new_commercial")$suppressed)
  expect_equal(get_row(m, "permits_per_1000_parcels", "zcta", "38103", "new_commercial")$n, 5L)
})

test_that("metrics do not depend on input order", {
  set.seed(4)
  n <- 60
  raw <- make_permits(n, sub_type = sample(c("RES", "COM"), n, TRUE),
                      construction_type = sample(c("NEW", "ALT", "ACC"), n, TRUE),
                      issued = format(as.Date("2025-01-01") + sample(0:600, n, TRUE)),
                      value = round(rlnorm(n, 11, 1.5)), east_m = seq(0, by = 25, length.out = n))
  raw$Record_ID <- sprintf("O%d", seq_len(n))
  through <- as.Date("2026-08-31")
  a <- compute_metrics_permits(permit_points(raw, through), fake_parcels(), through)
  b <- compute_metrics_permits(permit_points(raw[sample(n), ], through), fake_parcels(), through)
  key <- function(m) m[order(m$metric, m$variant, m$subgroup, m$geo_type, m$geo_id, m$window_start),
                       c("metric", "variant", "subgroup", "geo_id", "value", "ci_low", "ci_high", "n")]
  expect_equal(key(a), key(b), ignore_attr = TRUE)
})

test_that("reconciliation counts new residential permits in the whole jurisdiction by year", {
  raw <- rbind(
    make_permits(2, issued = c("2025-01-01", "2025-12-31")),
    make_permits(1, sub_type = "Residential", construction_type = "New", issued = "2025-06-01",
                 lon = 0, lat = 0),                                 # unlocated still counts
    make_permits(1, sub_type = "COM", issued = "2025-06-01"),        # commercial
    make_permits(1, construction_type = "ALT", issued = "2025-06-01"),
    make_permits(1, issued = "2026-01-01"))                          # next year
  raw$Record_ID <- sprintf("R%d", seq_len(nrow(raw)))
  path <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(
    figure_id = "bps_2025", measure = "census_bps_new_residential", subgroup = "",
    period_start = "2025-01-01", period_end = "2025-12-31", value = "3", precision = "1",
    definition = "d", source_title = "t", source_url = "https://www2.census.gov/x", source_page = "",
    published = "", transcribed = "", gap_note = ""), path, row.names = FALSE)
  r <- reconcile_permits(raw, cfg, path, as.Date("2026-09-25"))
  expect_equal(r$our_value, 3)
  expect_true(r$within_tolerance)
})

test_that("SPEC_VERSIONS matches the version in each spec", {
  specs <- memequity::read_specs("permits", file.path(repo_root, "specs"))
  for (id in names(SPEC_VERSIONS))
    expect_identical(as.character(specs[[id]]$version), SPEC_VERSIONS[[id]], info = id)
})

test_that("golden file: a frozen sample of real data reproduces the frozen outputs", {
  gd <- file.path(repo_root, "pipelines", "permits", "tests", "golden")
  skip_if_not(file.exists(file.path(gd, "golden_metrics.csv")), "golden files not built")
  raw <- readRDS(file.path(gd, "golden_raw.rds"))
  parcels <- golden_parcels(gd)
  through <- as.Date(readLines(file.path(gd, "golden_through.txt")))
  m <- golden_order(compute_metrics_permits(permit_points(raw, through), parcels, through))
  want <- utils::read.csv(file.path(gd, "golden_metrics.csv"), stringsAsFactors = FALSE,
                          colClasses = c(geo_id = "character"))
  expect_equal(nrow(m), nrow(want))
  expect_equal(m$n, want$n)
  expect_equal(m$value, want$value, tolerance = 1e-9)
  expect_equal(m$ci_low, want$ci_low, tolerance = 1e-9)
  expect_equal(m$ci_high, want$ci_high, tolerance = 1e-9)
})
