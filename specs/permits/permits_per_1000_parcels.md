---
id: permits_per_1000_parcels
pipeline: permits
title: Building permits per 1,000 parcels
version: "0.2"
status: draft
unit: count_per_1000_parcels
formula: >
  count(permits issued in the window, by category) / count(parcels inside the
  city in the area) x 1000, with an exact Poisson interval. Categories: new
  construction, renovation (alteration + addition) and accessory structures,
  each for residential, commercial and both. Demolition is not available
  (DECISIONS.md H21). Windows end on the last day of the last complete month
  of data (the source is refreshed monthly).
windows: [12m, 5y]
geographies: [citywide, zcta, council_district]
min_n: 0
min_parcels: 250
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
    primary: "sector and category maps in pipelines/permits/config/ (sector_map.csv, category_map.csv)"
    alternatives: ["exclude minor permits (declared value under $5,000): variant excl_minor",
                   "residential only: the *_residential subgroups"]
    arbitrary: true
inclusions:
  - Building permits issued (not merely applied for) in the window, from the City's DPD Building Permits layer (new, alteration, addition and accessory permits since January 2021).
  - Permits located inside the city limits.
exclusions:
  - Permits whose location is missing, 0,0 or outside Shelby County (counted as unlocated in the validation report).
  - Permits issued after the last complete month.
  - Demolitions, which are not in the source (DECISIONS.md D24, H21).
confounders:
  - Permits lead construction by months, and some permitted work is never built.
  - Unpermitted work is invisible and is plausibly more common where enforcement is weaker.
  - Parcel counts are the Assessor's 2022 snapshot. An area with new subdivisions since then has more parcels than the denominator shows, which inflates its rate.
objections:
  - objection: "Permit counts mix a new roof with a new tower."
    response: "Counts are shown by category, beside declared value, and the minor-permit alternative is published."
  - objection: "Parcels are a poor denominator where lots are vacant or consolidated."
    response: "Parcel counts come from the Assessor (a 2022 snapshot, with the vintage in the file name); rates are shown with the raw count, and areas with fewer than 250 in-city parcels are suppressed."
  - objection: "The DPD data covers the whole joint city-county jurisdiction, not just Memphis."
    response: "Only permits located inside the city limits are counted in any area; the unlocated share is reported in validation. The reconciliation, by contrast, counts the whole jurisdiction because that is what the Census reports."
---

## Definition

How much permitted building activity (new construction, renovation and
accessory structures) happens around here, relative to the number of
properties?

## Details and edge cases

- Issue dates are local (America/Chicago) calendar dates.
- The source mixes two codings in 2021 (`RES`/`COM` with `NEW`/`ALT`/`ADD`/`ACC`,
  and `Residential`/`Commercial` with `New`/`Alteration`/`Addition`/`Accessory`).
  Both are mapped explicitly, and the run fails on any value that is not.
- Every area with at least one in-city parcel gets a row, including areas
  with no permits: a zero is a result.

## Change log

- 0.1 — first draft from design plan 6.5.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — first computed version. Source limited to the City's DPD layer, because Data Midsouth forbids automated access (D24), so demolition is unavailable (H21). Added the accessory category, the 250-parcel suppression floor, windows ending at the last complete month, and the unit name.
