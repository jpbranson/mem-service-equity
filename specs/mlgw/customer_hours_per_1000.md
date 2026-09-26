---
id: customer_hours_per_1000
pipeline: mlgw
title: Customer-hours without power per 1,000 customers
version: "0.1"
status: draft
unit: hours_per_1000_customers
formula: >
  sum over events of (customers affected x hours out), attributed to the area
  by outage footprint, / customers served in the area x 1000. If customer
  counts are not exposed, event-hours per area, clearly labelled as such.
windows: [12m]
geographies: [citywide, zcta, council_district]
min_n: 0
promise:
  kind: official
  text: Power stays on. (Neighborhood analogue of SAIDI.)
  source_url: ""
reconciliation:
  measures: [saidi, saifi]
  text: >
    Plan 5.5: event counts and customer-hours against the reliability indices (SAIDI,
    SAIFI) in MLGW's annual reports or TVA filings.
thresholds: []
inclusions:
  - All observed events; storm and non-storm shown separately.
exclusions:
  - Poller gaps (hours in a gap are bounded above and below; both bounds published).
confounders:
  - Customers served per area must be estimated if MLGW does not publish it (housing units from ACS as proxy).
objections:
  - objection: "Your customer counts per area are estimates."
    response: "Yes; the denominator source is shown, and the citywide total is reconciled against MLGW's reported SAIDI."
  - objection: "Customer attribution across polygons is imprecise."
    response: "Customers are attributed proportionally by area overlap; the attribution rule is tested and published."
  - objection: "Gaps make durations uncertain."
    response: "Lower and upper bounds from gap handling are both published."
---

## Definition

Across a year, how many hours without power does the average customer near
you experience (scaled per 1,000 customers)?

**Revision needed before review (DECISIONS.md H19):** the outage map
publishes one point per outage with a stable `OUTAGE_NO`, not polygons.
Event segmentation and the address join below must be restated in those
terms.

## Change log

- 0.1 — first draft from design plan 6.2.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
