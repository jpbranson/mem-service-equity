# Shared business-day calendar (design plan 5.3).
#
# Every pipeline counts business days with these functions and this calendar,
# so a change to the holiday list changes every metric at once and shows up in
# one diff.

MSE_TZ <- "America/Chicago"

nth_weekday <- function(year, month, wday, n) {
  # wday: 1 = Monday ... 7 = Sunday (ISO). n = -1 means last.
  first <- as.Date(sprintf("%04d-%02d-01", year, month))
  days <- seq(first, by = "day", length.out = 31)
  days <- days[as.integer(format(days, "%m")) == month]
  hits <- days[iso_wday(days) == wday]
  if (n == -1) hits[length(hits)] else hits[n]
}

iso_wday <- function(d) as.integer(format(d, "%u"))

observed <- function(d) {
  # Federal rule: Saturday holidays observed Friday, Sunday holidays Monday.
  w <- iso_wday(d)
  d[w == 6] <- d[w == 6] - 1
  d[w == 7] <- d[w == 7] + 1
  d
}

#' Federal holidays (observed dates) for the given years.
#' @export
federal_holidays <- function(years) {
  rows <- lapply(years, function(y) {
    fixed <- function(m, d) as.Date(sprintf("%04d-%02d-%02d", y, m, d))
    h <- list(
      new_years_day      = observed(fixed(1, 1)),
      mlk_day            = nth_weekday(y, 1, 1, 3),
      presidents_day     = nth_weekday(y, 2, 1, 3),
      memorial_day       = nth_weekday(y, 5, 1, -1),
      juneteenth         = if (y >= 2021) observed(fixed(6, 19)) else NULL,
      independence_day   = observed(fixed(7, 4)),
      labor_day          = nth_weekday(y, 9, 1, 1),
      columbus_day       = nth_weekday(y, 10, 1, 2),
      veterans_day       = observed(fixed(11, 11)),
      thanksgiving       = nth_weekday(y, 11, 4, 4),
      christmas_day      = observed(fixed(12, 25))
    )
    h <- h[!vapply(h, is.null, logical(1))]
    data.frame(date = do.call(c, unname(h)), holiday = names(h),
               source = "federal", stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

rule_date <- function(rule, year) {
  switch(rule,
    day_after_thanksgiving = nth_weekday(year, 11, 4, 4) + 1,
    good_friday = easter_sunday(year) - 2,
    christmas_eve = observed(as.Date(sprintf("%04d-12-24", year))),
    stop("Unknown holiday rule: ", rule, call. = FALSE)
  )
}

easter_sunday <- function(year) {
  # Anonymous Gregorian algorithm.
  a <- year %% 19; b <- year %/% 100; c <- year %% 100
  d <- b %/% 4; e <- b %% 4; f <- (b + 8) %/% 25; g <- (b - f + 1) %/% 3
  h <- (19 * a + b - d - g + 15) %% 30; i <- c %/% 4; k <- c %% 4
  l <- (32 + 2 * e + 2 * i - h - k) %% 7; m <- (a + 11 * h + 22 * l) %/% 451
  month <- (h + l - 7 * m + 114) %/% 31
  day <- ((h + l - 7 * m + 114) %% 31) + 1
  as.Date(sprintf("%04d-%02d-%02d", year, month, day))
}

#' City of Memphis holidays that are not federal holidays.
#'
#' Read from inst/extdata/city_holidays.csv. Each row is either a rule
#' (`rule` column, applied to every year between `first_year` and
#' `last_year`) or an explicit `date`.
#' @export
city_holidays <- function(years,
                          path = system.file("extdata", "city_holidays.csv",
                                             package = "memequity")) {
  empty <- data.frame(date = as.Date(character()), holiday = character(),
                      source = character(), stringsAsFactors = FALSE)
  if (!nzchar(path) || !file.exists(path)) return(empty)
  spec <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  if (!nrow(spec)) return(empty)
  out <- list()
  for (i in seq_len(nrow(spec))) {
    r <- spec[i, ]
    if (!is.na(r$date)) {
      d <- as.Date(r$date)
      if (as.integer(format(d, "%Y")) %in% years)
        out[[length(out) + 1]] <- data.frame(date = d, holiday = r$holiday,
                                             source = "city", stringsAsFactors = FALSE)
    } else {
      ys <- years[years >= r$first_year & (is.na(r$last_year) | years <= r$last_year)]
      for (y in ys)
        out[[length(out) + 1]] <- data.frame(date = rule_date(r$rule, y), holiday = r$holiday,
                                             source = "city", stringsAsFactors = FALSE)
    }
  }
  if (!length(out)) return(empty)
  do.call(rbind, out)
}

#' The shared holiday calendar: federal plus City of Memphis holidays.
#' @export
holiday_calendar <- function(years = 2015:2030) {
  cal <- rbind(federal_holidays(years), city_holidays(years))
  cal <- cal[!duplicated(cal$date), ]
  cal[order(cal$date), ]
}

#' Convert timestamps to local (America/Chicago) calendar dates.
#'
#' POSIXct values are converted to local time. Character timestamps without a
#' zone (Socrata "floating timestamps") are already local and are read as
#' local time; a trailing "Z" marks UTC.
#' @export
local_date <- function(x, tz = MSE_TZ) {
  if (inherits(x, "Date")) return(x)
  if (is.character(x)) {
    utc <- grepl("Z$", x)
    fmts <- c("%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d %H:%M:%OS", "%Y-%m-%dT%H:%M", "%Y-%m-%d")
    parse <- function(v, zone) {
      out <- rep(NA_real_, length(v))
      for (f in fmts) {
        todo <- is.na(out) & !is.na(v)
        if (!any(todo)) break
        out[todo] <- as.numeric(as.POSIXct(v[todo], tz = zone, format = f))
      }
      out
    }
    secs <- ifelse(utc, parse(sub("Z$", "", x), "UTC"), parse(x, tz))
    x <- as.POSIXct(secs, origin = "1970-01-01", tz = "UTC")
  }
  as.Date(format(x, tz = tz, "%Y-%m-%d"))
}

#' Is each date a business day (Mon-Fri and not a holiday)?
#' @export
is_business_day <- function(d, holidays = holiday_calendar()$date) {
  d <- as.Date(d)
  iso_wday(d) <= 5 & !(d %in% holidays)
}

#' Business days elapsed between two timestamps.
#'
#' Convention: the number of business days `d` with
#' `local_date(start) < d <= local_date(end)`. A request opened and closed
#' the same day is 0; opened Friday and closed Monday is 1; opened Saturday
#' and closed Monday is 1. Returns NA where `end` is missing or precedes
#' `start`.
#' @export
business_days_between <- function(start, end, holidays = holiday_calendar()$date) {
  s <- local_date(start)
  e <- local_date(end)
  n <- max(length(s), length(e))
  s <- rep_len(s, n); e <- rep_len(e, n)
  out <- rep(NA_integer_, n)
  ok <- !is.na(s) & !is.na(e) & e >= s
  if (!any(ok)) return(out)
  lo <- min(s[ok]); hi <- max(e[ok])
  all_days <- seq(lo, hi, by = "day")
  cum <- cumsum(is_business_day(all_days, holidays))
  idx <- function(d) as.integer(d - lo) + 1L
  out[ok] <- cum[idx(e[ok])] - cum[idx(s[ok])]
  out
}

#' The date `n` business days after `start` (the deadline for an n-day target).
#' @export
add_business_days <- function(start, n, holidays = holiday_calendar()$date) {
  s <- local_date(start)
  vapply(seq_along(s), function(i) {
    if (is.na(s[i]) || is.na(n[(i - 1) %% length(n) + 1])) return(NA_real_)
    k <- n[(i - 1) %% length(n) + 1]
    d <- s[i]
    while (k > 0) {
      d <- d + 1
      if (is_business_day(d, holidays)) k <- k - 1
    }
    as.numeric(d)
  }, numeric(1)) |> as.Date(origin = "1970-01-01")
}
