---
id: demolition_to_new_ratio
pipeline: permits
title: Demolitions per new-construction permit
version: "0.2"
status: draft
unit: ratio
formula: >
  count(demolition permits in window) / count(new construction permits issued
  in window). Interval from the conditional binomial: with D demolitions and N
  new, p = D/(D+N) gets a Wilson interval, transformed to the ratio p/(1-p).
  Demolitions come from the Data Midsouth snapshot (DECISIONS.md D30) and are
  dated by their latest status; new construction comes from the City's DPD
  layer, residential and commercial, dated by issue. Windows end on the
  earlier of the two sources' data-through dates.
windows: [12m, 5y]
geographies: [citywide, zcta, council_district]
min_n: 20
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
  - Demolition permits in the Data Midsouth snapshot (D30), one per record ID, located inside the city limits.
  - New construction permits from the City's DPD layer, residential and commercial, located inside the city limits.
exclusions:
  - Interior demolition permits that are part of a renovation (mapped to renovation).
  - Areas with no new construction in the window, where the ratio is undefined (suppressed; the count of demolitions is in the permits_per_1000_parcels demolition subgroup).
confounders:
  - Demolition of blighted structures can be a precursor to investment, not a sign of abandonment.
  - City-initiated blight demolitions may not appear as ordinary permits. Coverage has not been checked against the City's blight-demolition records.
  - The two sides are dated differently. The snapshot has no issue date, so a demolition still open is dated by its issue and a closed one by its completion (a median of 201 days after issue for the snapshot's other permit types). In a steady state this shifts which window a demolition falls in, not how many fall in a window of a given length.
objections:
  - objection: "Blight demolition is the city doing its job, not abandonment."
    response: "Acknowledged in the panel text. The snapshot does not mark city-initiated demolitions, so they cannot be shown separately yet."
  - objection: "Ratios explode when new construction is near zero."
    response: "Computed on D/(D+N) with a Wilson interval and suppressed when D+N < 20 or N = 0; the raw counts are always shown."
  - objection: "Demolition and new construction on the same lot are one project."
    response: "Not handled yet: the DPD layer has no parcel ID to pair them on. A same-lot pairing is still to be built."
---

## Definition

For every new building permitted around here, how many buildings were
permitted to be torn down?

## Change log

- 0.1 — first draft from design plan 6.5.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.1, 2026-09-25 — marked `blocked` until a source of demolition permits exists (D24, H21). No change to the definition.
- 0.1, 2026-09-25 — confounder text: coverage can no longer be checked against Data Midsouth (D24). No change to the definition.
- 0.2, 2026-09-27 — first computed version: demolitions from the owner's Data Midsouth snapshot (D30), dated by their latest status; new construction from the DPD layer; suppressed when there is no new construction; windows end on the earlier data-through date. The same-lot pairing and separate city-initiated demolitions promised in 0.1 are withdrawn until built.
