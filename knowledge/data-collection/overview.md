---
type: Architecture
title: Collection architecture
description: The three ways data enter the project (daily ArcGIS pulls, continuous pollers, files from the owner's collectors) and where each goes next.
tags: [collection, architecture]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-06T15:20:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: claude-md
    resource: ../../CLAUDE.md
    title: CLAUDE.md, Architecture section
    last_modified: 2026-10-06T16:03:24-05:00
  - id: decisions
    resource: ../../DECISIONS.md
    title: DECISIONS.md (D11, D29, D30, D32)
    last_modified: 2026-10-06T16:03:24-05:00
  - id: mlgw-poller
    resource: ../../pollers/mlgw_poller.py
    title: MLGW poller
    last_modified: 2026-09-27T20:05:32-05:00
---

# Summary

Most of the collection is not HTML scraping. The project reads official
APIs and machine-readable feeds in two ways, and takes two more sources as
files from the owner's own collectors. The only HTML page it parses is
MLGW's outage summary.[^mlgw-poller]

| Path | Language | Runs | Sources | Output |
|---|---|---|---|---|
| [ArcGIS batch fetch](arcgis-batch-fetch.md) | R (`httr2`) | daily in `deploy-site.yml`; yearly or by hand for geography | 311, DPD permits, parcels, boundaries, Census | the pipeline run itself (`--raw-cache` optional) |
| [Pollers](poller-design.md) | Python 3.12 (stdlib and `gtfs-realtime-bindings`) | every 2 hours on GitHub Actions | [MATA](mata-poller.md) GTFS-RT and GTFS, [MLGW](mlgw-poller.md) outage map | [weekly GitHub releases](poller-archive.md) |
| [Owner-collected sources](owner-collected-sources.md) | none in this repo | when the owner supplies files | TDH records-request export, Data Midsouth | files on disk, read by the pipelines |

# Flow

```
ArcGIS REST / Census ──(R, daily)──────────► pipeline: fetch → validate → normalize → geography → metrics
MATA GTFS-RT / MLGW map ──(Python pollers)─► gzip JSON lines → weekly release
                                              └─ gh release download → pipelines/{mata,mlgw}/run.R --archive
Owner's files ──(on disk)──────────────────► pipelines/{food-safety,permits}/run.R
```

Every pipeline writes flat files to `data/published/<pipeline>/`.
`site/build_site_data.R` turns those into sharded JSON for the static
site.[^claude-md]

# Rule

No source is scraped if its terms or robots.txt forbid it (D11). Data
Midsouth is an exception the owner made; food inspections now come from a
records-request export (D32). The pipelines only read the owner's
files.[^decisions]

[^claude-md]: CLAUDE.md, Architecture section
[^decisions]: DECISIONS.md (D11, D29, D30, D32)
[^mlgw-poller]: MLGW poller
