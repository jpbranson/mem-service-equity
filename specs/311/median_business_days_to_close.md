---
id: median_business_days_to_close
pipeline: "311"
title: Median business days from request to close
version: "0.1"
status: draft
unit: business_days
formula: >
  Kaplan-Meier median of business days from open to close, per request type,
  over deduplicated requests opened in the window. Requests still open at
  computation time are right-censored at their current age.
windows: [90d, 12m]
geographies: [citywide, zcta, council_district, h3_8]
min_n: 20
promise:
  kind: official
  text: The city's published target timeframe for the request type is shown beside the median.
  source_url: ""
thresholds: []
inclusions:
  - Deduplicated primary requests of the given type opened in the window.
exclusions:
  - Requests closed as duplicates by the city.
  - Requests with a close time before their open time (counted in the validation report).
  - Requests spanning the October 2023 platform migration.
confounders:
  - Request type mix; always reported per type.
  - Engagement; areas that report more may have smaller, quicker problems reported.
objections:
  - objection: "Medians over recent windows are biased because slow requests have not closed yet."
    response: "The median is a Kaplan-Meier estimate that treats open requests as censored at their current age rather than dropping them. If fewer than half of requests have closed, the cell is suppressed rather than guessed."
  - objection: "A pothole on an arterial is handled by a different crew and priority than a residential one."
    response: "The metric is always per request type and per area; the address panel lists the individual requests near the address so a reader can see what drives the number."
  - objection: "Business days in your calendar don't match ours."
    response: "One shared, published holiday calendar is used for every metric and is tested against the city's worked examples where they exist; a missing city holiday is a one-line correction that versions the series."
---

## Definition

Half of the requests of this type near you were closed within this many
business days.

## Details and edge cases

- Censoring: a request open at computation time contributes its current age
  as a censored observation.
- Interval: log-log Kaplan-Meier confidence interval for the median. If the
  upper bound is not reached it is shown as "more than <max observed>".

## Change log

- 0.1 — first draft from design plan 6.3.
