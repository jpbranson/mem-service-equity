---
type: Poller
title: MLGW poller
description: Snapshots MLGW's outage-map GeoJSON every 5 min and scrapes the customer totals from the HTML summary page every 15 min.
resource: ../../pollers/mlgw_poller.py
tags: [collection, poller, mlgw, outages, power]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-04T20:45:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: mlgw-poller
    resource: ../../pollers/mlgw_poller.py
    title: pollers/mlgw_poller.py
    last_modified: 2026-09-27T20:05:32-05:00
  - id: research
    resource: ../../docs/research/mata-mlgw.md
    title: "Research: MATA and MLGW feeds"
    last_modified: 2026-09-25T20:55:57-05:00
---

# Feeds

| Feed | URL | Every | Written to |
|---|---|---|---|
| Active outages | `https://outagemap.mlgw.org/geojson.php` | 5 min | `mlgw_snapshots_<run>.jsonl.gz`, the full snapshot every poll |
| Customer totals | `https://outagemap.mlgw.org/OutageSummary.php` | 15 min | `mlgw_summary_<run>.jsonl.gz` |
| Every attempt | | | `mlgw_polls_<run>.jsonl.gz` |

Every writer flushes after each line.[^mlgw-poller]

# Outage snapshots

- The GeoJSON is a FeatureCollection of points, one per active outage, not
  polygons. Restored outages disappear and fields such as `STATUS` and the
  estimated repair time are revised in place, so every snapshot is kept
  whole and events are rebuilt later from the sequence.[^research]
- **Success means "parsed as the expected JSON", not "HTTP 200".** MLGW's
  firewall answers some clients with HTTP 200 and a small HTML "Request
  Rejected" page. A poll counts only if the body is a FeatureCollection and
  every feature has `OUTAGE_NO`, `TIME_STAMP`, `STATUS`, `EST_REPAIR_TIME`
  and `CUR_CUST_AFF`.

# Summary totals: the one HTML scrape

Customers with and without power appear only in the HTML of
`OutageSummary.php`. The poller strips tags, unescapes entities and reads
the two percentages, the two counts and the "CURRENT AS OF" time with one
regular expression. If the text is not found, the poll is logged as
failed.[^mlgw-poller]

# Downstream

`gh release download archive-mlgw-<week>`, then
`pipelines/mlgw/run.R --archive DIR` builds one outage event per
`OUTAGE_NO` chain (H19, D31). A window is computed only when the poller
covered 90% of its time, and the MLGW specs stay blocked until six months
of history exist. See [scheduling and coverage](poller-scheduling.md).

[^mlgw-poller]: pollers/mlgw_poller.py
[^research]: "Research: MATA and MLGW feeds"
