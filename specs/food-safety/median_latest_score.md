---
id: median_latest_score
pipeline: food-safety
title: Median latest routine inspection score
version: "0.1"
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
  text: Establishments pass inspection. Shown against the follow-up threshold.
  source_url: ""
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
    response: "If the source exposes establishment type, the area view breaks the median down by type."
  - objection: "Each establishment counts once regardless of size."
    response: "Intentional: the unit is the place a resident might eat, not the volume of meals."
---

## Definition

The typical score of food establishments near you at their latest routine
inspection.

## Change log

- 0.1 — first draft from design plan 6.4.
