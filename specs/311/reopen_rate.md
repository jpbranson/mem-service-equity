---
id: reopen_rate
pipeline: "311"
title: Share of closed requests re-reported within 30 days
version: "0.1"
status: frozen
unit: proportion
formula: >
  Among deduplicated requests closed in the window, and at least 30 days
  before computation, the share followed by a new request of the same type
  within 50 m that opens 1 to 30 days after the close date. A request
  opened on the close date itself does not count.
windows: [90d, 12m]
geographies: [citywide, zcta, council_district, super_district, reference_neighborhood, h3_9]
min_n: 30
promise:
  kind: comparison
  text: No official standard. A problem that comes back soon after being closed suggests it was not fixed.
  source_url: ""
reconciliation:
  measures: [requests_created]
  text: >
    Service request counts the City publishes, recomputed from the same 311 records
    (DECISIONS.md D22). This checks the fetch, the request-type mapping and the date
    handling behind this metric. It does not check timing or dispositions; the manual
    audit (H3) covers those.
thresholds:
  - name: re-report window
    primary: "30 days"
    alternatives: ["14 days", "60 days"]
    arbitrary: true
  - name: same-location radius
    primary: "50 m"
    alternatives: ["25 m", "100 m"]
    arbitrary: true
inclusions:
  - Deduplicated closed requests of the given type with an accepted geocode, located inside the city limits in every geography including citywide.
  - The later request can be any included request inside the city, near-duplicates included, since a re-report is by definition near an earlier request.
  - Address-level (h3_9) rows exist only for the headline request types (headline = TRUE in pipelines/311/config/request_types.csv).
exclusions:
  - Requests closed fewer than 30 days before computation (outcome unknown).
  - Closed requests without a usable close date (the four kinds listed in median_business_days_to_close).
confounders:
  - Busy corridors may generate genuinely new problems of the same type nearby.
  - A resident who files again on the day a request is closed is not counted, so the share is a lower bound on quick re-reports.
  - Mass closures (see median_business_days_to_close): a request closed in a batch was not necessarily fixed, and its close date is not when the work was done. No window published on 2026-10-06 contains the largest one, 2025-09-22.
objections:
  - objection: "A new pothole 40 m away is a new pothole, not a reopen."
    response: "Published at 25 m, 50 m and 100 m; if the conclusion depends on the radius, the panel says so."
  - objection: "Our system has an explicit reopen status; use it."
    response: "The source has no documented reopen status. Two statuses, Back to Department and Back to MCSC, may work as one, but the City has not said what they mean (DECISIONS.md H8), and both are treated as open. If the City confirms a reopen status, it becomes the primary definition in a new version and the spatial rule becomes the alternative (see docs/research/311-permits-districts.md)."
  - objection: "Engaged neighborhoods re-report more."
    response: "The metric is shown as a comparison alongside request volume, never as a quality ranking."
---

## Definition

Of the requests closed near you, how many came back within a month?

## Change log

- 0.1 — first draft from design plan 6.3.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22); corrected file references. No change to the definition.
- 0.1, 2026-10-06 — frozen at the owner's direction, reviewed by Claude (DECISIONS.md D33). The text now says what has been computed since 0.1: a re-report opens 1 to 30 days after the close date, never on it; the two extra geographies; the city-limits rule; headline types only at address level (H10 packet). Reworded the answer on reopen statuses and added the confounder on mass closures. No computed value changes.
