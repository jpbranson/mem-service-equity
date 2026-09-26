---
id: outage_events_per_year
pipeline: mlgw
title: Power outage events affecting the area per year
version: "0.1"
status: draft
unit: events_per_year
formula: >
  count(distinct outage events whose footprint intersects the area during the
  window) scaled to 12 months, with an exact Poisson interval. An event is a
  connected chain of overlapping outage records across consecutive polls.
windows: [12m]
geographies: [citywide, zcta, council_district, outage_polygon]
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
    primary: "any event with >= 1 customer affected"
    alternatives: [">= 10 customers affected", ">= 5 minutes duration"]
    arbitrary: true
inclusions:
  - Events observed by the poller; storm and non-storm shown together and separately.
exclusions:
  - Planned outages, if the source marks them.
confounders:
  - Tree canopy and overhead vs underground lines differ by neighborhood and are real drivers, not measurement error.
objections:
  - objection: "One outage re-drawn across polls is counted as several."
    response: "Events are chains of overlapping polygons across consecutive polls; the segmentation rule is tested by hand on real storm days."
  - objection: "The poller missed outages during storms when our map was slow."
    response: "Missed polls are logged; storms with more than 10% missed polls are flagged in the UI."
  - objection: "SAIFI already measures this."
    response: "SAIFI is citywide; this is the neighborhood breakdown, reconciled against the published SAIFI."
---

## Definition

How many times a year does the power go out in your area?

**Blocked from publishing** until the poller has six months of history
including at least one significant weather event (plan 6.2).

**Revision needed before review (DECISIONS.md H19):** the outage map
publishes one point per outage with a stable `OUTAGE_NO`, not polygons.
Event segmentation and the address join below must be restated in those
terms.

## Change log

- 0.1 — first draft from design plan 6.2.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
