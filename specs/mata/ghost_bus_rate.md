---
id: ghost_bus_rate
pipeline: mata
title: Share of scheduled trips that never showed up
version: "0.1"
status: draft
unit: proportion
formula: >
  Among scheduled trips (GTFS, feed version in force) on routes serving the
  area, during minutes the poller was up: count(trips with no observed
  vehicle within +/-15 minutes of any timepoint) / count(scheduled trips).
windows: [30d, 90d]
geographies: [citywide, route, stop, h3_8]
min_n: 30
promise:
  kind: official
  text: Every scheduled trip runs.
  source_url: ""
reconciliation:
  measures: [scheduled_trips, reported_on_time]
  text: >
    Plan 5.5: observed against scheduled trips per route per day (GTFS static), and any
    on-time figure MATA reports to the National Transit Database or its board (definition
    pending, DECISIONS.md H16).
thresholds:
  - name: observation tolerance
    primary: "+/-15 minutes at any timepoint"
    alternatives: ["+/-10 minutes", "+/-30 minutes"]
    arbitrary: true
inclusions:
  - Scheduled trips on routes above the match-rate floor.
exclusions:
  - Trips whose scheduled span overlaps a poller outage.
  - Trips on dates with announced service cancellations, if published (shown separately as announced cancellations).
confounders:
  - Vehicles with broken AVL equipment look like ghosts; the per-route match rate and vehicle-level reporting gaps are published.
objections:
  - objection: "The bus ran; its tracker was off."
    response: "Vehicle-level tracker gaps are measured; trips run by vehicles with a known dead tracker that day are shown as 'unobserved', not ghost, and the unobserved share is published."
  - objection: "Our feed was down, not our buses."
    response: "Poller and feed outages are excluded from the denominator and published as uptime."
  - objection: "We announced that cancellation."
    response: "Announced cancellations are split out when MATA publishes them; unannounced missed trips are the headline."
---

## Definition

Of the buses scheduled to serve the stops near you, how many never appeared?

## Change log

- 0.1 — first draft from design plan 6.1.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
