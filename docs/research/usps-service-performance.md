# Research: USPS mail service performance

_Verified 2026-09-25 by querying the USPS dashboard's own endpoints and
reading the statute, regulations and Inspector General reports, unless
marked otherwise._ This is a **candidate source, not part of the plan**. The
note answers "would USPS service performance data be a valuable addition?"
so the question does not have to be researched again.

## Headline findings

1. **USPS now publishes on-time mail rates for each 5-digit ZIP code
   (ZIP5).** The dashboard added ZIP5 and ZIP3 (the first three digits)
   levels starting with the week ending 2025-09-05. The regulation only
   requires Nation, Area and District (39 CFR 3055.102), so the ZIP levels
   are voluntary and could be changed or withdrawn without rulemaking.
2. **The numbers are USPS's own estimates, not records.** The dashboard
   publishes no volume or sample size at any level. Each value carries a
   margin of error (MOE; USPS's example uses 95% confidence), but the MOE
   does not shrink with longer windows, so it cannot be treated as an
   ordinary sampling interval. A USPS series cannot pass
   `metrics_problems()` (which requires `n`), and there is nothing to trace
   in a manual audit (plan 5.6).
3. **USPS's terms of use forbid republishing without written permission.**
   The dashboard has no robots.txt, and the regulation expects bulk and API
   access, but republishing still needs permission (plan section 12, D11).
4. **Mail to Memphis is on time less often than in the state or the
   nation, but the differences between Memphis ZIPs are small.** For fiscal
   2026 to date, 27 in-city ZIPs range from 80.1% to 86.5% on time.
   Downtown and the Medical District are lowest. The gaps do not follow
   disadvantage. If anything they run the other way, and part of that
   pattern comes from the mix of mail each ZIP receives.
5. **Recommendation: do not add USPS as a sixth panel now.** See the last
   section. Whether to change scope is the owner's decision.

## What USPS publishes

- **Legal basis.** 39 U.S.C. 3692 (Postal Service Reform Act of 2022,
  sec. 201) requires a public dashboard, updated weekly, for
  market-dominant mail. Geography follows the delivery organization "and, to
  the extent practicable, at the U.S. ZIP Code Area level". The Postal
  Regulatory Commission's rules (39 CFR 3055.101–.103, effective
  2023-03-20) require Nation, Area and District results, plus a lookup by
  street address, ZIP or PO box that returns the **District** result. The
  2026 revision (Order No. 9566, Docket RM2026-1, effective 2026-06-12) did
  not change the dashboard rules.
- **Dashboard:** https://spm.usps.com/ (an Angular app). The built-in
  documentation is `https://spm.usps.com/assets/pdf/External_Facing_SPM_Website_Documentation.pdf`.
- **Mail direction:** inbound (mail arriving in the area), outbound, or
  origin to destination between two areas at the same level.
- **Geography:** National, Area, District, ZIP3 and ZIP5. The default view
  is ZIP5, inbound, First-Class Mail, last week. Memphis is in Area `4G`
  ("Southern Retail Delivery") and District `370` ("Tennessee", ZIP3s
  370–385).
- **Periods:** postal week (Saturday–Friday), month, quarter, and fiscal
  year (October–September), each also "to date". The newest week on
  2026-09-25 ended 2026-09-11, so the lag is about two weeks.
- **Mail types:** First-Class Mail, Marketing Mail, Periodicals, and Bound
  Printed Matter/Media/Library Mail. Each is available as a whole, by
  product and by service standard (1–5 days for First-Class). One bulk file
  had 89 product and standard combinations.
- **Values:** on-time share (`score`), share delivered within one extra day
  (`score_plus_1`), average delivery days, MOE, and the fiscal-year target.
  Weekly values also come in a version adjusted for force majeure (events
  such as severe weather).
- **Suppression:** the API sets a low-volume flag. When the MOE exceeds 5
  points, no rate is shown and the page falls back to a broader geography.
- **How it is measured:** Intelligent Mail barcode scans on processing
  equipment, combined with sampled scans at collection and delivery. The
  USPS glossary defines "USPS Delivery" as the moment a piece "leaves the
  USPS mailstream or receives its final processing scan, making it ready
  for delivery". The documentation does not say how the delivery samples
  are used at ZIP level.

## Access

- **Query endpoint** (undocumented; it is what the page calls):
  `POST https://spm.usps.com/api/officialScore/toDate/get` with a JSON body.
  Unused levels take `"-1"`. The response has `score`, `scorePlus1`,
  `avgDaysToDelr`, `overallMoe`, `lowVolInd` and `geoLevelChanged`, and no
  volume field.

  ```json
  {"timePer": "Annual", "orgnArea": "-1", "orgnDist": "-1", "orgnZip3": "-1", "orgnZip5": "-1",
   "destnArea": "4G", "destnDist": "370", "destnZip3": "381", "destnZip5": "38126",
   "prodt": "First-Class Mail All", "rptgStartDate": "2025-10-01", "rptgEndDate": "2026-09-11",
   "current": true}
  ```

  `timePer` is `Weekly`, `Monthly`, `Quarterly` or `Annual`. `current` is
  omitted for weeks.
- **"Download Displayed Data"** saves the current view as CSV.
- **"Download Source Data"**: `GET https://spm.usps.com/api/extract/files`
  lists the files, and each is fetched from `/api/extract/download/<name>`.
  - On 2026-09-25 there were **72,626 gzip CSVs, about 470 GB compressed**
    (about 35 MB uncompressed each). The page waits 15 seconds between
    files (`/api/extract/interval` returns 15000 ms), so a full pull at that
    pace takes about 12.6 days.
  - Columns: `time_per, orgn_area, orgn_dist, orgn_zip_3, orgn_zip_5,
    destn_area, destn_dist, destn_zip_3, destn_zip_5, prodt,
    rptg_start_date, avg_days_to_delr, destn_area_name, destn_dist_name,
    mo, orgn_area_name, orgn_dist_name, pstl_qtr, pstl_yr, rptg_end_date,
    score, score_plus_1, overall_moe`.
  - One file had 150,054 rows. 135,717 were **origin ZIP5 → destination
    ZIP5 pairs**. The rest were the totals the page shows, with `-1` for
    unused levels (for example, 4,351 rows of all mail into one ZIP5).
    There are no volumes.
  - Rows are not grouped by place: that file had 894 destination ZIP3s and
    only 503 rows bound for 380 or 381. Extracting Memphis from the bulk
    files means reading all of them, so the query endpoint is the practical
    route for about 30 ZIPs.
- **robots.txt:** spm.usps.com has none (404). usps.com's robots.txt
  disallows the Post Office locator page
  (`/go/tools/po-locator/po-locator.html`), so post office locations and
  hours are off-limits there under D11.
- **Terms of use**
  ([about.usps.com](https://about.usps.com/who/legal/terms-of-use.htm)):
  "Material on this site is the copyrighted property of the United States
  Postal Service … Users may view and download material from this site only
  for the following purposes: (a) for personal, non-commercial home use …
  In all other cases, you will need written permission from the Postal
  Service to reproduce, republish, upload, post, transmit, distribute or
  publicly display material from this Web site." spm.usps.com has no terms
  page of its own. 39 CFR 3055.103(a) says results "should be exportable
  via a machine-readable format" and "accessible to any person or entity
  utilizing tools and methods designed to facilitate access to and
  extraction of data in bulk, such as an Application Programming Interface
  (API)". That supports automated access but does not grant republication
  rights. This is a question for a human, not a legal conclusion.

## Memphis numbers (pulled 2026-09-25)

Inbound First-Class Mail, all products, fiscal 2026 to date (2025-10-01 to
2026-09-11):

| Scope | On time | MOE (±) | Average days |
|---|---|---|---|
| National | 89.0% | 0.1 | 2.43 |
| Tennessee district | 87.4% | 0.1 | 2.53 |
| ZIP3 381 (Memphis and inner suburbs) | 84.4% | 0.2 | 2.80 |
| Memphis → Memphis (381 → 381) | 83.2% | 0.4 | 1.93 |
| 27 ZIPs with ≥ 1,000 in-city residents (D20) | 80.1% to 86.5% | 0.6 to 1.8 | 2.68 to 3.12 |

- **Lowest:** 38105 (80.1 ± 1.8) and 38103 (81.2 ± 1.8), the Downtown
  reference neighborhood (which includes the Medical District). Why they are
  lowest is not known. **Highest:** 38116 (86.5 ± 0.9), 38128 (86.4 ± 1.0) and 38135
  (86.4 ± 0.8). None of the 27 ZIPs was suppressed for the fiscal year,
  for August 2026, or for the week of September 5–11.
- **Time matters more than place.** The share of monthly First-Class Mail
  on time in 38105, 38103, 38116, 38117 and 38127 was 52.4–61.6% in
  February 2026. The Tennessee district was at 78.6% that month. This
  followed the late-January ice storm, when USPS "temporarily suspended"
  delivery to some Memphis customers
  ([Action News 5, 2026-01-27](https://www.actionnews5.com/2026/01/27/usps-suspends-mail-delivery-due-winter-weather-conditions/)).
  In the other eleven months these ZIPs ran 77–93%, lowest in December and
  January. A Downtown ZIP (38103 or 38105) was the lowest of the five in
  every month.
- **The MOE does not act like a sampling interval.** For 38116 it is ±0.9
  for the fiscal year, ±3.2 for August 2026 and ±0.7 for the week of
  September 5–11. For 38103 it is ±1.8 for the year and ±0.4 for August.
  The method is not published, so it cannot be reproduced.
- **The gap depends on the kind of mail.** Across the 27 ZIPs, all
  First-Class Mail spans 6.4 points. Presort letters (bulk mail that
  businesses sort before mailing, such as bills and statements) span 3.7
  points (84.4–88.1), with 38103 lowest. Single-piece letters (individually
  stamped mail) span 8.1 points (73.8–81.9), with 38105 and 38103 lowest.
- **The gaps do not track disadvantage.** Spearman correlations across the
  27 ZIPs, using the in-city ACS measures (D20):
  - % Black, not Hispanic: +0.65 for all First-Class Mail, +0.47 for
    presort letters and +0.43 for single-piece letters.
  - Income per resident: −0.55, −0.34 and −0.31.

  This is unadjusted and ecological (ZIP-level, not household-level), with
  n = 27. It is not a publishable finding. It says that ZIPs with more
  Black and lower-income residents do not get worse measured mail service.
  The correlations weaken within a single product, so part of the pattern
  comes from the mix of mail each ZIP receives.

## Inspector General findings for Memphis

- **23-099-R23 (2023-06-27).** At the Memphis Processing and Distribution
  Center and its annex, deficiencies were found in all four areas reviewed:
  clearance times, delayed mail, late or canceled trips, and load scans.
- **23-100-R23 (2023-08-21)** covered five delivery units: Collierville,
  Cordova, Germantown, Hickory Hill and the Desoto Carrier Annex.
  - **Desoto Carrier Annex** serves 38103, 38106 and 38126, plus PO-box ZIP
    38136. On 2023-05-02 the OIG found 2,141 delayed pieces. Management had
    reported 254 of them (11.86%) in its delayed-mail system (DCV).
  - **Hickory Hill Station** serves 38115, 38125 and 38141. The OIG found
    about 8,067 delayed pieces, and 5,434 (67.36%) had been reported.
- **21-089-R21 (2021-03-16).** Holiday City Station had 662 customer
  inquiries from September to November 2020.
- **Measurement, nationally.** 23-168-R24 (2024-06-26) found that the
  measurement system "accurately calculates service performance scores",
  but that collection and delivery scan data "may not be representative of
  the universe due to limitations with technology and carrier non-compliance
  with scanning". An older report, 19XG009NO000-R20 (2019-12-13), found
  21.7% of full-service mail excluded from measurement in FY2018.
- **What this means:** the failures residents notice most (mail held at the
  station, a route not run) happen in the last mile. The score sees the
  last mile only through sampled delivery scans, which the OIG says may not
  be representative.

## Fit with the plan

| Test | USPS ZIP data |
|---|---|
| Scope test (plan 12): a promise "the city or a utility makes to a resident at an address" | No. USPS is a federal service, so this would be a sixth system, like ED wait times (plan 6.6) |
| Promise source | USPS service standards are official, but they are federal. D12 covers city promises only |
| Address is the unit (principle 2) | No. The finest level is the 5-digit ZIP, so there is no H3 or address view. USPS ZIPs are not ZCTAs; PO-box ZIPs such as 38101 and 38136 have no ZCTA; and ZIPs that cross the city line (e.g. 38016, 38018) are reported whole |
| Council districts and multi-ZIP reference neighborhoods | No. Rates cannot be combined without volumes |
| Output contract (`n` required) | No. No volume or sample size is published |
| 5.4 minimum n and intervals | Only USPS's MOE, which cannot be reproduced. USPS suppresses above 5 points |
| 5.5 reconciliation | Circular, because the number is USPS's own |
| 5.6 manual audit | No records to trace |
| History and stability | ZIP levels only since September 2025, and voluntary. Measurement changes have been under Commission review (RM2024-9, PI2025-2, PI2025-5); since 2026-06-12 they need prior approval |
| Terms | Written permission is needed to republish |

## Recommendation

Do not add USPS as a sixth panel now. The data is real and matters to
residents. But it is USPS's own estimate for whole ZIP codes, it cannot
meet the publication rules (5.7) or the output contract, and republishing it
needs USPS's permission. It also adds little to the D19 question: the
differences between areas are small, partly reflect the mix of mail, and
are dwarfed by citywide swings such as February 2026.

Cheaper options, if the owner wants mail in the picture:

1. **Link, don't copy.** The ZIP view could link to USPS's dashboard, which
   already does ZIP lookups. No data is copied and no terms question
   arises.
2. **If a panel is wanted later:**
   - get written permission from USPS;
   - ask USPS for volumes or sample sizes per ZIP and for the MOE method;
   - decide how the output contract treats estimates made by the source
     without `n`;
   - limit the panel to `zcta` and single-ZIP reference neighborhoods;
   - show inbound First-Class Mail by product, not only "All";
   - record the scope change in DECISIONS.
3. **Adjacent USPS data for the investment panel.** HUD's aggregated USPS
   vacancy counts (census tract, quarterly) are
   [available](https://www.huduser.gov/portal/datasets/usps.html) "only to
   governmental entities and non-profit organizations registered as users",
   and only for the "stated purpose" in a sublicense agreement.
