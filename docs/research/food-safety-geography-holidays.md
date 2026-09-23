# Research: food inspections, geography, denominators, holidays

_Verified 2026-09-23 by hitting the endpoints unless marked otherwise._

## Food establishment inspections (Shelby County)

- **Portal:** https://inspections.myhealthdepartment.com/tennessee. It is run
  for the TN Department of Health by HealthSpace / HS GovTech ("My Health
  Department"). Shelby County Health Department (SCHD) issues permits and
  performs inspections. Its FAQs point to this portal
  ([county](https://www.shelbycountytn.gov/FAQ.aspx?QID=415),
  [SCHD](https://www.shelbytnhealth.com/Faq.aspx?QID=86)).
- **Automated access is prohibited.** `robots.txt` names ClaudeBot,
  anthropic-ai, GPTBot and others, and ends with `User-agent: *` /
  `Disallow: /`. An AWS load balancer also returns 403 to non-browser user
  agents. **This project does not scrape the portal** (plan section 12:
  "check terms of use first").
- There is no bulk download, public API or terms-of-use page. Neither the
  Memphis Data Hub nor Data Midsouth publishes inspection data.
- **Route:** a public records request for a bulk export, sent to TDH
  Environmental Health or SCHD (see DECISIONS.md H11). The legal basis is
  Rule 1200-23-01-.08(4)(c)5, "the department shall treat the inspection
  report as a public document", together with the TN Public Records Act. The
  vendor may also be able to provide a feed.
- Fields the pages appear to expose (from search snippets, **not
  verified**): establishment name, address, permit, inspection date, score,
  purpose (Routine / Follow-Up), and a violation narrative with priority
  items.

### Scoring rules

- **Frequency:** Rule 1200-23-01-.08(4)(a)1 says the department "may inspect
  a food establishment at least once every 6 months". Part 2 allows longer
  intervals for an approved HACCP plan, a written risk-based schedule, or
  coffee/prepackaged-only operations. The rule was amended effective
  2024-09-29. Sources:
  [Cornell LII](https://www.law.cornell.edu/regulations/tennessee/Tenn-Comp-R-Regs-1200-23-01-.08)
  and the
  [TDH Food Rules PDF](https://www.tn.gov/content/dam/tn/health/program-areas/eh/TDH-Food-Rules.pdf).
- **Correction:** priority violations must be corrected within 10 days, and
  "a follow-up inspection may be made" (T.C.A. § 68-14-716(b)(2)).
- **Follow-up threshold of 70:** this comes from TDH policy, not the rule
  text. A
  [2014 TDH release](https://www.tn.gov/news/2014/2/19/restaurant-inspections-help-keep-tennesseans-healthy.html)
  says TDH does "follow-up inspections within 15 days at facilities that did
  not achieve a minimum score of 70" and inspects "each location at least
  twice a year". The 0–100 scale comes from the inspection form. Point
  weights are not verified.
- Do not confuse this with the TN Department of Agriculture schedule for
  retail food stores, which is a different regime.

## Census geocoder

- Single address:
  `https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?address=...&benchmark=Public_AR_Current&format=json`.
  It returns `result.addressMatches[]` with `matchedAddress`,
  `coordinates{x,y}` and `tigerLine`. It has **no Exact/Non_Exact field**;
  an empty list means no match.
- Batch: POST multipart (`addressFile`, `benchmark`) to `/locations/addressbatch`.
  The limit is 10,000 rows. Output columns are: id, input, `Match`/`No_Match`/`Tie`,
  `Exact`/`Non_Exact`, matched address, `"lon,lat"`, tigerLineId, side.
  This is implemented in `memequity::geocode_addresses()`.

## Boundaries (TIGERweb, all return HTTP 200 GeoJSON)

- **Tracts, Shelby County (249):**
  `tigerWMS_Census2020/MapServer/6/query?where=STATE='47' AND COUNTY='157'`
- **City of Memphis:** `tigerWMS_Current/MapServer/28/query?where=GEOID='4748000'`
- **ZCTAs 2020:** `tigerWMS_Census2020/MapServer/84`. This layer has no state
  field, so filter it by the 41 ZCTAs that touch county 47157, taken from the
  [2020 ZCTA–county relationship file](https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_county20_natl.txt).
- City layers on the Memphis Data Hub:
  `services2.arcgis.com/saWmpKJIUAjyyNVc/arcgis/rest/services/{Memphis_Jurisdiction_Boundary,Memphis_ZIP_Codes,Shelby_County_ZIP_Codes}/FeatureServer/0`.

The fetch script is `geography/fetch_boundaries.R`.

## ACS population

- The latest release is the 2024 ACS 5-year (2020–2024).
- **An API key is required for every request.** Keyless calls are
  redirected to `missing_key.html`. See DECISIONS.md H12.
- Tracts: `https://api.census.gov/data/2024/acs/acs5?get=NAME,B01003_001E,B01003_001M&for=tract:*&in=state:47%20county:157&key=KEY`
- ZCTAs: `...&for=zip%20code%20tabulation%20area:38103,38104,...&key=KEY`.
  ZCTA queries do not accept `in=state:`.
- Verified 2026-09-23 (used by `geography/fetch_demographics.R`, D20):
  - Block groups: `...&for=block%20group:*&in=state:47%20county:157` returns
    685 block groups, 919,173 residents. Every table the project uses
    (B01003, B11001, B03002, C17002, B19313, B25002, B25003, B25044, B28002)
    is published at block-group level. The 2025 5-year release is not out
    yet (the API returns 404 until each December's release).
  - Annotation codes: `-666666666` estimate means not available (e.g.
    aggregate income in the 5 block groups with no residents: airport, parks,
    tracts 9801xx); MOE `-555555555` means controlled (exact); MOE
    `-222222222` means no MOE could be computed.
  - Aggregate income (B19313) is rounded, so block-group sums can differ from
    the tract figure by up to $100. Counts sum exactly.
  - Memphis place (4748000) total population, 2020–2024: 618,980.
- 2020 Census blocks with population, housing units and internal points:
  TIGERweb `tigerWMS_Census2020/MapServer/10` (fields POP100, HU100,
  INTPTLAT, INTPTLON; max 100,000 records per query, no key). Shelby County
  has 14,498 blocks, summing to the 2020 count of 929,744.

## Parcels

- The official county GIS and the Assessor site block automated clients
  (Cloudflare / 403).
- **Working city-hosted layer:**
  `https://311.memphistn.gov/server/rest/services/311/ParcelCentroids/MapServer/1`
  ("Tax Parcels"; the city credits REGIS of Shelby County as the data
  source). It has 350,835 records and the fields PARCELID, ZipCode,
  Council_District, CALC_ACRE, X and Y. Layer 0 (centroids) adds
  PropertyAddress and TotalAppraisal. There is no land-use field.
- A third-party layer (`services5.arcgis.com/69z5u4wI9ZLawzrr/.../Shelby_County_Parcels_2026`)
  has the full Assessor schema, including LUC and LANDUSE. It is **not
  official**; use it for prototyping only.

## Holidays

- **City of Memphis 2026** (14 days), from the
  [official PDF](https://totalrewards.memphistn.gov/wp-content/uploads/2026/01/image-9.pdf):
  New Year's (Jan 1), MLK Birthday (Jan 19), Presidents' Day (Feb 16), Good
  Friday (Apr 3), **MLK Memorial (Mon Apr 6)**, Memorial Day (May 25),
  Juneteenth (Jun 19), Independence Day (Fri Jul 3), Labor Day (Sep 7),
  Veterans Day (Nov 11), Thanksgiving (Nov 26), Thanksgiving Holiday
  (Nov 27), Christmas Eve (Dec 24), Christmas (Dec 25).
- **The city does not observe Columbus Day.**
- Tennessee state offices use the list in T.C.A. § 15-1-101, which differs
  from the city's.
