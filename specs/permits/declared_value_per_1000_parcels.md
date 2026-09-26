---
id: declared_value_per_1000_parcels
pipeline: permits
title: Declared permit value per 1,000 parcels (with median declared value)
version: "0.1"
status: draft
unit: dollars_per_1000
formula: >
  sum(declared value of permits issued in the window) / count(parcels) x
  1000. Robustness check: median declared value per permit, with a bootstrap
  interval. The total uses a bootstrap interval over permits.
windows: [12m, 5y]
geographies: [citywide, zcta, council_district]
min_n: 20
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
    alternatives: ["exclude top 1% of declared values citywide", "cap declared value at $10M"]
    arbitrary: true
inclusions:
  - Issued building permits with a declared value > 0.
exclusions:
  - Permits with no declared value (counted and reported).
confounders:
  - Declared value is self-reported and generally understated; understatement may differ by applicant type.
  - A single large project dominates a small area.
objections:
  - objection: "Declared value is meaningless; contractors lowball it."
    response: "A standing caveat says so; the median declared value and the permit count are shown beside the total, and the conclusion is only drawn when they agree."
  - objection: "One hospital expansion makes a ZIP look like a boom town."
    response: "The trimmed and capped alternatives are published; the address view lists the largest permits individually."
  - objection: "Inflation distorts the 5-year trend."
    response: "The 5-year trend is shown in constant dollars (CPI-U, Memphis MSA where available), and the deflator is documented."
---

## Definition

How much money (as declared on permits) is going into building work around
here, relative to the number of properties?

## Change log

- 0.1 — first draft from design plan 6.5.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
