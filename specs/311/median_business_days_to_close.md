---
id: median_business_days_to_close
pipeline: "311"
title: Median business days from request to close
version: "0.1"
status: frozen
unit: business_days
formula: >
  Kaplan-Meier median of business days from open to close, per request type,
  over deduplicated requests opened in the window. Requests still open at
  computation time are right-censored at their current age.
windows: [90d, 12m]
geographies: [citywide, zcta, council_district, super_district, reference_neighborhood, h3_9]
min_n: 20
promise:
  kind: comparison
  text: >
    Compared against the citywide median for the same request type and
    window. Where an official target exists (potholes, 5-10 business days)
    it is shown beside the median.
  source_url: "https://memphistn.gov/potholes-repairs-winter-weather"
reconciliation:
  measures: [requests_created]
  text: >
    Service request counts the City publishes, recomputed from the same 311 records
    (DECISIONS.md D22). This checks the fetch, the request-type mapping and the date
    handling behind this metric. It does not check timing or dispositions; the manual
    audit (H3) covers those.
thresholds: []
inclusions:
  - Deduplicated primary requests of the given type opened in the window.
  - Only requests located inside the city limits, in every geography including citywide. A request with no usable location cannot be placed inside the city.
  - Address-level (h3_9) rows exist only for the headline request types (headline = TRUE in pipelines/311/config/request_types.csv).
exclusions:
  - Requests closed as duplicates by the city.
  - Closed requests without a usable close date, each kind counted in the validation report. These are a missing close date, a close date before the open date, a placeholder close date before the October 2023 migration (years 0001 and 1202 occur), and a close date in the future.
  - Requests spanning the October 2023 platform migration.
confounders:
  - Request type mix; always reported per type.
  - Engagement; areas that report more may have smaller, quicker problems reported.
  - Missing close dates are concentrated in time, not in place. On 2026-09-23 they were 4.4% of closed requests overall, but 60% of those opened in December 2025 and 46% of those opened in January 2026, against 4.2% to 5.2% in every council district. A 12-month window that includes those months leaves out about half of their closed requests, and if those closed unusually fast or slowly the median is biased. The cause is not known (DECISIONS.md H8).
  - Mass closures. On 2025-09-22 at least 23,684 requests were closed in batches that share one close time to the second, some of them opened more than a year earlier (found in the audit, DECISIONS.md D33). Such a close date is when the record was closed, not when the work was done. No window published on 2026-10-06 contains that day. Smaller batches, about 1,700 requests in all, fall on seven later days through September 2026.
objections:
  - objection: "Medians over recent windows are biased because slow requests have not closed yet."
    response: "The median is a Kaplan-Meier estimate that treats open requests as censored at their current age rather than dropping them. If fewer than half of requests have closed, the cell is suppressed rather than guessed."
  - objection: "A pothole on an arterial is handled by a different crew and priority than a residential one."
    response: "The metric is always per request type and per area; the address panel lists the individual requests near the address so a reader can see what drives the number."
  - objection: "Business days in your calendar don't match ours."
    response: "One shared, published City of Memphis holiday calendar is used for every metric (DECISIONS.md D5, D10). The City has published no worked example to test it against. The 2026 calendar is verified; 2023 to 2025 are rebuilt from the City's rules, with two weekend shifts inferred (H13). A missing city holiday is a one-line correction that versions the series."
---

## Definition

Half of the requests of this type near you were closed within this many
business days.

## Details and edge cases

- Open is the time the record was created in the City's system
  (`created_date`). The City's `REPORTED_DATE` is not used: on some records
  it is 6 or 12 hours later than the creation time, and for 3 of the 100
  audited requests it was one to three days earlier, so the metric
  understates those residents' wait.
- A close date with no time of day (common on solid-waste requests) is read
  as that local day.
- Censoring: a request open at computation time contributes its current age
  as a censored observation.
- Interval: log-log Kaplan-Meier confidence interval for the median. If the
  upper bound is not reached it is shown as "more than <max observed>".

## Change log

- 0.1 — first draft from design plan 6.3.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.1, 2026-10-06 — frozen at the owner's direction, reviewed by Claude (DECISIONS.md D33). The text now says what has been computed since 0.1: the two extra geographies, the city-limits rule, headline types only at address level, and all four close-date problems (H10 packet C1 to C4). Added the confounders on missing close dates and mass closures, and the note on which open time is used. No computed value changes.
