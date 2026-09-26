---
id: restoration_vs_estimate
pipeline: mlgw
title: Actual restoration time vs. first published estimate
version: "0.2"
status: draft
unit: minutes
formula: >
  Per event: estimated restoration time (see outage_events_per_year) minus the
  first non-empty EST_REPAIR_TIME observed for its OUTAGE_NO. Area metrics
  over events whose point lies in the area: the median of that difference
  (bootstrap interval) and the share of events restored by their first
  estimate (Wilson interval). An event counts as restored by the estimate
  only if the latest possible restoration time is on or before it.
windows: [12m]
geographies: [citywide, zcta, council_district]
min_n: 20
promise:
  kind: official
  text: When power goes out, it is restored by the estimated time shown on the outage map.
  source_url: ""
reconciliation:
  measures: [saidi, saifi]
  text: >
    Plan 5.5: event counts and customer-hours against the reliability indices (SAIDI,
    SAIFI) in MLGW's annual reports or TVA filings.
thresholds:
  - name: reference estimate
    primary: "first published ETR"
    alternatives: ["ETR shown 60 minutes after outage start", "final ETR before restoration"]
    arbitrary: true
inclusions:
  - Unplanned events with at least one ETR and an observed restoration (absent from two consecutive successful polls).
exclusions:
  - Events whose restoration falls in a poller gap longer than 30 minutes (restoration time unknown).
  - Planned outages (OUT_CAUSE marks some as "Planned Construction").
confounders:
  - Major storms produce global ETRs rather than per-outage estimates.
  - ETRs are revised in place on the map; only estimates the poller saw are known, so an estimate shown and withdrawn within 5 minutes is missed.
objections:
  - objection: "Estimates are revised as crews assess damage; the first one is a placeholder."
    response: "The first ETR is what residents plan around, so it is the primary reference; later ETRs are published as alternatives."
  - objection: "Disappearing from the map is not the same as restoration."
    response: "Restoration is inferred from two consecutive successful polls without the outage. The on-time test uses the latest possible restoration time, so poll timing never flatters the result."
  - objection: "Storm ETRs are system-wide and not meant per location."
    response: "Storm events are also compared against the citywide median for the same storm (storm comparison metric)."
---

## Definition

When the power goes out near you, is it back by the time the outage map
promised?

## Details and edge cases

The event model is defined in `outage_events_per_year`.
- `EST_REPAIR_TIME` is local time with no zone and is read as
  America/Chicago.
- An empty or blank estimate is not an estimate.
- The difference in minutes uses the midpoint restoration time; the
  on-time share uses the latest possible restoration time.

## Change log

- 0.1 — first draft from design plan 6.2.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22). No change to the definition.
- 0.2, 2026-09-25 — restated for point outages (H19). Estimates and restoration are tracked per `OUTAGE_NO`, and the area join is by the outage point. The on-time test uses the latest possible restoration time. Planned outages are excluded. Drafted by Claude; needs the H19 and H10 review.
