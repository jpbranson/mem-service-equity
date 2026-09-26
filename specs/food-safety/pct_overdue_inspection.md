---
id: pct_overdue_inspection
pipeline: food-safety
title: Share of establishments overdue for a routine inspection
version: "0.2"
status: draft
unit: proportion
formula: >
  Among active establishments in the area: count(days since latest routine
  inspection > required interval) / count(establishments), evaluated on the
  data-current-through date. The clock starts at the latest routine or
  pre-opening inspection; an active establishment with neither is measured
  from its first inspection. The required interval is 6 calendar months.
  Rows carry the 36-month activity window as their window.
windows: [current]
geographies: [citywide, zcta, council_district, h3_8]
min_n: 30
promise:
  kind: official
  text: The state inspects each food establishment at least once every 6 months (Tenn. Comp. R. & Regs. 1200-23-01-.08(4)(a)1).
  source_url: "https://www.law.cornell.edu/regulations/tennessee/Tenn-Comp-R-Regs-1200-23-01-.08"
reconciliation:
  measures: [inspection_counts]
  text: >
    Plan 5.5 names weekly inspection counts in WREG's published roundups and a hand
    spot-check of scores against the state site. WREG is not an official source, so an
    official count (TDH or the Shelby County Health Department) is still to be identified.
thresholds:
  - name: required interval
    primary: "6 calendar months after the clock inspection"
    alternatives: ["plus 30 days' grace: variant grace_30d", "plus 90 days' grace: variant grace_90d"]
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
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — first computed version, tested on a synthetic export only; the real export has not arrived (H11). Rules and their sources are in `pipelines/food-safety/config/rules.yml`. Defined the clock inspection and the 6-month interval from the rule.
