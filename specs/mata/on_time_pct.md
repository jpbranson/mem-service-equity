---
id: on_time_pct
pipeline: mata
title: Share of observed bus arrivals on time at stops near you
version: "0.2"
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

- **Matching.** Every vehicle report carries MATA's trip_id, which matches
  the static feed, so trips are matched by id on the service date. The
  service date is the local date of the report; no MATA trip runs past
  midnight. The schedule used is the one in force that day: the newest
  archived GTFS zip dated on or before it.
- **Arrival inference.**
  - Each report on the trip is projected onto the trip's shape.
  - The arrival at a stop is when the distance along the shape reaches the
    stop's, interpolated linearly between the two bracketing reports.
  - Reports more than 60 m off the shape are ignored, and so is a bracket
    wider than 180 s.
  - A vehicle that halts within 30 m short of a stop (typically at a
    terminal) arrives at its first report that close.
  - A report may not project more than 300 m behind the furthest point
    already reached, so a route that doubles back is not confused.
- **The first stop of each trip is not scored.** The bus waits there
  before departing. Early departures from later timepoints are the
  "−1 minute" edge.
- **Measurable trips.** A trip counts only if the poller covered its whole
  scheduled span, plus 15 minutes on each side (DECISIONS.md H22).
- **Windows** are computed only when archived data cover at least 90% of
  their days.
- **Citywide** means the whole MATA system, including route segments
  outside the city limits.

## Change log

- 0.1 — first draft from design plan 6.1.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — first computed version: arrival inference by projection onto the shape (replacing the first report within 30 m); first stop excluded; measurability and window-coverage rules stated. Tested on a synthetic route and run on 3 days of archive at 43% coverage.
