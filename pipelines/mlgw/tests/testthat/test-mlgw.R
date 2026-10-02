# Layer 3 tests for the MLGW pipeline (plan 5.3) on a synthetic archive with
# known answers (scenario in helper-mlgw.R). A golden file comes once the
# poller has a well-covered month (DECISIONS.md H22).

ev_of <- function(ev, id) ev[event_id == id]
mins <- function(x) as.numeric(x, units = "mins")

test_that("snapshots are deduplicated by poll time and empty snapshots still count as polls", {
  s <- read_snapshots(scenario())
  expect_length(s$polls, length(SCENARIO_POLLS))
  expect_equal(nrow(s$obs), uniqueN(s$obs, by = c("poll_time", "OUTAGE_NO")))
  expect_length(s$missing_fields, 0)
})

test_that("map times are local, and the repeated hour reads as CDT", {
  expect_equal(format(parse_local_time("09/24/2026 01:30:00 PM"), tz = "UTC", "%Y-%m-%d %H:%M"), "2026-09-24 18:30")
  expect_equal(format(parse_local_time("12/01/2026 01:30:00 PM"), tz = "UTC", "%Y-%m-%d %H:%M"), "2026-12-01 19:30")
  # Daylight saving ends 2026-11-01: 01:30 happens twice; the first is 06:30 UTC.
  expect_equal(format(parse_local_time("11/01/2026 01:30:00 AM"), tz = "UTC", "%Y-%m-%d %H:%M"), "2026-11-01 06:30")
  expect_true(is.na(parse_local_time("")))
})

test_that("an OUTAGE_NO back after more than 2 hours is a new event; within 2 hours, the same one", {
  ev <- scenario_events()
  expect_setequal(ev$event_id, c("101-1", "101-2", "102-1", "103-1", "104-1", "105-1"))
  expect_true(ev_of(ev, "102-1")$reappeared)
  expect_false(any(ev[event_id != "102-1"]$reappeared))
})

test_that("restoration lies between the last poll showing an outage and the first without it", {
  e <- ev_of(scenario_events(), "101-1")
  expect_true(e$confirmed)
  expect_equal(e$restored_lo, utc("08:30"))
  expect_equal(e$restored_hi, utc("08:35"))
  expect_equal(e$restoration_span_s, 300)
  expect_equal(e$duration_s / 60, 30.5)
  # First estimate 08:20; restored at the 08:32:30 midpoint.
  expect_equal(mins(e$restored_mid - e$first_etr), 12.5)
})

test_that("start is the earliest TIME_STAMP and location the first point observed", {
  ev <- scenario_events()
  expect_equal(ev_of(ev, "102-1")$start, utc("08:55"))
  expect_equal(ev_of(ev, "101-1")$lon, -90.05)
})

test_that("customer-hours count certain spans in both bounds and the restoration span only in the upper", {
  ev <- scenario_events()
  # 101-1: six sightings of 10 customers; five certain 5-minute spans, then restoration.
  expect_equal(ev_of(ev, "101-1")$cust_hours_lo, 5 * 5 * 10 / 60)
  expect_equal(ev_of(ev, "101-1")$cust_hours_hi, 6 * 5 * 10 / 60)
  # 102-1: certain spans 09:00-09:10 and 09:30-09:40; uncertain after 09:10 and 09:40.
  expect_equal(ev_of(ev, "102-1")$cust_hours_lo, 4 * 5 * 5 / 60)
  expect_equal(ev_of(ev, "102-1")$cust_hours_hi, 6 * 5 * 5 / 60)
  # 103-1: the span from 10:00 to the next poll (10:35) is the poller gap.
  expect_equal(ev_of(ev, "103-1")$cust_hours_hi - ev_of(ev, "103-1")$cust_hours_lo, 35 * 20 / 60)
})

test_that("an outage still on at the last poll has no restoration and no final span", {
  e <- ev_of(scenario_events(), "105-1")
  expect_false(e$confirmed)
  expect_true(is.na(e$restored_mid))
  expect_equal(e$cust_hours_hi, 6 * 5 * 2 / 60)
  expect_equal(e$first_etr, utc("12:30"))
  expect_equal(e$final_etr, utc("13:00"))
  expect_equal(e$etr_60m, utc("13:00"))    # shown at 12:00, start 11:00
})

test_that("a planned cause marks the event planned", {
  ev <- scenario_events()
  expect_true(ev_of(ev, "104-1")$planned)
  expect_false(any(ev[event_id != "104-1"]$planned))
})

test_that("covered spans break at the poller gap", {
  s <- read_snapshots(scenario())
  sp <- covered_spans(s$polls)
  expect_equal(nrow(sp), 2)
  expect_equal(span_coverage(sp, utc("08:00"), utc("12:00")), (240 - 35) / 240)
})

# ---- metrics ------------------------------------------------------------------

scenario_metrics <- function() {
  ev <- scenario_events()
  cells <- h3jsr::point_to_cell(sf::st_sfc(sf::st_point(c(-90.05, 35.14)), crs = 4326), res = 9, simple = TRUE)
  neighbour <- setdiff(h3jsr::get_disk(cells, ring_size = 1L)[[1]], cells)[1]
  ev[, `:=`(citywide = "4748000", council_district = "1",
            zcta = fifelse(outage_no %in% c("101", "102"), "38103", "38104"),
            h3_9 = fifelse(event_id == "103-1", neighbour, cells))]
  den <- data.table(geo_type = c("citywide", "zcta", "zcta", "zcta", "council_district"),
                    geo_id = c("4748000", "38103", "38104", "38105", "1"),
                    population = c(600000, 5000, 500, 3000, 90000),
                    households = c(250000, 2000, 200, 1000, 35000))
  list(ev = ev, m = as.data.frame(compute_metrics_mlgw(ev, den, as.Date(DATE))), cell = cells,
       neighbour = neighbour)
}

row_of <- function(m, metric, geo_id, variant = "primary", subgroup = "all")
  m[m$metric == metric & m$geo_id == geo_id & m$variant == variant & m$subgroup == subgroup, ]

test_that("event counts split planned from unplanned and follow the size thresholds", {
  m <- scenario_metrics()$m
  expect_equal(row_of(m, "outage_events_per_year", "4748000")$n, 5)
  expect_equal(row_of(m, "outage_events_per_year", "4748000", subgroup = "planned")$n, 1)
  expect_equal(row_of(m, "outage_events_per_year", "4748000", "min_10_customers")$n, 2)
  expect_equal(row_of(m, "outage_events_per_year", "38103")$n, 3)
})

test_that("an area with no outages reads zero with an exact Poisson interval", {
  r <- row_of(scenario_metrics()$m, "outage_events_per_year", "38105")
  expect_equal(r$n, 0)
  expect_equal(r$value, 0)
  expect_equal(r$ci_high, stats::qchisq(0.975, 2) / 2)
  expect_false(r$suppressed)
})

test_that("an address disk counts the outages in the cell and its six neighbours", {
  s <- scenario_metrics()
  r <- s$m[s$m$metric == "outage_events_per_year" & s$m$geo_type == "h3_9" &
             s$m$variant == "primary" & s$m$subgroup == "all", ]
  expect_equal(r[r$geo_id == s$cell, ]$n, 5)          # four in the cell, 103 next door
  expect_equal(r[r$geo_id == s$neighbour, ]$n, 5)
})

test_that("customer-hours are per 1,000 households, bounded by poll timing, and need 1,000 residents", {
  s <- scenario_metrics()
  e <- s$ev[zcta == "38103"]
  r <- row_of(s$m, "customer_hours_per_1000", "38103")
  expect_equal(r$ci_low, sum(e$cust_hours_lo) / 2000 * 1000)
  expect_equal(r$ci_high, sum(e$cust_hours_hi) / 2000 * 1000)
  expect_equal(r$value, (r$ci_low + r$ci_high) / 2)
  expect_true(row_of(s$m, "customer_hours_per_1000", "38104")$suppressed)
  expect_equal(row_of(s$m, "customer_hours_per_1000", "38105")$value, 0)
})

test_that("restoration vs. estimate uses only confirmed restorations outside long poller gaps", {
  r <- row_of(scenario_metrics()$m, "restoration_vs_estimate", "4748000")
  # 101-1 only: 103-1 was restored in the 35-minute gap, 105-1 is still on,
  # 102-1 and 101-2 had no estimate.
  expect_equal(r$n, 1)
  expect_true(r$suppressed)
})

test_that("the metrics table meets the output contract", {
  m <- memequity::as_metrics_table(as.data.frame(scenario_metrics()$m), NA, as.Date(DATE))
  expect_length(memequity::metrics_problems(m), 0)
  expect_setequal(unique(m$metric), names(SPEC_VERSIONS))
})
