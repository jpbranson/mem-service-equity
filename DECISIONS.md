# Decision log

Two lists. **Needs a human** holds the items that block part of the plan
until a person acts. They are grouped by who can resolve them, and each
names what it blocks. **Decisions made** records the implementation choices
made while building, so a reviewer can challenge them.

## Needs a human

### Accounts, credentials and access

- [ ] **H1. Object storage (Cloudflare R2 or S3).** Plan section 9 stores
  published flat files and poller archives in free-tier object storage.
  Create a bucket and add `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
  `R2_SECRET_ACCESS_KEY` and `R2_BUCKET` as repository secrets.
  *Blocks:* durable poller archives and versioned dataset storage. *Interim:*
  weekly and monthly GitHub release assets (see D7, D17).
- [x] **H2. GitHub Pages.** Enable Pages for this repo with source "GitHub
  Actions". *Done 2026-09-23:* https://jpbranson.github.io/mem-service-equity/.
  The site and `.github/workflows/deploy-site.yml` are built; the first
  deploy runs once that workflow is pushed to `main`.

- [ ] **H12. Census API key.** The Census data API now requires a key for
  every request. Get a free key at https://api.census.gov/data/key_signup.html
  and add it as the repo secret `CENSUS_API_KEY`, or locally as an
  environment variable. *Blocks:* ACS population denominators, which are
  needed for per-1,000-resident rates.

### Records requests and agency contacts

- [ ] **H11. Restaurant inspection data (blocks Phase 2).** The state
  inspection portal (inspections.myhealthdepartment.com) prohibits all
  automated access in robots.txt, and the project will not scrape it. File a
  Tennessee Public Records Act request with TDH Environmental Health or the
  Shelby County Health Department for a bulk export of Shelby County food
  establishment inspections, and ask whether a recurring export is possible.
  The request should cover: permit number, establishment name, address,
  inspection date, inspection type/purpose, score and violations, for
  2021–present. Rule 1200-23-01-.08(4)(c)5 makes inspection reports public
  documents. A draft request is in
  `docs/records-requests/h11-food-inspections.md` (not sent). The food-safety pipeline has not been built yet. It will be
  built to ingest that export (`pipelines/food-safety/`, reading from
  `pipelines/food-safety/inbox/`).
- [ ] **H14. Official 311 service targets and on-time figure.** The plan's
  "3–7 business days" and "82% on-time" figures trace to memphisgov.com, a
  commercial look-alike domain, not the city (see
  `docs/research/311-permits-districts.md`). The only official target found
  is potholes within 5–10 business days. Ask the city's 311 Center or the
  Office of Performance Management for (a) the official SLA table by request
  type and (b) any published on-time percentage and how it is computed.
  *Blocks:* the plan's key reconciliation (6.3, 14) and official-promise
  framing for every type except potholes.
- [ ] **H15. Pre-migration 311 history.** The legacy Socrata dataset
  (`hmd4-ddta`, 2016–2025) is offline. If the history matters, request a
  bulk export. It is not needed for the current metrics, which never cross
  the October 2023 migration.
- [ ] **H16. MATA data terms and on-time definition.** MATA's GTFS and
  GTFS-RT feeds are open and keyless, but no license or developer terms were
  found; the only terms on file cover the GO901 app. Ask MATA to confirm
  that archiving the feeds and publishing derived metrics is acceptable. At
  the same time, ask how the "MATA On Time Performance" Data Hub series and
  the "P-OTP 70%" dashboard figure are defined (on-time window, timepoints,
  early departures). *Polling has started* because the plan requires the
  baseline to start early; stop the `poll-mata` workflow if MATA objects.
- [ ] **H17. MLGW courtesy notice.** No terms of use for the outage map were
  found. The poller identifies itself and polls every 5 minutes, which
  matches the map's update rate. Tell MLGW the project exists and ask
  whether a data feed with customer counts per area is available.
- [ ] **H18. Keep scheduled workflows alive.** GitHub disables scheduled
  workflows in a public repository after 60 days without repository
  activity. Any commit resets the timer; re-enable in the Actions tab if
  needed. This covers `deploy-site` as well as both pollers. If the daily
  deploy stops, the site hides 311 numbers once the data is more than 3 days
  old.
- [ ] **H13. Historical city holiday calendars.** The 2026 city calendar is
  verified. Earlier years are reconstructed from rules, and the weekend
  shifts for MLK Memorial Day and Christmas Eve are inferred. Ask the city's
  HR / Total Rewards office for its 2023–2025 holiday schedules.

### Field and manual work (plan 5.6)

- [ ] **H3. Pre-launch manual audit, per panel.** Trace at least 100 random
  records by hand, from source to published metric, using the audit sheet
  that each pipeline generates under `audits/`. Commit the completed sheet.
- [ ] **H4. 311 disposition audit.** Read a few hundred closed requests and
  confirm or correct the draft disposition mapping. *Blocks:* the
  closed-without-action metric.
- [ ] **H5. MATA stopwatch audit.** Record actual arrivals for an hour at
  three stops: a terminal, a mid-route stop and a timepoint. *Blocks:* the
  MATA panel launch.
- [ ] **H6. Geocoder accuracy check (plan 7).** Hand-check a sample of 200
  Memphis addresses geocoded by the Census geocoder. The sample has not been
  drawn yet. The 311 pipeline does not need this, because it uses the city's
  own request coordinates. The address lookup does need it. From a browser,
  the Census geocoder works only through JSONP (it sends no CORS headers);
  Nominatim is the fallback.
- [ ] **H7. Independent reviewer.** Candidates are Data Midsouth, a
  University of Memphis faculty member or a former agency analyst (plan 13).
- [ ] **H8. Agency courtesy previews.** Send each panel and its methodology
  to the agency two weeks before launch.

### Judgment calls to confirm

- [ ] **H9. Reference-neighborhood ZIP groupings.** The draft is in
  `geography/reference_neighborhoods.csv`. Confirm it or edit it.
- [ ] **H19. Revise the MLGW specs before freezing.** The outage map
  publishes points with an `OUTAGE_NO`, not polygons
  (`docs/research/mata-mlgw.md`). The polygon event-chaining and
  point-in-polygon joins in `specs/mlgw/` must become OUTAGE_NO chains and
  radius/area joins.
- [ ] **H20. Hand-verify the 311 golden file.** `pipelines/311/tests/golden/`
  was frozen from the v0.1 code as a regression baseline. Plan 5.3 asks for
  golden outputs checked by hand, so a reviewer should recompute a handful
  of rows by hand.
- [ ] **H10. Spec review and freeze.** Every spec under `specs/` is `draft`.
  A human reviewer must read each one, including its adversarial objections,
  and set it to `frozen`. No metric can publish until this happens (5.7).

## Decisions made

- **D1. Language split.** Batch pipelines and the shared core are in R, as
  plan section 9 specifies. The MATA and MLGW pollers are Python, because
  long-running collectors are easier to keep running on GitHub Actions
  without an R toolchain. Their only dependency is the official
  `gtfs-realtime-bindings` protobuf package.
- **D2. Shared core as an R package.** The geography layer, calendar, stats,
  validation harness, output writers, spec parser and publish gate live in
  `packages/memequity`.
- **D3. Validation harness is built in-house, not pointblank.** The plan
  allows pointblank or pandera. The report format is fixed by plan section 8
  and has to be identical for the R pipelines and the Python pollers. A small
  harness writing that JSON directly (`R/validation.R`) is simpler than
  converting pointblank output, and it keeps dependencies light.
- **D4. Output schema extension.** `metrics_*.csv` adds a `variant` column,
  so the threshold alternatives required by 5.1 sit beside the primary
  series, and a `subgroup` column (such as the 311 request type). `citywide_median` holds the citywide median for median metrics and
  the citywide pooled value for proportions and rates.
- **D5. Business-day convention.** A request's age in business days counts
  the business days `d` with `open_date < d <= close_date`, in Memphis local
  time. A request opened and closed the same day is 0 days old. This must
  still be checked against any worked examples the city publishes; see the
  311 spec.
- **D6. Near-duplicate rule.** A record duplicates the earliest earlier
  *primary* record of the same type within 50 m and 7 days. The rule is not
  transitive, so a pothole re-reported every 5 days for a month produces a
  new primary each week, not a single cluster.
- **D7. Interim storage.** Until object storage exists (H1), poller output
  goes to **weekly GitHub releases** (`archive-<source>-<YYYY>-W<ww>`) as
  gzip JSON-lines assets; see `pollers/archive_release.sh`. Git history is
  the wrong place for about 1 GB a year of raw data, and weekly releases
  stay under GitHub's 1,000-asset limit. Pipelines write published outputs
  to `data/published/`. Once H1 is done, the upload step switches to R2.
- **D15. Pollers run on GitHub Actions** in 140-minute runs started every
  2 hours, so consecutive runs overlap. Duplicates from the overlap are
  removed downstream. Every poll attempt is logged (`*_polls_*`), and uptime
  is computed from those logs.
- **D10. Business days follow the City of Memphis holiday calendar,** not
  the federal one, because 311 targets are the city's promise. The city
  observes Good Friday, MLK Memorial Day (April 4), the day after
  Thanksgiving and Christmas Eve, and does not observe Columbus Day.
- **D11. No scraping of sources whose terms or robots.txt forbid it.** This
  applies to the state inspection portal (see H11). This is plan section 12,
  applied.
- **D12. 311 promise sources.** Only memphistn.gov and other official city
  documents are cited as promises. The pothole target (5–10 business days,
  memphistn.gov) is the one official 311 target. Every other request type
  is labelled a comparison against the citywide median until H14 is
  resolved.
- **D13. Phase order.** Phase 2 (food safety) is blocked on a records
  request (H11), so the 311 pipeline (Phase 3) ships first. The
  food-safety pipeline is not built yet. When it is, it will be built and
  tested against the expected export format, so it can run the day the data
  arrives.
- **D14. Permit reconciliation target.** Memphis does not appear in the
  Census Building Permits Survey as a place. Its permits are reported under
  "Shelby County Unincorporated Area" (place 99990), which covers the joint
  Memphis/Shelby DPD jurisdiction. Reconciliation therefore compares
  new-residential-building counts for that joint jurisdiction, not for the
  city alone.
- **D16. Address-level area.** For the address lookup, "near this address"
  means the address's H3 resolution-9 cell plus its six neighbors (grid
  disk k = 1). That is about 0.74 km², roughly a 0.3-mile radius, close to
  the plan's 0.25-mile radius. Per-cell counts are summed over the disk and
  run through the same estimators as the district metrics (count-based
  Kaplan–Meier, Wilson), so the browser needs no server and never computes
  a statistic itself.
- **D17. Published outputs are not committed.** Each run's flat files
  (tens of MB) go to a monthly release (`data-<pipeline>-<YYYY-MM>`) as a
  dated zip, which keeps every version as plan section 9 requires, and are
  deployed with the static site. Code, config, specs, golden files and
  audits are committed.
- **D18. The publish gate is enforced in the site data, not only in the
  browser.** `site/build_site_data.R` leaves out every metric that fails
  `publish_gate()`, so unpublished numbers never reach the public JSON on
  GitHub Pages. `--preview` keeps them for local review and marks the
  manifest, and the page then shows a preview banner. The deploy workflow
  refuses to publish a preview manifest. Raw nearby 311 requests are source
  records, not statistics, so they are shown either way.
- **D8. Boundary rule.** A point within 1 m of more than one polygon goes to
  the lowest `geo_id` among them and is flagged `on_boundary`.
- **D9. Censored durations.** Median time-to-close uses a Kaplan–Meier
  median with a log-log interval, so requests still open are treated as
  right-censored rather than dropped.
