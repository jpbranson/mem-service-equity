---
type: Analysis
title: Where 311 runs slow
description: Exploratory tract-level analysis of where 311 requests close slower than their type's citywide median, and whether those places cluster; not a project metric.
resource: ../../analysis/311-slow-service/output/report.html
tags: [analysis, 311, spatial, exploratory]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-04T20:50:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: readme
    resource: ../../analysis/311-slow-service/README.md
    title: "Where 311 runs slow: README"
    last_modified: 2026-10-04T20:46:26-05:00
  - id: run
    resource: ../../analysis/311-slow-service/run.R
    title: analysis/311-slow-service/run.R
    last_modified: 2026-10-04T20:46:26-05:00
---

# What it is

A standalone spatial analysis in `analysis/311-slow-service/`. It asks
where requests take longer to close than the same request types take
citywide, and whether those places cluster. The unit is the 2020 census
tract.

It is **exploratory, not a project metric**. Nothing in it passes the
publication rule: the specs are drafts (H10) and there is no manual audit
(H3).[^readme] Do not cite its numbers as the project's findings or put
them on the site without going through the specs and the publish gate.

# Result in brief

These numbers come from the 2026-09-28 run, for requests opened June to
August 2026.[^readme]

- Type-adjusted closing times cluster strongly: global Moran's I is 0.76
  over 181 tracts.
- A **fast cluster** of 30 tracts in the north (ZIPs 38127, 38128) had 0.57
  times the expected number of slow requests. A **slow cluster** of 29
  tracts in the southwest (ZIPs 38116, 38109) had 1.31 times.
- Most of the contrast is solid-waste collection. Bulk trash had a median
  of 1 business day in the fast cluster, 7 citywide and 15 in the slow
  cluster.

# Caveats

- The two clusters close bulk-trash requests with different resolution
  codes: 88% carry no code in the fast cluster, while 92% carry `SWMCT4` in
  the slow cluster. Part of the gap may come from how requests are closed
  rather than from when trash is collected (H4).
- Without the solid-waste types, Moran's I falls to 0.34, and only 3 slow
  and 2 fast cores remain.
- In June–July 2025 the fast cluster was in the same place, but the slow
  cluster was mostly elsewhere (ZIPs 38114, 38111, 38104).
- The six-nearest-neighbour check gives almost the same result.[^readme]

# Method

The thresholds, minimum counts, seed (20260923) and sensitivity checks are
fixed in `PARAMS` at the top of `run.R`. They were set before any result
was seen, with one exception: the solid-waste exclusion check was added
after the per-service breakdown.[^run]

- **Threshold.** Each request type's threshold is its citywide
  Kaplan–Meier median of business days to close. Open requests are
  censored (D9).
- **Ratio.** A tract's ratio is observed over expected slow requests, with
  a Wilson interval.
- **Minimum counts.** Tracts with fewer than 30 eligible requests are not
  reported, and types with fewer than 20 requests are left out.
- **Clusters.** Ratios are standardized with empirical Bayes. Global and
  local Moran's I use queen contiguity, permutation tests and a
  Benjamini–Hochberg FDR of 5%.

The README describes each step in full.[^readme]

# Inputs and rerunning

The inputs are the offline caches from 2026-09-25: 311, DPD permits, the
owner's demolition and inspection files, and `geography/`. None is
committed. The prep step reuses each pipeline's own normalize and
geography code, then adds a tract assignment.

```sh
R CMD INSTALL packages/memequity
Rscript analysis/311-slow-service/run.R                 # reuses the prep cache
Rscript analysis/311-slow-service/run.R --rebuild-prep  # also rebuilds it (~3 min extra)
Rscript analysis/311-slow-service/run.R --report-only   # page and figures from saved results
```

The run is deterministic. The outputs in `output/` are committed: the
report, four SVG figures and one CSV per table. `results.rds` holds the
request-level results, which `--report-only` reads, and is gitignored.

[^readme]: "Where 311 runs slow: README"
[^run]: analysis/311-slow-service/run.R
