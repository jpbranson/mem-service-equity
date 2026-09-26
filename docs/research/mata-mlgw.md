# Research: MATA and MLGW feeds

_Verified 2026-09-23 with curl._ This answers the plan's section 13 open
questions about MATA and MLGW.

## MATA static GTFS

- **URL:** `https://gtfs.mata.cadavl.com/MATA/GTFS/GTFS_MATA.zip`. No
  authentication. About 1.5 MB, with an ETag. Linked from
  matatransit.com's GTFS page. The vendor is Cadavl, exported from Trapeze.
- **Regenerated nightly as a rolling 30-day window.** There is no
  `feed_info.txt`. Export logs (`GTFS_CR_MATA_YYYYMMDD.txt`) are kept for
  only about 4 days, so **the project must archive the zip daily** to know
  which schedule was in force on each date (plan 6.1).
- **Contents:** 25 routes (including the Main Street Trolley), about 1,400
  trips, 7,588 stops.
  - `stop_times.timepoint` is 1 on about 9k rows; the other rows are
    interpolated.
  - `shape_dist_traveled` is filled, and so is `block_id`.
  - Registries point to stale URLs (Mobility Database `mdb-602`/`2352`
    deprecated, `tld-1655` inactive). Transitland
    `f-memphis~area~transit~authority` is current.

## MATA GTFS-Realtime (open, no key)

- `https://gtfsrt.mata.cadavl.com/ProfilGtfsRt2_0RSProducer-MATA/VehiclePosition.pb`
  (~4 KB, refreshed every ~30 s)
- `.../TripUpdate.pb` (~160 KB; absolute predicted times, **no `delay`**)
- `.../Alert.pb` (free-text alerts scoped to routes, e.g. cancellations)
- **VehiclePosition fields:** vehicle id and label, `trip_id`, `route_id`,
  lat/lon, `bearing`, `speed`, `current_status`, `stop_id`, `timestamp`,
  `occupancy_status`. All trip, route and stop IDs matched the static feed.
- **This answers plan section 13:** a GTFS-RT feed exists, and it exposes
  trip ID, route, heading and timestamp per vehicle.
- **Terms: not found.** MATA's T&C cover the GO901 app. See DECISIONS.md
  H16.
- **Seen in the archive (2026-09-23 to 09-25):**
  - `start_date` is always empty and `direction_id` is never set, so the
    service date is taken from the report time. No trip runs past
    midnight.
  - About 1.6% of reports are on `ADDED` trips that are not in the static
    feed.
  - `shape_dist_traveled` is in metres, about 0.3% longer than the
    projected shape length.
  - No route is scheduled every 30 minutes or better at peak; the most
    frequent run every 45.
  - See `pipelines/mata/` and DECISIONS.md H22 for coverage.

## MATA on-time performance (reconciliation target)

- **Memphis Data Hub, "MATA On Time Performance":**
  `https://services2.arcgis.com/saWmpKJIUAjyyNVc/arcgis/rest/services/MATA_On_Time_Performance/FeatureServer/0`
  - Monthly rows from 2015-07 to 2026-08. Fields: `Date`, `MATABus`,
    `MATAplus`, `Trolley`.
  - August 2026 bus value: **59%**.
- matatransit.com/progress shows "Peak On-Time Performance 70%, August 2026".
  This is a different, undefined series.
- The on-time definition behind either figure is unknown (H16).

## MLGW outage map

- `https://outagemap.mlgw.org/` → `OutageSummary.php`, a custom
  ArcGIS JS page. It is **not Kubra**.
- **Data:** `https://outagemap.mlgw.org/geojson.php`, a FeatureCollection
  of **points** (no polygons). Properties:
  - `OUTAGE_NO`: a stable ID
  - `TIME_STAMP`: outage start, local, no timezone
  - `DURATION`
  - `IMPACT`: size bucket, from "Single Customer" to "A Neighborhood"
  - `STATUS`
  - `EST_REPAIR_TIME`: ETR, often empty
  - `CUR_CUST_AFF`: customers affected
  - `OUT_CAUSE`: mostly blank
- **STATUS is revised in place**, and restored outages simply disappear.
  ETR revision was not observed in 25 minutes; assume ETRs are overwritten,
  so snapshots must be stored.
- Summary totals (customers with and without power) appear only in the HTML
  of `OutageSummary.php`.
- **F5 firewall:** some user agents get HTTP 200 with a 247-byte HTML
  "Request Rejected" page. The poller must check for JSON, not the status
  code.
- Content changes about every 5 minutes, so the poller runs every 5 minutes.

**Consequences for the MLGW spec:** events are points, not polygons.
Plan 6.2's polygon event-chaining becomes an `OUTAGE_NO` chain across
snapshots, and the address join becomes a radius or area join.
- The specs were restated this way in v0.2 (2026-09-25), awaiting
  confirmation (DECISIONS.md H19).
- `OUT_CAUSE` sometimes reads "Planned Construction", which marks planned
  outages.
- `IMPACT` buckets are "Single Customer", "Half a Block", "One Block", "A
  Few Blocks" and "A Neighborhood".

## MLGW reliability (reconciliation target)

- **EIA-861:** utility ID 12293 ("City of Memphis - (TN)"), IEEE 1366.

| Year | SAIDI with major events (min) | SAIFI with major events | SAIDI without major events | SAIFI without major events | Customers |
|---|---|---|---|---|---|
| 2022 | 866.8 | 2.92 | 411.6 | 2.27 | 420,172 |
| 2023 | 2694 | 3.20 | 408.6 | 2.08 | 421,615 |
| 2024 | 327.2 | 1.95 | 280.8 | 1.74 | 427,658 |
| 2025 (early release) | 348.7 | 2.23 | 283.2 | 1.99 | 430,114 |

- Source files: `https://www.eia.gov/electricity/data/eia861/zip/f8612024.zip`
  (`Reliability_2024.xlsx`). In the 2025 early-release workbook the columns
  are shifted by one.
- MLGW's "4M" Power BI dashboard (mlgw.com/4M) reports monthly SAIDI, SAIFI
  and CAIDI. Its values were not extracted.
