---
id: demolition_to_new_ratio
pipeline: permits
title: Demolitions per new-construction permit
version: "0.1"
status: draft
unit: ratio
formula: >
  count(demolition permits issued in window) / count(new construction permits
  issued in window). Interval from the conditional binomial: with D
  demolitions and N new, p = D/(D+N) gets a Wilson interval, transformed to
  the ratio p/(1-p).
windows: [12m, 5y]
geographies: [citywide, zcta, council_district]
min_n: 20
blocked: "No permitted source of demolition permits: Data Midsouth forbids automated access and the City's DPD layer has none (DECISIONS.md D24, H21)."
promise:
  kind: comparison
  text: No official standard. More demolition than new construction suggests disinvestment; compared against citywide.
  source_url: ""
reconciliation:
  measures: [census_bps_new_residential]
  text: >
    Plan 5.5 and DECISIONS.md D14: new residential building counts for the joint
    Memphis/Shelby jurisdiction against the Census Building Permits Survey (place 99990).
thresholds: []
inclusions:
  - Issued demolition and new-construction building permits, residential and commercial (also shown separately).
exclusions:
  - Interior demolition permits that are part of a renovation (mapped to renovation).
confounders:
  - Demolition of blighted structures can be a precursor to investment, not a sign of abandonment.
  - City-initiated blight demolitions may not appear as ordinary permits; data coverage is checked against the Data Midsouth demolition dataset.
objections:
  - objection: "Blight demolition is the city doing its job, not abandonment."
    response: "Acknowledged in the panel text; where the source distinguishes city-initiated demolitions they are shown separately."
  - objection: "Ratios explode when new construction is near zero."
    response: "Computed on D/(D+N) with a Wilson interval and suppressed when D+N < 20; the raw counts are always shown."
  - objection: "Demolition and new construction on the same lot are one project."
    response: "Pairs on the same parcel within 24 months are shown as redevelopment in the address view; the ratio is published with and without such pairs."
---

## Definition

For every new building permitted around here, how many buildings were
permitted to be torn down?

## Change log

- 0.1 — first draft from design plan 6.5.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.1, 2026-09-25 — marked `blocked` until a source of demolition permits exists (D24, H21). No change to the definition.
