---
type: Collection Method
title: Owner-collected sources
description: Food inspections (state portal) and demolition permits (Data Midsouth) come from the owner's own collectors outside the repo; the pipelines only read the files (D29, D30).
tags: [collection, food-safety, permits, demolitions, d11]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-04T20:50:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: session-2026-09-27
    resource: "The owner's direction in a Claude Code session on 2026-09-27, kept in Claude's private project memory until it was moved here on 2026-10-04"
    title: Owner's direction on the owner-collected sources
    author: human:jpbranson
  - id: decisions
    resource: ../../DECISIONS.md
    title: DECISIONS.md D11, D24, D29 and D30
    last_modified: 2026-10-01T21:20:45-05:00
  - id: permits-research
    resource: ../../docs/research/311-permits-districts.md
    title: "Research: 311, permits, district boundaries"
    last_modified: 2026-09-27T22:38:47-05:00
  - id: fetch-permits
    resource: ../../pipelines/permits/R/fetch.R
    title: Permits fetch
    last_modified: 2026-09-27T22:38:47-05:00
---

# Sources

| Data | Original source | Owner's file (sibling repo) | Read by | Decision |
|---|---|---|---|---|
| Food inspections | Tennessee Department of Health inspection portal | `../tn-health-inspections/data/inspections.csv` | `pipelines/food-safety/run.R --inbox DIR` | D29 |
| Demolition permits | Data Midsouth, "Building and Demolition Permits – Shelby County" | `../mem-demo-permits/shelby_permits.csv` | `pipelines/permits/run.R --demolitions FILE` | D30 |

# Why this repo does not fetch them

Both sites' robots.txt files disallow automated access. The inspection
portal disallows every crawler. Data Midsouth disallows `/api/` and dataset
downloads for every crawler except Googlebot, and its dataset license says
only "See Website Terms of Use" (D24). Under D11 the project does not
scrape either source.[^decisions][^permits-research]

On 2026-09-27, after being shown the robots.txt conflict, the owner made
an exception for each one and directed that the data from their own
collectors be used.[^session-2026-09-27] This repo still fetches nothing
from either source: the permits fetch code says so, and the pipelines take
the owner's files as arguments.[^fetch-permits]

# State as of 2026-09-27

- Food inspections: 18,689 inspections from 2025-01-02 to 2026-09-25. The
  validation report records the input file's md5.
- Demolitions: 2,315 permits after duplicates are removed, with the latest
  status date 2026-07-31. Only demolitions come from this snapshot; the
  City's DPD layer stays the source for every other permit type.
- Both are static snapshots and neither is in `deploy-site` yet. The owner
  plans a daily inspection collector and a live Data Midsouth service.

# Working with these sources

- Do not reopen the D11 question for these two sources. The owner has
  decided it, and DECISIONS.md records both exceptions.
- When the owner's daily collector or the live Data Midsouth service
  exists, wire it into `deploy-site`.
- Do not build or run the collectors themselves without asking the
  owner.[^session-2026-09-27]

[^session-2026-09-27]: Owner's direction on the owner-collected sources
[^decisions]: DECISIONS.md D11, D24, D29 and D30
[^permits-research]: "Research: 311, permits, district boundaries"
[^fetch-permits]: Permits fetch
