---
id: reopen_rate
pipeline: "311"
title: Share of closed requests re-reported within 30 days
version: "0.1"
status: draft
unit: proportion
formula: >
  Among deduplicated requests closed in the window, and at least 30 days
  before computation, the share followed by a new request of the same type
  within 50 m within 30 days of the close.
windows: [90d, 12m]
geographies: [citywide, zcta, council_district, h3_8]
min_n: 30
promise:
  kind: comparison
  text: No official standard. A problem that comes back soon after being closed suggests it was not fixed.
  source_url: ""
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
  - Deduplicated closed requests of the given type with an accepted geocode.
exclusions:
  - Requests closed fewer than 30 days before computation (outcome unknown).
confounders:
  - Busy corridors may generate genuinely new problems of the same type nearby.
objections:
  - objection: "A new pothole 40 m away is a new pothole, not a reopen."
    response: "Published at 25 m, 50 m and 100 m; if the conclusion depends on the radius, the panel says so."
  - objection: "Our system has an explicit reopen status; use it."
    response: "If the source exposes one it becomes the primary definition and the spatial re-report rule becomes the alternative (see docs/research/311.md)."
  - objection: "Engaged neighborhoods re-report more."
    response: "The metric is shown as a comparison alongside request volume, never as a quality ranking."
---

## Definition

Of the requests closed near you, how many came back within a month?

## Change log

- 0.1 — first draft from design plan 6.3.
