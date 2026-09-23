test_that("federal holidays land on known observed dates", {
  h <- federal_holidays(2024:2027)
  get <- function(name, year) h$date[h$holiday == name & format(h$date, "%Y") == year]
  expect_equal(get("mlk_day", "2024"), as.Date("2024-01-15"))
  expect_equal(get("memorial_day", "2025"), as.Date("2025-05-26"))
  expect_equal(get("thanksgiving", "2024"), as.Date("2024-11-28"))
  expect_equal(get("labor_day", "2026"), as.Date("2026-09-07"))
  # July 4 2026 is a Saturday: observed Friday July 3.
  expect_equal(get("independence_day", "2026"), as.Date("2026-07-03"))
  # Juneteenth 2027 is a Saturday: observed Friday June 18.
  expect_equal(get("juneteenth", "2027"), as.Date("2027-06-18"))
  # Christmas 2022 is a Sunday: observed Monday Dec 26.
  expect_equal(federal_holidays(2022)$date[federal_holidays(2022)$holiday == "christmas_day"],
               as.Date("2022-12-26"))
  expect_false("juneteenth" %in% federal_holidays(2020)$holiday)
})

test_that("easter computus matches known dates", {
  expect_equal(memequity:::easter_sunday(2024), as.Date("2024-03-31"))
  expect_equal(memequity:::easter_sunday(2025), as.Date("2025-04-20"))
  expect_equal(memequity:::easter_sunday(2026), as.Date("2026-04-05"))
})

test_that("city holiday rules and explicit dates are read from the spec file", {
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("holiday,rule,date,first_year,last_year,source_url",
               "day_after_thanksgiving,day_after_thanksgiving,,2020,,x",
               "special_closure,,2025-01-09,,,y"), f)
  ch <- city_holidays(2024:2025, f)
  expect_true(as.Date("2024-11-29") %in% ch$date)
  expect_true(as.Date("2025-11-28") %in% ch$date)
  expect_true(as.Date("2025-01-09") %in% ch$date)
  expect_equal(nrow(city_holidays(2019, f)), 0)
})

test_that("the shared calendar reproduces the City of Memphis 2026 holiday schedule exactly", {
  # Source: https://totalrewards.memphistn.gov/wp-content/uploads/2026/01/image-9.pdf
  official_2026 <- as.Date(c("2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03",
                             "2026-04-06", "2026-05-25", "2026-06-19", "2026-07-03",
                             "2026-09-07", "2026-11-11", "2026-11-26", "2026-11-27",
                             "2026-12-24", "2026-12-25"))
  cal <- holiday_calendar(2026)
  expect_equal(sort(cal$date[format(cal$date, "%Y") == "2026"]), official_2026)
  expect_false(as.Date("2026-10-12") %in% cal$date) # no Columbus Day
  # New Year's Day 2027 is a Friday.
  expect_true(as.Date("2027-01-01") %in% holiday_calendar(2027)$date)
})

test_that("inferred city rules shift weekend dates without collisions", {
  cal <- holiday_calendar(2015:2030)
  expect_false(anyDuplicated(cal$date) > 0)
  expect_true(all(as.integer(format(cal$date, "%u")) <= 5))
  # 2023: Dec 24 is a Sunday; Christmas observed Monday 25th, Eve Friday 22nd.
  expect_true(all(as.Date(c("2023-12-22", "2023-12-25")) %in% cal$date))
})

test_that("business-day convention: (open date, close date]", {
  hol <- federal_holidays(2024:2026)$date
  bd <- function(a, b) business_days_between(as.Date(a), as.Date(b), hol)
  expect_equal(bd("2026-09-21", "2026-09-21"), 0)   # same day
  expect_equal(bd("2026-09-18", "2026-09-21"), 1)   # Fri -> Mon
  expect_equal(bd("2026-09-19", "2026-09-21"), 1)   # Sat -> Mon
  expect_equal(bd("2026-09-14", "2026-09-21"), 5)   # Mon -> Mon
  expect_equal(bd("2026-09-04", "2026-09-08"), 1)   # Fri -> Tue across Labor Day
  expect_equal(bd("2024-11-27", "2024-12-02"), 2)   # Wed -> Mon across Thanksgiving
  expect_true(is.na(bd("2026-09-21", "2026-09-18"))) # close before open
  expect_true(is.na(business_days_between(as.Date("2026-09-21"), as.Date(NA), hol)))
})

test_that("business days are vectorised and match a naive count", {
  hol <- federal_holidays(2025:2026)$date
  set.seed(1)
  s <- as.Date("2025-01-01") + sample(0:500, 200, TRUE)
  e <- s + sample(0:40, 200, TRUE)
  naive <- vapply(seq_along(s), function(i) {
    if (e[i] == s[i]) return(0L)
    d <- seq(s[i] + 1, e[i], by = "day")
    sum(is_business_day(d, hol))
  }, integer(1))
  expect_equal(business_days_between(s, e, hol), naive)
})

test_that("timestamps are converted to Memphis local dates, including across DST", {
  # 03:00Z on 10 Mar 2026 is 22:00 CDT on 9 Mar.
  expect_equal(local_date("2026-03-10T03:00:00Z"), as.Date("2026-03-09"))
  # Floating (zone-less) timestamps are already local.
  expect_equal(local_date("2026-03-10T03:00:00.000"), as.Date("2026-03-10"))
  # DST starts 8 Mar 2026 at 02:00 local; 07:30Z is 01:30 CST, 08:30Z is 03:30 CDT.
  expect_equal(local_date(as.POSIXct("2026-03-08 07:30:00", tz = "UTC")), as.Date("2026-03-08"))
  expect_equal(local_date(as.POSIXct("2026-03-08 05:30:00", tz = "UTC")), as.Date("2026-03-07"))
  # DST ends 1 Nov 2026: 05:30Z is 00:30 CDT on 1 Nov.
  expect_equal(local_date(as.POSIXct("2026-11-01 05:30:00", tz = "UTC")), as.Date("2026-11-01"))
  expect_equal(local_date(as.POSIXct("2026-11-01 04:30:00", tz = "UTC")), as.Date("2026-10-31"))
  # Opened Friday 11pm local, closed Monday: one business day.
  hol <- federal_holidays(2026)$date
  expect_equal(business_days_between("2026-09-18T23:00:00", "2026-09-21T08:00:00", hol), 1)
})

test_that("add_business_days is the inverse of business_days_between", {
  hol <- federal_holidays(2024:2026)$date
  s <- as.Date("2024-11-20") + 0:60
  for (n in c(0, 3, 7, 10)) {
    d <- add_business_days(s, n, hol)
    expect_equal(business_days_between(s, d, hol), rep(n, length(s)))
  }
})
