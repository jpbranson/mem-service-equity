---
id: restoration_vs_estimate
pipeline: mlgw
title: Actual restoration time vs. first published estimate
version: "0.1"
status: draft
unit: minutes
formula: >
  Per outage event: actual restoration time - first published estimated
  restoration time (ETR). Area metrics: median of that difference (bootstrap
  interval) and share of events restored by the first ETR (Wilson interval).
windows: [12m]
geographies: [citywide, zcta, council_district]
min_n: 20
promise:
  kind: official
  text: When power goes out, it is restored by the estimated time shown on the outage map.
  source_url: ""
thresholds:
  - name: reference estimate
    primary: "first published ETR"
    alternatives: ["ETR shown 60 minutes after outage start", "final ETR before restoration"]
    arbitrary: true
inclusions:
  - Events with at least one ETR and an observed restoration (disappearance from the map, confirmed by two consecutive polls).
exclusions:
  - Events whose restoration falls in a poller gap longer than 30 minutes (restoration time unknown).
confounders:
  - Major storms produce global ETRs rather than per-outage estimates.
objections:
  - objection: "Estimates are revised as crews assess damage; the first one is a placeholder."
    response: "The first ETR is what residents plan around, so it is the primary reference; later ETRs are published as alternatives."
  - objection: "Disappearing from the map is not the same as restoration."
    response: "Restoration is inferred from two consecutive polls without the outage; the uncertainty of the poll interval is added to the interval."
  - objection: "Storm ETRs are system-wide and not meant per location."
    response: "Storm events are also compared against the citywide median for the same storm (storm comparison metric)."
---

## Definition

When the power goes out near you, is it back by the time the outage map
promised?

## Change log

- 0.1 — first draft from design plan 6.2.
