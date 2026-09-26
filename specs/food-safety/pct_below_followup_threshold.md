---
id: pct_below_followup_threshold
pipeline: food-safety
title: Share of nearby food establishments whose latest routine score requires a follow-up
version: "0.1"
status: draft
unit: proportion
formula: >
  Among active establishments in the area with a routine inspection in the
  last 24 months: count(latest routine score < follow-up threshold) /
  count(establishments).
windows: [24m]
geographies: [citywide, zcta, council_district, h3_8]
min_n: 30
promise:
  kind: official
  text: >
    Food establishments are inspected regularly and pass. Tennessee rules set
    the score below which a follow-up inspection is required.
  source_url: ""
reconciliation:
  measures: [inspection_counts]
  text: >
    Plan 5.5 names weekly inspection counts in WREG's published roundups and a hand
    spot-check of scores against the state site. WREG is not an official source, so an
    official count (TDH or the Shelby County Health Department) is still to be identified.
thresholds:
  - name: follow-up threshold
    primary: "the state's follow-up score (confirm and cite; see docs/research/food-safety.md)"
    alternatives: ["score < 80", "score < 85"]
    arbitrary: false
inclusions:
  - Establishments with a stable establishment ID and an accepted geocode.
  - Routine inspections only; follow-up and complaint inspections do not set the "latest routine score".
exclusions:
  - Establishments with no routine inspection in 24 months (reported in pct_overdue_inspection instead).
  - Establishment types not scored on the 100-point scale (if any), listed in the pipeline config.
confounders:
  - Inspector-to-inspector variation; areas served by one inspector may differ systematically.
  - A single bad day skews a small area; minimum n and intervals apply.
objections:
  - objection: "Scores are point-in-time; a restaurant that failed once and was fixed the next week is counted as failing."
    response: "The metric uses the latest routine inspection; the per-establishment view shows the follow-up result beside it, and reinspection rate is a separate metric."
  - objection: "Chains and renamed restaurants are double-counted or split."
    response: "Establishments are keyed on a stable ID built from the state permit number where available, else normalized address + name, and the matching is tested against a hand-labelled sample."
  - objection: "Different inspectors score differently."
    response: "Acknowledged as a confounder; if inspector IDs are available, the methodology reports whether area differences persist within inspector."
---

## Definition

Of the restaurants and other food establishments near you, what share failed
to reach the score that avoids a mandatory follow-up at their latest routine
inspection?

## Change log

- 0.1 — first draft from design plan 6.4.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
