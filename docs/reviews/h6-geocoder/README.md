# H6 review packet: geocoder accuracy

_Prepared 2026-09-25 by Claude. **H6 is not done.** Plan 7 asks for a
hand-checked sample of 200 Memphis addresses before the address lookup is
used, and for the accuracy rate to be published. The sample is drawn and
measured automatically below. The hand check is a person's job._

## How the sample was drawn

The parcel layer's `PropertyAddress` field is empty on all 350,835 records,
so addresses come from the City's own address-point locator instead
([`geography/check_geocoder.R`](../../../geography/check_geocoder.R)):
1. Random in-city tax parcels were drawn (seed 20260925).
2. Each parcel was reverse-geocoded with the City's 311 locator
   (`311/LiveLinkGeolocator`). A parcel was kept when the locator returned
   an official address point (`PointAddress`) within 50 m of it: 200
   addresses from 623 in-city parcels. The rest were mostly vacant lots and
   large parcels with no address point nearby.
3. Each address was then geocoded **exactly as the site does**
   (`site/assets/app.js`):
   - append ", Memphis, TN";
   - take the Census geocoder's first match (`Public_AR_Current`);
   - otherwise fall back to Nominatim, bounded to the Memphis box.
4. Each result was compared with the official address point.

The reference is the City's address point, not ground truth. It can be
wrong too, and settling that is what the hand check is for.

## Results (all 200 addresses; a miss counts against every rate)

| Measure | Result |
|---|---|
| Census geocoder matched | 93.0% (186) |
| Nominatim fallback used | 5.0% (10) |
| No result at all | 2.0% (4) |
| Median distance from the address point | 35 m |
| 90th / 95th percentile distance | 107 m / 138 m |
| Within 50 m / 100 m / 250 m | 64.5% / 86.5% / 95.5% |
| Same H3 cell as the address point | 77.5% |
| **Inside the address point's 7-cell disk** (what the lookup shows, D16) | **96.5%** |
| Same ZIP code (ZCTA) | 96.5% |
| Same council district | 97.5% |

The address lookup reports the seven-cell disk around the geocoded cell, so
for 96.5% of addresses the result covers the address's own cell. It is off
by a cell or more for 3.5%, and the ZIP or district shown is wrong for 2.5%
to 3.5%.

Full detail: [`geocoder_sample_2026-09-25.csv`](geocoder_sample_2026-09-25.csv)
and [`geocoder_summary_2026-09-25.txt`](geocoder_summary_2026-09-25.txt).

## Failure patterns worth a decision

| Case | What happened |
|---|---|
| `1234 HWY 78`, `3675 HWY 78` | Census found no match (Lamar Avenue is US 78). The **Nominatim fallback returned "Old US Highway 78", 19.6 km and 8.7 km away**, in the wrong ZIP and district |
| `3884 HWY 79` | No result from either geocoder |
| `1389` and `1443 WILLIE MITCHELL BL` | No result. The street was renamed, and the Census address ranges may still use the old name |
| `4630 SHELBY COMMONS CT` | No result |
| `200 W GEORGIA AV` | Census matched **200 E Georgia Ave**, 1.2 km away in a different ZIP |
| `1188 FAXON AV` | 196 m off and across a ZIP line |

Possible changes to the site (none made):
- Distrust Nominatim when its matched street differs from the input, or
  when the result is far from the typed ZIP. Today a wrong match is shown
  with its label ("Old US Highway 78") and nothing else.
- Warn when the matched directional or street name differs from what was
  typed (W vs E Georgia).
- Try the City's own locator as a second source before Nominatim. It is an
  address-point locator and has no robots.txt. This needs a check that it
  accepts browser requests (CORS) and a decision that using it is
  acceptable.

## What a person still has to do

1. Open `geocoder_sample_2026-09-25.csv`. For the 27 rows with a `flag`,
   plus at least 20 unflagged rows as a control, look at both points on a
   map (`reference_lon/lat` and `geocode_lon/lat`). Set `reviewer_verdict`:
   - `correct`: the geocode is at the right property;
   - `near`: the right block, wrong spot;
   - `wrong`: another place;
   - `reference_wrong`: the City's point is the one that is off.
2. Decide which rate to publish on the methodology page. The disk
   containment rate (96.5%) is the one that matches what the lookup shows.
3. Decide on the fallback changes above.
4. Mark H6 done in DECISIONS.md.

## Re-running

```sh
Rscript geography/check_geocoder.R docs/reviews/h6-geocoder 200 20260925
Rscript geography/check_geocoder.R --summarize docs/reviews/h6-geocoder/geocoder_sample_2026-09-25.csv 20260925
```

The first command draws a new sample and queries three services (the City's
parcel layer and locator, the Census geocoder, and Nominatim at one request
per second). It takes about 10 minutes. The second only rebuilds the summary.
