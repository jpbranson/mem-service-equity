---
id: on_time_pct
pipeline: mata
title: Share of observed bus arrivals on time at stops near you
version: "0.1"
status: draft
unit: proportion
formula: >
  Among inferred arrivals at timepoint stops matched to a scheduled trip:
  count(arrival - scheduled time within [-1, +5] minutes) / count(matched
  arrivals). Computed per stop and per route over rolling windows, using the
  GTFS feed version in force on each service date.
windows: [30d, 90d]
geographies: [citywide, route, stop, h3_8]
min_n: 30
promise:
  kind: official
  text: The bus arrives at the scheduled time at the scheduled stop (the published GTFS schedule).
  source_url: ""
reconciliation:
  measures: [scheduled_trips, reported_on_time]
  text: >
    Plan 5.5: observed against scheduled trips per route per day (GTFS static), and any
    on-time figure MATA reports to the National Transit Database or its board (definition
    pending, DECISIONS.md H16).
thresholds:
  - name: on-time window
    primary: "[-1, +5] minutes (industry convention)"
    alternatives: ["[0, +10] minutes", "MATA's own standard, if published"]
    arbitrary: true
inclusions:
  - Arrivals matched to a scheduled trip on routes whose trip-match rate is at least 85% in the window.
  - Timepoint stops (the stops the schedule actually commits to).
exclusions:
  - Minutes when the poller was down (excluded from numerator and denominator; uptime published).
  - Routes below the match-rate floor (shown as "not yet measurable").
  - Service dates with a declared detour or emergency service change, if MATA publishes them.
confounders:
  - Traffic, construction and weather are outside MATA's control but are part of the resident's experience.
objections:
  - objection: "Your on-time window is stricter than ours."
    response: "Published under [-1,+5], [0,+10] and MATA's standard if one is published; the stricter window is never the only one shown."
  - objection: "You inferred arrivals from GPS pings; that's not an arrival."
    response: "Arrival inference is validated against a stopwatch audit at three stops before launch (DECISIONS.md H5), and the inference error is published."
  - objection: "Your trip matching is wrong so your lateness is wrong."
    response: "Routes below an 85% match rate are not published; the matching rule and per-route match rates are published."
---

## Definition

When a bus stops near you, how often is it within a few minutes of the
schedule?

## Details

Arrival inference: the first position report within 30 m of the stop with
the vehicle on the matched trip, interpolated between the bracketing pings.
Early departures from timepoints are the "-1 minute" edge.

## Change log

- 0.1 — first draft from design plan 6.1.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
