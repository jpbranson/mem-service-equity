---
id: pct_overdue_inspection
pipeline: food-safety
title: Share of establishments overdue for a routine inspection
version: "0.1"
status: draft
unit: proportion
formula: >
  Among active establishments in the area: count(days since latest routine
  inspection > required interval) / count(establishments), evaluated on the
  data-current-through date.
windows: [current]
geographies: [citywide, zcta, council_district, h3_8]
min_n: 30
promise:
  kind: official
  text: The state requires routine inspections at a set frequency (confirm the rule; see docs/research/food-safety.md).
  source_url: ""
thresholds:
  - name: required interval
    primary: "the state's required frequency, converted to days"
    alternatives: ["required interval + 30 days grace", "required interval + 90 days grace"]
    arbitrary: true
inclusions:
  - Establishments with at least one inspection of any type in the last 36 months (proxy for active).
exclusions:
  - Establishments known to be closed, if the source exposes status.
confounders:
  - Closed establishments that remain in the source look overdue; the active-establishment proxy mitigates but does not eliminate this.
objections:
  - objection: "Frequency is risk-based; low-risk establishments legitimately go longer."
    response: "If the source exposes a risk category, the required interval is per category; otherwise the metric uses the most lenient interval and says so."
  - objection: "Your 'active' list includes closed restaurants."
    response: "Acknowledged; the active proxy is published and the metric is shown with the grace-period alternatives."
  - objection: "Recent inspections may not yet be posted online."
    response: "Posting lag is measured by the freshness check and the grace-period variants absorb it."
---

## Definition

Of the food establishments near you, how many are past due for their
regular inspection?

## Change log

- 0.1 — first draft from design plan 6.4.
