---
id: requests_per_1000
pipeline: "311"
title: 311 requests per 1,000 residents (demand, not performance)
version: "0.2"
status: draft
unit: count_per_1000
formula: >
  count(deduplicated primary requests inside the city opened in the window)
  / ACS 5-year residents of the part of the area inside the city x 1000, per
  request type, with an exact Poisson interval on the count. Not annualized:
  a 90-day rate and a 12-month rate are different quantities.
windows: [90d, 12m]
geographies: [citywide, zcta, council_district, super_district, reference_neighborhood]
min_n: 0
min_population: 1000
promise:
  kind: comparison
  text: Not a performance measure. Shown separately and labelled as demand.
  source_url: ""
reconciliation:
  measures: [requests_created]
  text: >
    Service request counts the City publishes, recomputed from the same 311 records
    (DECISIONS.md D22). This checks the fetch, the request-type mapping and the date
    handling behind this metric. It does not check timing or dispositions; the manual
    audit (H3) covers those.
thresholds: []
inclusions:
  - Deduplicated primary requests; raw counts published alongside.
exclusions:
  - Geographies without an ACS population denominator (e.g. hex cells).
  - Areas with fewer than 1,000 residents inside the city (min_population),
    such as the airport ZIP code or the part of a suburban ZIP code that
    crosses the city line. There a handful of requests gives a meaningless
    rate. This is a suppression floor like min_n, not a threshold that
    changes any published value.
confounders:
  - Resident engagement, awareness of 311 and internet access drive volume at least as much as conditions do.
  - The interval covers only the randomness of the count. The population is
    itself a survey estimate with a margin of error, shown with the area's
    demographics (DECISIONS.md D20).
objections:
  - objection: "High request volume means people are engaged, not that services are worse."
    response: "Agreed. The UI never presents volume as quality, places it in a separate demand section, and the methodology says why."
  - objection: "Population denominators are wrong for downtown and commercial areas."
    response: "The rate is shown with the raw count and the denominator; ZCTAs with small residential populations are flagged."
  - objection: "City crews file requests too, inflating some areas."
    response: "If the source distinguishes internal from resident-originated requests, the metric is split by origin (see docs/research/311-permits-districts.md)."
---

## Definition

How many 311 requests of this type come from around here, per 1,000 people?
This measures demand, not how well the city responds.

## Change log

- 0.1 — first draft from design plan 6.3.
- 0.2 — denominator defined as residents inside the city (ACS 2020–2024,
  apportioned through 2020 blocks, D20); added super districts and reference
  neighborhoods; added the 1,000-resident floor.
- 0.2, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22); corrected file references. No change to the definition.
