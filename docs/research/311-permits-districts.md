# Research: 311, permits, district boundaries

_Verified 2026-09-23 by querying the endpoints unless marked otherwise._

## Headline findings

1. **data.memphistn.gov is no longer on Socrata.** It is now an ArcGIS Hub
   site (org `saWmpKJIUAjyyNVc`). Legacy `/resource/<id>.json` URLs redirect
   to `hub.arcgis.com/legacy`, and SoQL pipelines will fail.
2. **The live 311 data is on the city's own ArcGIS Server**, not the Hub.
3. **The plan's 311 promises ("3–7 business days for potholes", "82%
   on-time") trace to memphisgov.com.** That is a commercial `.com`,
   registered in 2024, that previously hosted travel SEO pages; the city uses
   memphistn.gov. **These figures are not cited.** The only official target
   found is the pothole goal on memphistn.gov: "The goal aims to address all
   reported potholes within 5-10 business days"
   ([source](https://memphistn.gov/potholes-repairs-winter-weather)). No
   official SLA table and no official on-time figure were found. The
   February 2026 Council deck says the city will "continue to work with
   Divisions to evaluate service level agreements". See DECISIONS.md H14.
4. **Another 311 migration is coming.** The same deck says the city is
   procuring a replacement system; the finalists are Accela, Tyler, Catalis
   and GOGov.

## 311 (current system, since 2023-10-16)

- **Layer (read-only use only):**
  `https://311.memphistn.gov/server/rest/services/311/311_Request_Map_PROD/FeatureServer/0`.
  - No token is needed. `maxRecordCount` is 3000. Page with
    `where=OBJECTID > n` and `orderByFields=OBJECTID`.
  - **The layer advertises Create/Update/Editing.** The pipeline only ever
    issues `query` requests.
- **Rows:** 407,039 on 2026-09-23. `created_date` runs from 2023-10-16 (go-live) to today.
- **PII:** the service exposes contact names, emails and phone numbers. The
  pipeline requests an explicit field list that excludes them.
- **Geometry:** request `outSR=4326`. The `X`/`Y` attributes mix lon/lat
  and state-plane feet, so they are ignored.
- **Dates:**
  - `created_date` is the open time.
  - `Closed_Date` contains sentinel junk dates (year 0001, 1202).
  - `RESOLVED_DATE` is populated on only 951 rows.
  - Some `REPORTED_DATE` values look like local time stored as UTC.
- **REQUEST_STATUS:** Closed 381,124; Open 12,473; In Progress 4,592;
  Resolved 4,531; "In Progress – Part of Ongoing Case" 2,391; Back to
  Department 1,139; Back to MCSC 477; Pending Litigation 240; blank 68;
  null 3.
- **Request_Sub_Status:** See Resolution Summary 367,368; Under Review
  28,351; Work in Progress 5,200; Cutting Complete 745; Pending Legal
  Resolution 302; No Violation Found 186; and others.
- **RESOLUTION_CODE:** 429 distinct values (e.g. SWM100, SWMCT4, NJ, OTHER).
  These are the input to the disposition audit (H4).
- **Duplicates:** `SYSREVSTATUS = DUPLICATE` on 5,495 rows. `SCF_URL` is
  set on 87,741 rows that originated in SeeClickFix.
- **Types:** 166 `REQUEST_TYPE` values. `CATEGORY` and `DIVISION` are
  empty, so the category is derived from the prefix (SWM-, PW (SM)-, CE-,
  CW-, EE-, EN-, …).
  - Potholes: `PW (SM)-Potholes`, 18,738 rows.
  - Graffiti: `PW (ROW)-Graffiti`, 315 rows.
  - **There is no streetlight type**; streetlights belong to MLGW.
- **Geography fields:** `cd_name` (council district 1–7, often null),
  `scd_name` (8/9) and `ZipCode`. The pipeline assigns geography itself and
  uses these fields only as a cross-check.

### Official 311 figures for reconciliation (researched 2026-09-25)

A research pass looked for figures the City publishes that the pipeline
could reproduce (DECISIONS.md D22). Figures marked *verified* were read on
the page itself; the rest are as reported by that pass.

- **No citywide figure exists.** The City publishes no citywide 311 request
  volume, time to close or on-time percentage.
  - The February 24, 2026 Council deck
    (https://memphistn.gov/wp-content/uploads/2026/02/EXEC-City-Council-311-Updates-Presentation-2-24-2026.pdf)
    has no numbers. Slide 4 says the web portal replaced "Roadside Litter"
    with "Bulk Trash"; watch for that in `config/request_types.csv`.
  - The City's "311 - Public Dashboard" (an ArcGIS dashboard on
    311.memphistn.gov) reads the same layer, so reconciling against it would
    be circular.
- **Division KPIs** in the adopted budget books and in the budget-hearing
  decks are annual by fiscal year (July–June). The adopted book appears
  around October; the FY27 book is not out yet.
- **Street-sweeping requests (verified).** FY26 Adopted Budget Book
  (https://memphistn.gov/wp-content/uploads/2025/10/FY26-Adopted-Budget-Book.pdf)
  p. 371 reports 1,424 street-sweeping service requests, with no period
  stated.
  - The layer has 1,423 `PW (HE)-Street Cleaning` requests created in FY25,
    so the figure is FY25.
  - It is transcribed in `pipelines/311/reconciliation/official_figures.csv`.
  - The FY25 book's FY24 figure (1,407) spans the migration and cannot be
    reproduced.
- **Pothole average days to fill (verified).** Same book, p. 372: "Average
  time to fill potholes in response to citizen request (days)":

  | FY24 actual | FY25 goal | FY25 actual | FY26 goal |
  |---|---|---|---|
  | 3.0 | 4.0 | 2.7 | 3.0 |

  - The book does not define the average or the timestamps.
  - The layer's FY25 mean from creation to close is 2.56 calendar days
    (median about 1.1).
  - The City's pothole page says approved camera detections also create
    311 requests; a "citizen request" may exclude them.
- **Bulk waste collected within 48 hours.** Solid Waste FY26 and FY27 budget
  decks (listed at https://memphistn.gov/fy27-budget/):

  | FY21 | FY22 | FY23 | FY24 | FY25 | FY26 |
  |---|---|---|---|---|---|
  | 58.0% | 48.5% | 39.3% | 33.7% | 34.2% | 41.2% (through January) |

  It does not reproduce under the literal definition: 13.8% of FY25
  `SWM-Missed Bulk Trash` requests closed within 48 hours. See H14.
- **Not reproducible from the layer:**
  - code enforcement days to first notice and compliance;
  - drain maintenance request counts (the book's 7,486 far exceeds the
    layer's 3,378);
  - call-centre answer times and abandonment rates, which also conflict
    between sources;
  - pothole counts, where decks, the ACFR and the web page disagree.
- **Correction to the note above.** `DEPARTMENT` is populated for most
  records. Since July 2025, however, about a third of new rows have it
  blank. The pipeline does not use it.
- **Granicus is off-limits.** memphis.granicus.com (Council video and
  document archive) has a robots.txt that disallows all crawlers. Do not
  automate retrieval from it (D11). memphistn.gov allows crawling with a
  10-second delay.

### Legacy dataset (offline)

- "Service Requests since 2016" (`hmd4-ddta`) had 2.1M rows covering
  2016-01-01 to 2025-09-30. It overlapped the new system from 2023-10 to
  2025-09.
- It is no longer served; metadata survives only in the Wayback Machine.
- Pre-migration history needs a records request (H15). Plan 6.3 already
  says never to compute across the migration.

## Building permits

- **Memphis Data Hub, "DPD Building Permits":**
  `https://services2.arcgis.com/saWmpKJIUAjyyNVc/arcgis/rest/services/DPD_Building_Permits/FeatureServer/0`
  - New, alteration and addition permits since January 2021, covering the
    joint Memphis/Shelby DPD jurisdiction. 27,501 rows.
  - Fields: Record_ID, Issued_Date, Sub_Type (RES/COM/Residential/Commercial),
    Construction_Type (ALT/New/ACC/ADD/Alteration/Accessory/Addition),
    Valuation, Address, City, ZIP_Code, Latitude, Longitude.
  - **No demolitions.**
- **Data Midsouth, "Building and Demolition Permits - Shelby County"**
  (Opendatasoft). **Do not collect it automatically.** Checked 2026-09-25:
  www.datamidsouth.org's robots.txt disallows `/api/` and dataset downloads
  for every crawler except Googlebot, and the dataset's license says only
  "See Website Terms of Use" (DECISIONS.md D24, H21). The API path is
  `https://www.datamidsouth.org/api/explore/v2.1/catalog/datasets/shelby-county-building-and-demolition-permits/records`.
  It is listed only so a future permission can be acted on. Its publisher is
  Innovate Memphis, and its attributions are Shelby County and Develop 901.
  - 74,502 rows since 2011.
  - `date_status` is a *status* date, not the issue date.
  - `record_type` has 9 values, including Demolition (3,261).
  - Carries `council_district`, `commission_district`, `tract_2020`,
    `parid`, `lat`, `lon`.
  - There is a spike in 2021 (13,813 rows), possibly an artifact of a system
    change.
- **Census BPS:** Memphis does not appear as a place. Joint Memphis/Shelby
  Construction Code Enforcement reports as "Shelby County Unincorporated
  Area" (place code 99990, county 157). Reconciliation therefore compares
  new residential building counts for the whole joint jurisdiction.
  - File pattern: `https://www2.census.gov/econ/bps/Place/South%20Region/soYYMMc.txt`
    (and `y`, `a`).

## District boundaries

- **City Council, 2023** (Ordinance 5870, 7 districts, field `CD`):
  `https://services2.arcgis.com/saWmpKJIUAjyyNVc/arcgis/rest/services/Council_Districts_2023/FeatureServer/0`
- **Super districts, 2023** (2 districts, field `SD` = 8/9):
  `.../Super_District_2023/FeatureServer/0`
- **County Commission** (13 districts, field `ShelbyCoun`, post-2020):
  `.../Commission_Districts_WEB/FeatureServer/0`
- Do **not** use `Political_Boundaries` layers 2 and 3; they are pre-2023.
