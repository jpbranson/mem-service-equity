---
id: peak_headway_ratio
pipeline: mata
title: Median observed peak headway vs. scheduled headway
version: "0.1"
status: draft
unit: ratio
formula: >
  For each route-direction and timepoint stop during weekday peaks (06:00-09:00,
  15:00-18:00 local): median(observed gap between consecutive arrivals) /
  median(scheduled gap). Bootstrap interval on the observed median.
windows: [30d, 90d]
geographies: [citywide, route, stop]
min_n: 20
promise:
  kind: official
  text: Buses come as often as the schedule says during rush hour.
  source_url: ""
thresholds:
  - name: peak definition
    primary: "06:00-09:00 and 15:00-18:00 weekdays"
    alternatives: ["06:30-08:30 and 16:00-18:00", "MATA's published peak periods"]
    arbitrary: true
inclusions:
  - Routes with scheduled peak headways of 30 minutes or less.
exclusions:
  - Gaps spanning a poller outage.
confounders:
  - Bunching makes the median gap look fine while the wait is long; the 90th-percentile gap is shown beside it.
objections:
  - objection: "Median gap hides bunching."
    response: "The 90th-percentile observed gap is shown alongside, and excess wait time is a planned v0.2 addition."
  - objection: "Routes with 60-minute headways are schedule-based, not headway-based."
    response: "Only routes with scheduled peak headways of 30 minutes or less are included."
  - objection: "Peak periods differ by route."
    response: "MATA's own peak definitions are published as an alternative once located."
---

## Definition

At rush hour, how long is the typical gap between buses, compared with what
the schedule promises?

## Change log

- 0.1 — first draft from design plan 6.1.
