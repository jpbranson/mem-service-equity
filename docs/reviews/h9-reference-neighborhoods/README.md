# H9 review packet: reference neighborhoods

_Prepared 2026-09-25 by Claude. **H9 is a judgment call for a person**, and
`geography/reference_neighborhoods.csv` has not been changed._

Plan 7 calls for "a fixed set of six to eight named areas … used as
comparison anchors in every view", defined as ZIP groupings with the mapping
published. The draft uses the plan's own eight examples. This packet gives
the numbers behind that choice. Nothing in it decides it.

## Files

- [`neighborhood_table.csv`](neighborhood_table.csv): each draft anchor and
  the city, with in-city residents (ACS 2020–2024, D20), the share of 2020
  population inside the city, demographics, and 311 requests (deduplicated,
  all types) over the 12 months to 2026-09-24.
- [`zip_table.csv`](zip_table.csv): the same for every ZIP code (ZCTA) with
  residents inside the city, including those in no anchor.
- [`cdc_service_areas_by_zip.csv`](cdc_service_areas_by_zip.csv): the City's
  "City of Memphis Neighborhoods" layer, which is 44 community development
  corporation (CDC) service areas, not a citywide neighborhood map. Each is
  split by ZIP code by area. It is an independent check of which ZIPs a
  neighborhood name covers.
- [`build_tables.R`](build_tables.R) rebuilds all three after a 311 run.

## What the numbers show

**Coverage.** The eight anchors hold 50% of in-city residents. The largest
ZIPs in no anchor, by in-city residents:

| ZIP | Residents | Black | White | Hispanic | Poverty | Requests per 1,000 | Area |
|---|---|---|---|---|---|---|---|
| 38109 | 42,500 | 95% | 2% | 1% | 32% | 284 | Westwood / southwest |
| 38111 | 41,920 | 47% | 33% | 13% | 26% | 208 | University area |
| 38118 | 39,170 | 72% | 5% | 21% | 30% | 187 | Parkway Village / Oakhaven |
| 38115 | 38,400 | 81% | 6% | 12% | 19% | 131 | Hickory Hill |
| 38134 | 29,760 | 53% | 19% | 21% | 14% | 111 | northeast, 68% in the city |
| 38122 | 25,950 | 20% | 33% | **38%** | 28% | 201 | Nutbush / Berclair |
| 38114 | 20,490 | 88% | 6% | 5% | 33% | **342** | Orange Mound |

The area names are the usual associations, confirmed by the CDC crosswalk
where one exists (for example, Orange Mound Development Corp. is 82% in
38114). They are not official ZIP names.

**Observations for the decision:**

1. **No anchor represents the city's Hispanic neighborhoods.** Citywide,
   10.4% of residents are Hispanic. Among the anchors the share runs from
   2.6% (South Memphis) to 10.5% (Raleigh). The four ZIPs above 20%
   (38122, 38108, 38134, 38118) are all outside the anchors. If anchors
   are meant to span the city's range, this is the biggest gap.
2. **Frayser, Raleigh and Whitehaven match their CDC areas.**
   - Frayser CDC is 100% in 38127.
   - Raleigh CDC is 98% in 38128.
   - Greater Whitehaven EDC is 81% in 38116 and 19% in 38109.
3. **"Midtown" mixes two different ZIPs.** 38104 is the Midtown core:
   Central Gardens is 100% in it, and Midtown Memphis Development Corp. is
   57% in it and 16% in 38112. 38112 is mostly Binghampton: Binghampton
   Development Corp. is 82% in it. The two differ:

   | ZIP | Poverty | Hispanic | Income per resident |
   |---|---|---|---|
   | 38104 | 16% | 5% | $52,800 |
   | 38112 | 29% | 15% | $32,900 |

   The draft's own note says 38112 "also covers parts of Binghampton".
4. **"Downtown" mixes two different ZIPs.**

   | ZIP | Black | Poverty | Requests per 1,000 |
   |---|---|---|---|
   | 38103 (downtown core) | 28% | 10% | 57, the lowest of any ZIP with 1,000+ residents |
   | 38105 (Medical District / Uptown) | 72% | 26% | 172 |

   The Center City Development Corporation area also reaches into 38107
   (22%).
5. **Cordova is mostly outside the city by population.** Only 59% of the
   2020 population of 38016 and 38018 lives inside the city, and 44% for
   38018 alone. Under D20 the anchor shows only its in-city part, and the
   site says so. The anchor is still a distinct suburban comparison
   (income per resident $40,400; poverty 7.5%).
6. **South Memphis (38106 + 38126)** is consistent with the CDC areas (The
   Works, The Stone, South Memphis Alliance). 38126 also includes the
   South City redevelopment next to downtown.
7. **East Memphis (38117, 38119, 38120)** spans income per resident from
   $53,300 to $106,600, all well above the city's $33,200. It is the
   high-income anchor.

## Options

These are examples, not recommendations:
- **Keep the draft** as the plan's examples. Note in the methodology that the
  anchors cover half the city and no Hispanic-majority area.
- **Swap one anchor to cover the Hispanic gap**, staying within eight. For
  example, add "Nutbush / Berclair" (38122), or "Parkway Village" (38118,
  which is 21% Hispanic and poorer than the city), in place of one of the two
  anchors most alike on these measures (Whitehaven and South Memphis are
  both over 90% Black with high poverty).
- **Tighten the mixed anchors:** Midtown = 38104 only, and Downtown =
  38103 only (38105 on its own or dropped). Single-ZIP anchors are easier
  to explain but smaller, so more cells are suppressed.

## After deciding

1. Edit `geography/reference_neighborhoods.csv` if anything changes.
2. Rerun `Rscript geography/fetch_demographics.R` (needs `CENSUS_API_KEY`). A
   package test fails if the demographics no longer match the mapping.
3. Rerun the 311 pipeline and the site build.
4. Mark H9 done in DECISIONS.md with the date and what was chosen.
