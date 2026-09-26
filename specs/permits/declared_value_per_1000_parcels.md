---
id: declared_value_per_1000_parcels
pipeline: permits
title: Declared permit value per 1,000 parcels (with median declared value)
version: "0.2"
status: draft
unit: dollars_per_1000_parcels
formula: >
  sum(declared value of permits issued in the window) / count(parcels inside
  the city in the area) x 1000, per category subgroup, with a percentile
  bootstrap interval over permits (2,000 resamples, fixed seed). Robustness
  check, published as variant median_per_permit: the median declared value
  per permit (unit: dollars), with a bootstrap interval. Windows end on the
  last day of the last complete month of data.
windows: [12m, 5y]
geographies: [citywide, zcta, council_district]
min_n: 20
min_parcels: 250
promise:
  kind: comparison
  text: No official standard. Comparison against the citywide value.
  source_url: ""
reconciliation:
  measures: [census_bps_new_residential]
  text: >
    Plan 5.5 and DECISIONS.md D14: new residential building counts for the joint
    Memphis/Shelby jurisdiction against the Census Building Permits Survey (place 99990).
thresholds:
  - name: outlier handling
    primary: "no trimming; total and median shown together"
    alternatives: ["exclude permits above the citywide 99th percentile of declared value in the window: variant excl_top1pct",
                   "cap each declared value at $10M: variant cap_10m"]
    arbitrary: true
inclusions:
  - Issued building permits located inside the city limits with a declared value above zero.
exclusions:
  - Permits with no declared value or a value of zero (53 of 27,501 on 2026-09-25).
  - The same exclusions as permits_per_1000_parcels.
confounders:
  - Declared value is self-reported and generally understated; understatement may differ by applicant type.
  - A single large project dominates a small area. The largest declared value on 2026-09-25 was $1.8 billion, on a commercial alteration permit.
  - Values are nominal dollars.
objections:
  - objection: "Declared value is meaningless; contractors lowball it."
    response: "A standing caveat says so; the median declared value and the permit count are shown beside the total, and the conclusion is only drawn when they agree."
  - objection: "One hospital expansion makes a ZIP look like a boom town."
    response: "The trimmed and capped alternatives are published beside the primary series."
  - objection: "Inflation distorts the 5-year window."
    response: "Not yet handled: values are nominal. Areas are compared over the same window, so inflation affects each area in proportion to when its spending happened. A constant-dollar version (CPI-U) is not built."
---

## Definition

How much money (as declared on permits) is going into building work around
here, relative to the number of properties?

## Change log

- 0.1 — first draft from design plan 6.5.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — first computed version: the City's DPD layer only (D24); variants named (excl_top1pct, cap_10m, median_per_permit); 250-parcel floor; windows end at the last complete month; unit name. The earlier promise of constant dollars and an address-level list of the largest permits is withdrawn until built.
