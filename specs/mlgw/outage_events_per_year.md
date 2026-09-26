---
id: outage_events_per_year
pipeline: mlgw
title: Power outage events affecting the area per year
version: "0.2"
status: draft
unit: events_per_year
formula: >
  count(distinct outage events whose point lies in the area and that started
  in the window), scaled to 12 months, with an exact Poisson interval. An event
  is one OUTAGE_NO followed across the poller's snapshots (see Details). For
  an address, the area is its H3 resolution-9 cell plus the six neighbours
  (DECISIONS.md D16), as for 311.
windows: [12m]
geographies: [citywide, zcta, council_district, h3_9]
min_n: 0
promise:
  kind: official
  text: Power stays on.
  source_url: ""
reconciliation:
  measures: [saidi, saifi]
  text: >
    Plan 5.5: event counts and customer-hours against the reliability indices (SAIDI,
    SAIFI) in MLGW's annual reports or TVA filings.
thresholds:
  - name: minimum event size
    primary: "any event with >= 1 customer affected at some snapshot"
    alternatives: [">= 10 customers affected at some snapshot", "lasting >= 5 minutes"]
    arbitrary: true
inclusions:
  - Unplanned events observed by the poller. Storm and non-storm events are shown together and separately.
exclusions:
  - Planned outages. The map marks some in OUT_CAUSE (seen as "Planned Construction"); they are counted in a separate series.
  - Events whose point is outside Shelby County (bad coordinates, counted in validation).
confounders:
  - Tree canopy, and overhead versus underground lines, differ by neighborhood. They are real drivers, not measurement error.
  - An outage is placed at one point. A large outage (IMPACT "A Neighborhood") can cover homes in a neighboring area that is not credited with it.
  - Counts are not normalized by area size or customers. Larger areas have more events; the per-customer view is customer_hours_per_1000.
objections:
  - objection: "One outage re-drawn across polls is counted as several."
    response: "An event is keyed on OUTAGE_NO, which the map keeps stable across snapshots. An OUTAGE_NO that reappears within 2 hours of vanishing continues the same event and is flagged; a hand check on real storm days tests both rules."
  - objection: "The poller missed outages during storms when our map was slow."
    response: "Every poll attempt is logged, including failures. Outages that start and end inside a gap are invisible, so storm windows with more than 10% missed polls are flagged in the UI, and uptime is published."
  - objection: "SAIFI already measures this."
    response: "SAIFI is citywide; this is the neighborhood breakdown, reconciled against the published SAIFI."
---

## Definition

How many times a year does the power go out in your area?

**Blocked from publishing** until the poller has six months of history
including at least one significant weather event (plan 6.2).

## Details and edge cases

This event model is shared by all three MLGW specs (DECISIONS.md H19):
- **Event.** One `OUTAGE_NO`. The map shows one point per active outage and
  drops it when restored. The poller stores every 5-minute snapshot
  (D15).
- **Start.** The outage's `TIME_STAMP`. It is local time with no zone, so
  it is read as America/Chicago. In the repeated hour when daylight saving
  ends, it is read as the first (CDT) occurrence.
- **Restoration.** The event is restored when it is absent from two
  consecutive successful polls. The restoration time lies between the last
  poll that showed it and the first that did not. The midpoint is used, and
  that span is carried as uncertainty. If polls failed in between (a gap),
  the span covers the gap.
- **Reappearance.** An `OUTAGE_NO` that comes back within 2 hours continues
  the same event and is flagged. Later, it starts a new one.
- **Location.** The first point observed for the `OUTAGE_NO`. The area is
  the one that point falls in, under the same boundary rule as other
  pipelines (D8).
- **Overlapping runs.** Overlapping poller runs (D15) produce duplicate
  snapshots; they are removed by poll time before events are built.

## Change log

- 0.1 — first draft from design plan 6.2.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — restated for point outages (H19). An event is an `OUTAGE_NO` chain, not a chain of overlapping polygons. The area join is by the outage point, with the D16 disk for addresses instead of `outage_polygon`. Planned outages are excluded using `OUT_CAUSE`. Drafted by Claude; needs the H19 and H10 review.
