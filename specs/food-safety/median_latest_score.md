---
id: median_latest_score
pipeline: food-safety
title: Median latest routine inspection score
version: "0.3"
status: draft
unit: score_0_100
formula: >
  Median of each establishment's latest routine inspection score (last 24
  months) across establishments in the area, with a bootstrap interval.
windows: [24m]
geographies: [citywide, zcta, council_district, h3_8]
min_n: 20
promise:
  kind: official
  text: Establishments pass inspection. Shown against the follow-up threshold (score 70, TDH policy).
  source_url: "https://www.tn.gov/news/2014/2/19/restaurant-inspections-help-keep-tennesseans-healthy.html"
reconciliation:
  measures: [inspection_counts]
  text: >
    Plan 5.5 names weekly inspection counts in WREG's published roundups and a hand
    spot-check of scores against the state site. WREG is not an official source, so an
    official count (TDH or the Shelby County Health Department) is still to be identified.
thresholds: []
inclusions:
  - Establishments with a routine inspection in the last 24 months and an accepted geocode.
exclusions:
  - Follow-up and complaint inspections.
confounders:
  - Establishment mix (fast food vs. full service) differs by area.
  - Inspector variation.
objections:
  - objection: "Scores cluster near the top; a median hides the failing tail."
    response: "That is why pct_below_followup_threshold is the headline metric; the median is context."
  - objection: "Mixing establishment types is unfair."
    response: "Partly handled: only restaurant and auxiliary (bar) permits count, so school, child-care and senior-meal kitchens are not mixed in. No breakdown by seating size is built yet."
  - objection: "Each establishment counts once regardless of size."
    response: "Intentional: the unit is the place a resident might eat, not the volume of meals."
---

## Definition

The typical score of food establishments near you at their latest routine
inspection.

## Change log

- 0.1 — first draft from design plan 6.4.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — first computed version, tested on a synthetic export only; the real export has not arrived (H11). Rules and their sources are in `pipelines/food-safety/config/rules.yml`. The latest routine inspection is the most recent one with a score; ties on the same day take the higher score.
- 0.3, 2026-09-27 — first run on real data: the state portal via the owner's collector (DECISIONS.md D29), inspections since 2025-01-01. Only the Food Service Establishment program counts, and only restaurant and auxiliary (bar) permits: mobile units, school, child-care and senior-meal kitchens, and private homes are left out (`pipelines/food-safety/config/establishment_types.csv`). Windows start no earlier than the first day the data cover, so they are shorter than their nominal length until 2027 (24 months) and 2028 (the 36-month activity window).
