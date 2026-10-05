---
type: Collection Method
title: ArcGIS batch fetch
description: R pipelines page through ArcGIS REST layers with read-only queries, retrying through memequity::arcgis_json().
tags: [collection, arcgis, r, 311, permits, geography]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-04T21:00:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: arcgis-r
    resource: ../../packages/memequity/R/arcgis.R
    title: memequity arcgis_json()
    last_modified: 2026-09-25T21:08:41-05:00
  - id: fetch-311
    resource: ../../pipelines/311/R/fetch.R
    title: 311 fetch
    last_modified: 2026-09-25T21:08:41-05:00
  - id: fetch-permits
    resource: ../../pipelines/permits/R/fetch.R
    title: Permits fetch
    last_modified: 2026-09-27T22:38:47-05:00
  - id: fetch-parcels
    resource: ../../geography/fetch_parcels.R
    title: Parcel fetch
    last_modified: 2026-09-25T21:08:41-05:00
  - id: fetch-boundaries
    resource: ../../geography/fetch_boundaries.R
    title: Boundary fetch
    last_modified: 2026-09-23T09:59:38-05:00
  - id: fetch-demographics
    resource: ../../geography/fetch_demographics.R
    title: Demographics fetch
    last_modified: 2026-09-23T17:01:48-05:00
  - id: deploy-site
    resource: ../../.github/workflows/deploy-site.yml
    title: deploy-site workflow
    last_modified: 2026-09-27T20:23:00-05:00
---

# Layers

| Data | Layer | Fetched by | Paging |
|---|---|---|---|
| 311 requests | `https://311.memphistn.gov/server/rest/services/311/311_Request_Map_PROD/FeatureServer/0` | `pipelines/311/R/fetch.R` | `OBJECTID > last`, ascending, 2,000 per page |
| DPD building permits | `https://services2.arcgis.com/saWmpKJIUAjyyNVc/arcgis/rest/services/DPD_Building_Permits/FeatureServer/0` | `pipelines/permits/R/fetch.R` | `ObjectId > last`, ascending, 1,000 per page |
| Parcel centroids | `https://311.memphistn.gov/server/rest/services/311/ParcelCentroids/MapServer/0` | `geography/fetch_parcels.R` | `OBJECTID > last` |
| Boundaries | TIGERweb (`tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb`) | `geography/fetch_boundaries.R` | `resultOffset`, 2,000 per page, GeoJSON |
| 2020 Census blocks | TIGERweb `tigerWMS_Census2020/MapServer/10` | `geography/fetch_demographics.R` | `resultOffset`, 5,000 per page[^fetch-demographics] |

# How a request is made

- **Read-only.** Only `query` requests are sent. The 311 layer advertises
  editing capabilities, which the code never uses. Contact fields and free
  text are never requested from 311, and neither is the permits
  `Description` field.[^fetch-311][^fetch-permits]
- **Keyset paging.** 311, permits and parcels ask for rows with an object
  ID greater than the last one seen, ordered by object ID. Boundaries and
  blocks use `resultOffset` instead.
- **Retries in two layers.** Each page request carries an identifying user
  agent, `httr2::req_retry` (5 tries, 2^i s backoff) and a 120 s timeout
  (`count_311()` sets only the retry count). It is then performed by `memequity::arcgis_json()`, which retries up to 6 times
  with 2^i s backoff on dropped connections *and* on ArcGIS errors returned
  inside an HTTP 200 body. `req_retry` alone covers only HTTP 429 and 503.
  The second layer was added after the City's 311 server answered one page
  with "User couldn't access this resource" and a daily run failed.[^arcgis-r]
  The boundary and block fetchers use their own loops and do not go through
  `arcgis_json()`.[^fetch-boundaries]
- **Dates** arrive as epoch milliseconds and are converted to UTC `POSIXct`.
- **Completeness.** `count_311()` and `permits_layer_info()` ask for
  `returnCountOnly` so validation can compare row counts. Permits also reads
  the layer's last edit date, which sets the data-through date.

# When it runs

- `deploy-site.yml` runs daily at 11:00 UTC (05:00 or 06:00 in Memphis,
  after the City's overnight 311 load). It runs the tests, then the 311
  pipeline, then permits, each with a fresh fetch.[^deploy-site]
- `--raw-cache FILE` lets a development run reuse a saved fetch.
- Parcels and demographics are refreshed yearly by hand
  (`geography/fetch_parcels.R`, `geography/fetch_demographics.R`).
  Boundaries are fetched by hand with `geography/fetch_boundaries.R`, which
  writes source and vintage into each file name.[^fetch-parcels]

# Other HTTP sources

These are plain downloads, not ArcGIS:

- Census Building Permits Survey place files from `www2.census.gov`
  (`pipelines/permits/reconciliation/fetch_bps.R`).
- The Census ACS API (`geography/fetch_demographics.R`, which needs
  `CENSUS_API_KEY`).
- The Census batch geocoder, with an optional Nominatim fallback
  (`packages/memequity/R/geocode.R`), used by food safety.

[^arcgis-r]: memequity arcgis_json()
[^fetch-311]: 311 fetch
[^fetch-permits]: Permits fetch
[^fetch-parcels]: Parcel fetch
[^fetch-boundaries]: Boundary fetch
[^fetch-demographics]: Demographics fetch
[^deploy-site]: deploy-site workflow
