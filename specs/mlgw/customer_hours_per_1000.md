---
id: customer_hours_per_1000
pipeline: mlgw
title: Customer-hours without power per 1,000 customers
version: "0.2"
status: draft
unit: hours_per_1000_customers
formula: >
  For each event, customer-hours = sum over its snapshots of (CUR_CUST_AFF at
  that snapshot x time until the next snapshot), up to the estimated
  restoration time. Area value = sum of customer-hours of events whose point
  lies in the area / customers in the area x 1000. MLGW does not publish
  customers by area, so households inside the city (ACS, D20) stand in as
  the denominator, and the metric says so.
windows: [12m]
geographies: [citywide, zcta, council_district]
min_n: 0
min_population: 1000
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
  - All unplanned events observed by the poller; storm and non-storm shown separately.
exclusions:
  - Planned outages (OUT_CAUSE marks some as "Planned Construction").
  - Areas with fewer than 1,000 residents inside the city (min_population), as for requests_per_1000.
confounders:
  - Households are a proxy for customers. They leave out businesses and count a vacant home as no customer.
  - Customers are attributed to the area of the outage point. An outage covering several areas is credited to one.
  - Customer counts change during an outage as crews restore sections. The snapshot sum follows that; a single count per event would not.
objections:
  - objection: "Your customer counts per area are estimates."
    response: "Yes. The denominator is ACS households inside the city (D20), shown with its margin of error, and the citywide total is reconciled against MLGW's reported SAIDI."
  - objection: "Customer attribution by outage point is imprecise."
    response: "Acknowledged. The point is the only location the map publishes. The IMPACT bucket is published beside each event in the address view, so a reader can see when an outage was large."
  - objection: "Gaps make durations uncertain."
    response: "Customer-hours are computed at both ends of each gap. The lower bound assumes restoration right after the last snapshot showing the outage, the upper bound right before the first snapshot without it. Both bounds are published."
---

## Definition

Across a year, how many hours without power does the average customer near
you experience (scaled per 1,000 customers)?

## Details and edge cases

The event model (start, restoration, reappearance, location) is defined in
`outage_events_per_year`. Customer-hours between two snapshots use the
earlier snapshot's `CUR_CUST_AFF`.

**Open question for the reviewer:** should the denominator be households or
all housing units? Households leave out vacant homes, which have no active
meter; housing units are closer to meters where vacancy is high.

## Change log

- 0.1 — first draft from design plan 6.2.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — restated for point outages (H19). Customer-hours are summed over snapshots of an `OUTAGE_NO` and attributed by the outage point. The denominator is named (ACS households inside the city, D20), with a 1,000-resident floor. Drafted by Claude; needs the H19 and H10 review.
