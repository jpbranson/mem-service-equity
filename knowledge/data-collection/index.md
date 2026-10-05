# Overview

* [Collection architecture](overview.md) - The three ways data enter the project (daily ArcGIS pulls, continuous pollers, files from the owner's collectors) and where each goes next.

# Batch pulls

* [ArcGIS batch fetch](arcgis-batch-fetch.md) - R pipelines page through ArcGIS REST layers with read-only queries, retrying through memequity::arcgis_json().

# Pollers

* [Poller design](poller-design.md) - Shared design of the Python pollers: stdlib fetch with retries, a multi-rate loop, crash-safe gzip JSON lines, and a log of every poll attempt.
* [MATA poller](mata-poller.md) - Polls MATA's GTFS-Realtime vehicle positions every 30 s and alerts every 15 min, and archives the static GTFS zip once per run.
* [MLGW poller](mlgw-poller.md) - Snapshots MLGW's outage-map GeoJSON every 5 min and scrapes the customer totals from the HTML summary page every 15 min.
* [Poller scheduling and coverage](poller-scheduling.md) - The pollers run as 170-minute GitHub Actions jobs every 2 hours, which covers only about half the time; an always-on host is prepared (H22).
* [Poller archive](poller-archive.md) - Poller output is uploaded every 30 minutes, after a gzip -t check, to weekly GitHub releases named archive-<source>-<YYYY>-W<ww>.

# Files from the owner

* [Owner-collected sources](owner-collected-sources.md) - Food inspections (state portal) and demolition permits (Data Midsouth) come from the owner's own collectors outside the repo; the pipelines only read the files (D29, D30).
