# Layer 3 tests for the MATA pipeline (plan 5.3) on a synthetic route with
# known answers. Golden files come once a month of well-covered data exists
# (DECISIONS.md H22).

# The scenario, all on 2026-09-24 (Thursday), poller up 07:30-11:00:
#   T1 08:00 block B1  observed (vehicle V1), passes 2500 m at 08:11:00, 5000 m at 08:21:30
#   T2 09:00 block B1  not reported, but B1 was seen on T1  -> ghost
#   T3 08:30 block B2  observed (V2), passes 2500 m at 08:46:00 (6 min late)
#   T4 10:00 block B3  not reported, nothing from B3 all day -> unobserved
#   T5 12:00 block B4  outside the poller's coverage          -> not measurable
scenario <- function() {
  dir <- tempfile("mata_archive_"); dir.create(dir)
  write_gtfs(dir, data.frame(trip_id = c("T1", "T2", "T3", "T4", "T5"),
                             block_id = c("B1", "B1", "B2", "B3", "B4"),
                             start = c("08:00:00", "09:00:00", "08:30:00", "10:00:00", "12:00:00")))
  v1 <- pings("V1", "T1", "08:11:00", 2500 / 630, "07:58:00", "08:23:00")   # 2500 -> 5000 m in 630 s
  v2 <- pings("V2", "T3", "08:46:00", 2500 / 960, "08:28:00", "09:05:00")
  write_jsonl_gz(rbind(v1, v2), file.path(dir, "mata_positions_run1.jsonl.gz"))
  # An overlapping run repeats some reports (D15).
  write_jsonl_gz(v1[1:10], file.path(dir, "mata_positions_run2.jsonl.gz"))
  write_polls(dir, "07:30:00", "11:00:00")
  dir
}

test_that("reports are deduplicated across runs and dated in local time", {
  dir <- scenario()
  p <- read_positions(dir)
  expect_equal(nrow(p), uniqueN(p, by = c("vehicle", "timestamp")))
  expect_equal(unique(p$service_date), as.Date(DATE))
  s <- covered_spans(dir)
  expect_equal(nrow(s), 1)
  expect_true(fully_covered(local("08:00:00"), local("10:30:00"), s))
  expect_false(fully_covered(local("10:30:00"), local("11:30:00"), s))
})

test_that("the schedule in force is the newest archived zip on or before the date", {
  dir <- tempfile("zips_"); dir.create(dir)
  for (d in c("2026-09-20", "2026-09-24", "2026-09-26")) file.create(file.path(dir, sprintf("mata_gtfs_%s_aaa111.zip", d)))
  expect_match(gtfs_zip_for_date(dir, "2026-09-25"), "2026-09-24")
  expect_match(gtfs_zip_for_date(dir, "2026-09-24"), "2026-09-24")
  expect_null(gtfs_zip_for_date(dir, "2026-09-19"))
})

test_that("trips are classified as observed, ghost, unobserved or not measurable", {
  dir <- scenario()
  g <- read_gtfs(list.files(dir, pattern = "zip$", full.names = TRUE))
  expect_equal(active_services(g, DATE), "WK")
  expect_length(active_services(g, "2026-09-26"), 0)                     # Saturday
  s <- scheduled_trips(g, DATE)
  cls <- classify_trips(match_trips(s$trips, read_positions(dir), covered_spans(dir)))
  setkey(cls, trip_id)
  expect_equal(cls[c("T1", "T2", "T3", "T4"), status], c("observed", "ghost", "observed", "unobserved"))
  expect_equal(cls[c("T1", "T2", "T3", "T4", "T5"), measurable], c(TRUE, TRUE, TRUE, TRUE, FALSE))
  r <- match_rates(cls)
  expect_equal(r[route_id == "(all)", c(scheduled, observed)], c(4L, 2L))
})

test_that("arrivals are interpolated along the shape to within a second", {
  dir <- scenario()
  g <- read_gtfs(list.files(dir, pattern = "zip$", full.names = TRUE))
  s <- scheduled_trips(g, DATE)
  pos <- read_positions(dir)
  cls <- classify_trips(match_trips(s$trips, pos, covered_spans(dir)))
  a <- infer_arrivals(cls, s$stop_times, pos, g)
  setkey(a, trip_id, stop_id)
  # The first stop (A) is never scored: the bus waits there before departing.
  expect_false("A" %in% a$stop_id)
  expect_equal(as.numeric(a[.("T1", "C"), arrival]), as.numeric(local("08:11:00")), tolerance = 1)
  expect_equal(as.numeric(a[.("T1", "D"), arrival]), as.numeric(local("08:21:30")), tolerance = 1)
  expect_equal(a[.("T1", "C"), delay_s], 60, tolerance = 1)
  expect_equal(a[.("T3", "C"), delay_s], 360, tolerance = 1)
})

test_that("reports far from the shape are ignored, and a long bracket leaves an arrival unobserved", {
  sh <- prepare_shape(data.table(shape_pt_lat = LAT0, shape_pt_lon = lon_at(c(0, 2500, 5000)),
                                 shape_pt_sequence = 0:2, shape_dist_traveled = c(0, 2500, 5000)))
  xy <- project_xy(c(lon_at(1000), lon_at(2000), lon_at(3000)), c(LAT0, LAT0 + 0.01, LAT0))
  expect_true(is.na(trip_progress(sh, xy[, 1], xy[, 2])[2]))            # about 1 km off the route
  expect_true(is.na(crossing_times(c(0, 400), c(2000, 3000), 2500)))     # 400 s bracket
  expect_equal(crossing_times(c(0, 100), c(2000, 3000), 2500), 50)
})

test_that("headway gaps span confirmed ghosts but never an unknown trip", {
  t <- function(hms) local(hms)
  ev <- data.table(service_date = as.Date(DATE), route_id = "R1", direction_id = "0", stop_id = "C",
                   trip_id = paste0("X", 1:6),
                   scheduled = t(c("07:00:00", "07:15:00", "07:30:00", "07:45:00", "08:00:00", "08:15:00")),
                   arrival = t(c("07:01:00", NA, "07:31:00", "07:46:00", NA, "08:17:00")),
                   status = c("observed", "ghost", "observed", "observed", "observed", "observed"),
                   measurable = TRUE)
  g <- headway_gaps(ev)
  # 07:01 -> 07:31 spans the ghost (30 min); 07:31 -> 07:46 (15 min); the
  # 08:00 trip ran but was not timed, so 07:46 -> 08:17 is not a gap.
  expect_equal(sort(g$observed$gap), c(15, 30) * 60)
  expect_equal(unique(g$scheduled$gap), 15 * 60)
})

test_that("a window needs data on most of its days", {
  through <- as.Date(DATE)
  expect_length(usable_windows(through, through, 0.9), 0)
  expect_equal(names(usable_windows(through, through, 0)), names(WINDOW_DAYS))
  expect_equal(names(usable_windows(through - 0:29, through, 0.9)), "30d")
})

test_that("metrics come out in the output contract, with suppression below the minimum n", {
  dir <- scenario()
  p <- read_positions(dir)
  days <- list(process_date(dir, as.Date(DATE), p, covered_spans(dir)))
  res <- compute_metrics_mata(days, as.Date(DATE), min_coverage = 0)
  m <- res$metrics
  g <- m[metric == "ghost_bus_rate" & geo_type == "citywide" & variant == "primary" & window_start == as.Date(DATE) - 29]
  expect_equal(g$n, 3L)              # T1, T2, T3: T4 is unobserved, T5 not measurable
  expect_true(g$suppressed)          # below the minimum of 30
  # Route R1 matched 2 of 4 measurable trips, below the 85% floor, so no
  # on-time figure is computed for it.
  expect_equal(nrow(m[metric == "on_time_pct"]), 0)
  tab <- memequity::as_metrics_table(as.data.frame(m), NA, as.Date(DATE))
  expect_length(memequity::metrics_problems(tab), 0)
})

test_that("on-time counts arrivals inside the window, for routes above the match floor", {
  dir <- scenario()
  p <- read_positions(dir)
  d <- process_date(dir, as.Date(DATE), p, covered_spans(dir))
  cls <- copy(d$cls$primary)[trip_id %in% c("T1", "T3")]        # an all-observed route
  cells <- stop_cells(list(d$stops))
  o <- compute_on_time(d$arrivals, cls, cells, as.Date(DATE))
  city <- o[geo_type == "citywide" & window_start == as.Date(DATE) - 29]
  # Delays: T1 60 s (C) and 90 s (D); T3 360 s (C) and 720 s (D).
  expect_equal(city[variant == "primary", n], 4L)
  expect_equal(nrow(o[geo_type == "stop"]), 2L * 2L * 2L)       # 2 stops x 2 variants x 2 windows
  a <- d$arrivals[order(trip_id, stop_id)]
  expect_equal(a$delay_s, c(60, 90, 360, 720), tolerance = 1)
  on <- a$delay_s >= ON_TIME$primary[1] & a$delay_s <= ON_TIME$primary[2]
  expect_equal(sum(on), 2L)
  wide <- a$delay_s >= ON_TIME$window_0_10[1] & a$delay_s <= ON_TIME$window_0_10[2]
  expect_equal(sum(wide), 3L)
})

test_that("SPEC_VERSIONS matches the version in each spec", {
  specs <- memequity::read_specs("mata", file.path(repo_root, "specs"))
  for (id in names(SPEC_VERSIONS))
    expect_identical(as.character(specs[[id]]$version), SPEC_VERSIONS[[id]], info = id)
})
