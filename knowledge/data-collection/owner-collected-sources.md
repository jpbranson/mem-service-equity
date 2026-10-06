---
type: Collection Method
title: Owner-collected sources
description: Demolition permits (Data Midsouth) come from the owner's collector, and food inspections from a TDH records-request export the owner supplied; the pipelines only read the files (D30, D32).
tags: [collection, food-safety, permits, demolitions, d11, records-request]
status: draft
generated: { by: claude-code/claude-fable-5-1, at: 2026-10-06T16:05:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: session-2026-09-27
    resource: "The owner's direction in a Claude Code session on 2026-09-27, kept in Claude's private project memory until it was moved here on 2026-10-04"
    title: Owner's direction on the owner-collected sources
    author: human:jpbranson
  - id: decisions
    resource: ../../DECISIONS.md
    title: DECISIONS.md D11, D24, D29, D30, D32 and H11
    last_modified: 2026-10-06T16:03:24-05:00
  - id: column-map
    resource: ../../pipelines/food-safety/config/column_map.yml
    title: Food-safety column map
    last_modified: 2026-10-06T16:00:07-05:00
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

| Data | Original source | Owner's file | Read by | Decision |
|---|---|---|---|---|
| Food inspections | Tennessee Department of Health, records-request export | `pipelines/food-safety/inbox/Shelby County Information Request.xlsx` (gitignored) | `pipelines/food-safety/run.R` | H11, D32 |
| Demolition permits | Data Midsouth, "Building and Demolition Permits – Shelby County" | `../mem-demo-permits/shelby_permits.csv` (sibling repo) | `pipelines/permits/run.R --demolitions FILE` | D30 |

From 2026-09-27 to 2026-10-06 food inspections came from the owner's
collector for the state inspection portal (D29). Since D32 the pipeline
reads only the agency's export, and its column map names the export's
sheets and columns, so the collector's file cannot be read without
editing the map.[^decisions][^column-map]

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

# State as of 2026-10-06

- Food inspections: TDH's export has 41,212 food-program inspections from
  2021-01-04 to 2026-10-02 (41,185 after rows identical in every column
  are read once) and 6,161 permits. It has no inspection IDs, violations
  or closure dates, and it names inspectors and billing contacts, so it is
  never committed. The validation report records its md5.[^decisions]
- Demolitions: 2,315 permits after duplicates are removed, with the latest
  status date 2026-07-31. Only demolitions come from this snapshot; the
  City's DPD layer stays the source for every other permit type.
- Both are static files and neither is in `deploy-site`. The owner plans
  a live Data Midsouth service. TDH will not send recurring exports, the
  owner reported on 2026-10-06, so the inspection data end on 2026-10-02
  until a new request is filed; how the panel stays current is undecided
  (H11).[^decisions]

# Working with these sources

- Do not reopen the D11 question for these two sources. The owner has
  decided it, and DECISIONS.md records both exceptions.
- When the live Data Midsouth service exists, wire it into `deploy-site`.
  A newer TDH export goes in the inbox by hand.
- Do not build or run the collectors themselves without asking the
  owner.[^session-2026-09-27]

[^session-2026-09-27]: Owner's direction on the owner-collected sources
[^decisions]: DECISIONS.md D11, D24, D29, D30, D32 and H11
[^column-map]: Food-safety column map
[^permits-research]: "Research: 311, permits, district boundaries"
[^fetch-permits]: Permits fetch
