---
id: permits_per_1000_parcels
pipeline: permits
title: Building permits per 1,000 parcels
version: "0.1"
status: draft
unit: count_per_1000
formula: >
  count(permits issued in the window, by category) / count(parcels in the
  area) x 1000, with an exact Poisson interval. Categories: new construction,
  renovation (alteration + addition), demolition; residential vs commercial.
windows: [12m, 5y]
geographies: [citywide, zcta, council_district]
min_n: 0
promise:
  kind: comparison
  text: No official standard. Is the neighborhood being maintained and invested in, compared with the city as a whole?
  source_url: ""
reconciliation:
  measures: [census_bps_new_residential]
  text: >
    Plan 5.5 and DECISIONS.md D14: new residential building counts for the joint
    Memphis/Shelby jurisdiction against the Census Building Permits Survey (place 99990).
thresholds:
  - name: permit category mapping
    primary: "category map in pipelines/permits/config/category_map.csv, tested against a hand-labelled sample"
    alternatives: ["exclude minor permits (declared value < $5,000)", "residential only"]
    arbitrary: true
inclusions:
  - Permits issued (not merely applied for) in the window, deduplicated across the city and Data Midsouth sources.
exclusions:
  - Trade-only permits (electrical, plumbing, mechanical) unless attached to a building permit, since they measure a different thing.
  - Permits without a parcel or located address (counted as unlocated).
confounders:
  - Permits lead construction by months; the trend view is labelled accordingly.
  - Unpermitted work is invisible and is plausibly more common where enforcement is weaker.
objections:
  - objection: "Permit counts mix a new roof with a new tower."
    response: "Counts are shown by category, beside declared value, and the minor-permit alternative is published."
  - objection: "Parcels are a poor denominator where lots are vacant or consolidated."
    response: "Parcel counts come from the Assessor and are versioned annually; per-parcel and raw counts are shown together."
  - objection: "The two permit sources overlap and you double count."
    response: "Records are matched across sources on permit number, then address and date; the authoritative source per field is documented and the overlap is reported in validation."
---

## Definition

How much permitted building activity (new construction, renovation,
demolition) happens around here, relative to the number of properties?

## Change log

- 0.1 — first draft from design plan 6.5.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
