---
id: requests_per_1000
pipeline: "311"
title: 311 requests per 1,000 residents (demand, not performance)
version: "0.1"
status: draft
unit: count_per_1000
formula: >
  count(deduplicated requests opened in the window) / ACS 5-year population
  x 1000, per request type, with an exact Poisson interval.
windows: [90d, 12m]
geographies: [citywide, zcta, council_district]
min_n: 0
promise:
  kind: comparison
  text: Not a performance measure. Shown separately and labelled as demand.
  source_url: ""
thresholds: []
inclusions:
  - Deduplicated primary requests; raw counts published alongside.
exclusions:
  - Geographies without an ACS population denominator (e.g. hex cells).
confounders:
  - Resident engagement, awareness of 311 and internet access drive volume at least as much as conditions do.
objections:
  - objection: "High request volume means people are engaged, not that services are worse."
    response: "Agreed. The UI never presents volume as quality, places it in a separate demand section, and the methodology says why."
  - objection: "Population denominators are wrong for downtown and commercial areas."
    response: "The rate is shown with the raw count and the denominator; ZCTAs with small residential populations are flagged."
  - objection: "City crews file requests too, inflating some areas."
    response: "If the source distinguishes internal from resident-originated requests, the metric is split by origin (see docs/research/311.md)."
---

## Definition

How many 311 requests of this type come from around here, per 1,000 people?
This measures demand, not how well the city responds.

## Change log

- 0.1 — first draft from design plan 6.3.
