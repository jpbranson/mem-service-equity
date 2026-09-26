---
id: reinspection_rate
pipeline: food-safety
title: Share of inspections that were follow-ups
version: "0.2"
status: draft
unit: proportion
formula: >
  count(follow-up inspections) / count(routine + follow-up inspections) over
  inspections of establishments in the area during the window.
windows: [24m]
geographies: [citywide, zcta, council_district, h3_8]
min_n: 30
promise:
  kind: comparison
  text: No official target. Compared against the citywide share for the same window.
  source_url: ""
reconciliation:
  measures: [inspection_counts]
  text: >
    Plan 5.5 names weekly inspection counts in WREG's published roundups and a hand
    spot-check of scores against the state site. WREG is not an official source, so an
    official count (TDH or the Shelby County Health Department) is still to be identified.
thresholds: []
inclusions:
  - Routine and follow-up inspections of establishments with an accepted geocode.
exclusions:
  - Complaint, pre-opening and other non-routine inspection types (listed in the pipeline config).
confounders:
  - Follow-up scheduling depends on inspector workload as well as on the establishment.
objections:
  - objection: "Complaint inspections are how problems are found; excluding them hides them."
    response: "Complaint inspections are counted separately on the establishment view. They are excluded here because complaint volume reflects resident engagement, the same confound as 311 volume."
  - objection: "Follow-up codes are inconsistent in the state system."
    response: "The inspection-type mapping is a spec artifact tested against a hand-labelled sample; unmapped types fail validation."
  - objection: "A higher rate may mean more diligent inspection, not worse food safety."
    response: "It is labelled a comparison and shown beside the score metric, never alone."
---

## Definition

Of the inspections near you, how many were return visits because the first
one went badly?

## Change log

- 0.1 — first draft from design plan 6.4.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — first computed version, tested on a synthetic export only; the real export has not arrived (H11). Rules and their sources are in `pipelines/food-safety/config/rules.yml`.
