---
type: Operations
title: What passes the publish gate, and who signed it
description: Five metrics (three for 311, two for permits) pass the publish gate since 2026-10-06; Claude froze their specs and audited them at the owner's direction (D33), and no person has reviewed them.
tags: [publication, publish-gate, audit, specs, d33]
status: draft
generated: { by: claude-code/claude-fable-5-1, at: 2026-10-06T16:10:00-05:00 }
stale_after: 2027-01-06T00:00:00-06:00
sources:
  - id: decisions
    resource: ../../DECISIONS.md
    title: DECISIONS.md D22, D23, D33, H3, H7, H8 and H10
    last_modified: 2026-10-06T16:03:24-05:00
  - id: gate
    resource: ../../packages/memequity/R/publish.R
    title: The publish gate and the audit checks
    last_modified: 2026-10-06T16:02:18-05:00
  - id: audit-311
    resource: ../../pipelines/311/audits/README.md
    title: The 311 audit of 2026-10-06
    last_modified: 2026-10-06T16:02:18-05:00
  - id: audit-permits
    resource: ../../pipelines/permits/audits/README.md
    title: The permits audit of 2026-10-06
    last_modified: 2026-10-06T16:02:18-05:00
  - id: evidence-311
    resource: ../../pipelines/311/tests/independent/audit_evidence.py
    title: Evidence script for the 311 audit
    last_modified: 2026-10-06T16:02:18-05:00
  - id: trace-permits
    resource: ../../pipelines/permits/tests/independent/trace_audit.py
    title: Independent trace for the permits audit
    last_modified: 2026-10-06T16:02:18-05:00
---

# State as of 2026-10-06

Five metrics pass all six publication conditions:[^decisions]

| Pipeline | Metric | Spec version |
|---|---|---|
| 311 | `median_business_days_to_close` | 0.1 |
| 311 | `reopen_rate` | 0.1 |
| 311 | `requests_per_1000` | 0.2 |
| permits | `permits_per_1000_parcels` | 0.3 |
| permits | `declared_value_per_1000_parcels` | 0.2 |

Every other spec is a draft. `pct_within_target` has no official on-time
figure, `closed_without_action_rate` waits on the disposition audit, and
`demolition_to_new_ratio` is computed only from a snapshot the audit did
not cover.[^decisions]

# Who signed

The plan gives the spec freeze and the audit to a person. On 2026-10-06 the
owner delegated both, for 311 and permits, to Claude, which also wrote the
pipelines. No person has reviewed a spec or traced a record. The
independent reviewer (H7) and the agency previews (H8) are still
open.[^decisions]

Three things keep that visible:
- every row of both audit sheets names Claude as the
  auditor;[^audit-311][^audit-permits]
- `committed_audit()` reads the auditor from the newest sheet, and the
  generated methodology page prints the name;[^gate]
- D33 lists the judgment calls made in the freeze, for the owner or a
  reviewer to overturn.[^decisions]

The gate does not know about H7 or H8. Once a spec is frozen and an audit is
committed, the next deploy publishes the metric.[^gate][^decisions]

# How the audits were done

Each audit took the 100 records its pipeline drew on the 2026-10-06 run and
checked them with code that shares nothing with the R pipeline:

- **311:** each request was fetched again and its dates, business days and
  geography recomputed. Then the City's own date, ZIP code and council
  district fields, a Census geocode of the street address, and the number of
  requests sharing the exact close time were compared with the pipeline's
  values.[^evidence-311] The published ZIP-code rows the records count in
  were recomputed from a fresh fetch of each request type: 534 of 534
  matched.[^audit-311]
- **Permits:** each permit was fetched again, its category was read a
  second way from the permit number, and its address was
  geocoded.[^trace-permits] The auditor read every sampled permit's
  description against its category. All 3,936 published count and value
  rows were recomputed from a fresh fetch and matched.[^audit-permits]

The scripts gather evidence and never fill in a check column.[^evidence-311][^trace-permits]

# What the audits found

- At least 23,684 requests were closed on 2025-09-22 in batches that share a
  close time to the second. Three sampled requests were among them. Their
  close date is not when the work was done. No window published on
  2026-10-06 contains that day, and both timing specs now list mass closures
  as a confounder.[^audit-311][^decisions]
- On three sampled requests the City's `REPORTED_DATE` is one to three days
  before the record's creation, which the metric counts from.[^audit-311]
- One of five near-duplicates is more likely a second missed collection a
  week after the first than a second report: the 7-day rule (D6) spans the
  weekly collection cycle.[^audit-311]
- The City codes one renovation as new construction, and the pipeline
  follows the code.[^audit-permits]

# How to apply

- A frozen spec's text may be corrected without a version bump only when no
  computed value changes, and its change log must say so. A definition
  change bumps MAJOR, needs a new golden file, and needs the independent
  recomputation updated.[^decisions]
- A new audit goes in `pipelines/<pipeline>/audits/` as
  `audit_sample_<date>.csv`; the newest file name wins. The gate needs 100
  rows, every check answered, an auditor on every row and a note on every
  "no".[^gate]
- Before the permits `demolition` subgroup or the demolition ratio is
  published, audit a sample of the Data Midsouth snapshot.[^audit-permits]
- Do not describe these five metrics as reviewed or audited by a person.

[^decisions]: DECISIONS.md D22, D23, D33, H3, H7, H8 and H10
[^gate]: The publish gate and the audit checks
[^audit-311]: The 311 audit of 2026-10-06
[^audit-permits]: The permits audit of 2026-10-06
[^evidence-311]: Evidence script for the 311 audit
[^trace-permits]: Independent trace for the permits audit
