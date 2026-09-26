---
id: ghost_bus_rate
pipeline: mata
title: Share of scheduled trips that never showed up
version: "0.2"
status: draft
unit: proportion
formula: >
  Among measurable scheduled trips (GTFS version in force; the poller covered
  the trip's whole scheduled span plus the tolerance on each side), leaving
  out unobserved blocks: count(ghost trips) / count(observed + ghost trips).
  A trip is observed if a vehicle reported on its trip_id within the span
  plus the tolerance. A ghost trip was not reported although a vehicle
  reported on another trip of the same block that day. The block was out,
  so this trip did not run. If nothing from a block reported all day, its
  trips are unobserved (possibly a dead tracker); they are left out, and
  their count is published in validation.
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
  - "Measurable scheduled trips on every route. The match-rate floor
    applies to on_time_pct, not here: the ghost rate is itself close to the
    complement of the match rate, so a floor would hide exactly the routes
    that miss trips."
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

## Details

The stop and H3-cell views count a ghost trip at every stop it was scheduled
to serve. Matching, service date and measurability are as in on_time_pct.
Announced cancellations are not yet split out: the Alerts feed is archived
but free text.

## Change log

- 0.1 — first draft from design plan 6.1.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — first computed version: measurability defined by poller coverage; ghost versus unobserved by block; the match-rate floor no longer applies to this metric. Variants tolerance_10m and tolerance_30m.
