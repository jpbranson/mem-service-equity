---
id: closed_without_action_rate
pipeline: "311"
title: Share of requests closed without work performed
version: "0.1"
status: draft
unit: proportion
formula: >
  count(closed requests whose disposition maps to 'no work performed') /
  count(closed requests), per request type, over deduplicated requests closed
  in the window.
windows: [90d, 12m]
geographies: [citywide, zcta, council_district, h3_9]
min_n: 30
promise:
  kind: comparison
  text: No official standard. Compared against the citywide rate for the same type and window.
  source_url: ""
reconciliation:
  measures: [requests_created]
  text: >
    Service request counts the City publishes, recomputed from the same 311 records
    (DECISIONS.md D22). This checks the fetch, the request-type mapping and the date
    handling behind this metric. It does not check timing or dispositions; the manual
    audit (H3) covers those.
thresholds:
  - name: disposition mapping
    primary: "mapping established by the manual disposition audit (DECISIONS.md H4)"
    alternatives: ["strict: only explicit no-action codes", "broad: also unable-to-locate and referred-elsewhere codes"]
    arbitrary: true
inclusions:
  - Deduplicated closed requests of the given type.
exclusions:
  - Requests closed as duplicates by the city (handled by deduplication, not counted as no action).
confounders:
  - Some no-action closures are legitimate (already fixed, private property, not city responsibility).
objections:
  - objection: "Many closures without work are correct: the problem was on private property or already fixed."
    response: "The metric is labelled a comparison, not a compliance measure, and is published under a strict and a broad mapping; what matters is whether the rate differs between areas for the same request type."
  - objection: "You don't know what our status codes mean."
    response: "The metric is not defined until a few hundred closed requests have been read by hand and the code mapping published (plan 5.6). The mapping is a spec artifact open to correction."
  - objection: "Resolution notes are free text and inconsistent across crews."
    response: "Only structured status and disposition fields are used; free text informs the audit, not the metric."
---

## Definition

Of the requests closed near you, what share were closed without the city
doing the work?

**Blocked:** this metric cannot move past draft until the manual
disposition audit (DECISIONS.md H4) is done. The mapping will live in
`pipelines/311/config/disposition_map.csv`, which does not exist yet. The
worksheet for the audit is generated on every run
(`audit/disposition_worksheet_<date>.csv`).

## Change log

- 0.1 — placeholder definition from design plan 6.3.
- 0.1, 2026-09-25 — added the `reconciliation` block (DECISIONS.md D22); corrected file references. No change to the definition.
