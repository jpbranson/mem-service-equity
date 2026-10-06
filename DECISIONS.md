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
  `deploy-site` has deployed daily since that day.

- [x] **H12. Census API key.** The Census data API now requires a key for
  every request. Get a free key at https://api.census.gov/data/key_signup.html
  and add it as the repo secret `CENSUS_API_KEY`, or locally as an
  environment variable. *Blocks:* ACS population denominators, which are
  needed for per-1,000-resident rates. *Done 2026-09-23:* the repo secret
  is set, and the key is also set locally in `~/.Renviron`.

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
  documents. The request is in
  `docs/records-requests/h11-food-inspections.md`. *Sent 2026-09-23 to TDH;
  no reference number yet.*
  Under the Public Records Act the agency must respond within 7 business
  days (by 2026-10-02) by producing the records, denying the request or
  giving an estimated completion date. Follow up if nothing arrives by then (draft:
  `docs/records-requests/h11-follow-up.md`).
  *No longer blocking (2026-09-27):* the food-safety pipeline runs on the
  owner's collector data from 2025 onward (D29). The export would still add
  2021–2024, violations and closures, and a source the agency provides.
  *Received by 2026-10-06 from TDH (reference number not recorded):*
  `Shelby County Information Request.xlsx`, md5
  `7d9f511352cffea62f542f15174ac2f7`, 4,045,333 bytes, now in
  `pipelines/food-safety/inbox/`. Two sheets: "Food Inspection
  Information" (41,212 food-program inspections, 2021-01-04 to 2026-10-02:
  date, permit name, score, inspector, address, permit type, status,
  establishment ID, purpose, risk) and "Permit Information" (6,161
  food-program permits, with status but no closure date). It has no
  inspection ID and no violations. Over 2025-01-02 to 2026-09-25, 99.6% of
  the collector's food inspections are in it (same date, address and
  score), and it has 930 more, mostly recent restaurant routines not yet on
  the portal. It also has 198 same-day repeats (same establishment, date
  and purpose; most with different scores), which the collector never has:
  in 36 of the 48 such pairs since 2025 the portal shows only one, and not
  always the higher score. New values needing a mapping: purposes
  Consultation (four variants), Routine Complaint and Preliminary; permit
  types Hotel 51-150, Type C - Wading pools and Child Care Inst.
  *Wired in 2026-10-06 (D32):* the pipeline now reads only this export.
  *Still open:* the request asked for violations, which the export lacks.
  The owner decides whether to ask TDH for them.
  *No recurring export (2026-10-06):* the owner reports that TDH will not
  send recurring exports. The food-safety data therefore end on 2026-10-02
  until someone files a new request, and the pipeline warns once they are
  60 days old. How the panel stays current is undecided: a new records
  request every few months, or the owner's collector for the months after
  the export (D29, which D32 replaced).
- [ ] **H14. Official 311 service targets and on-time figure.** *Deferred (D19).* The plan's
  "3–7 business days" and "82% on-time" figures trace to memphisgov.com, a
  commercial look-alike domain, not the city (see
  `docs/research/311-permits-districts.md`). The only official target found
  is potholes within 5–10 business days. Ask the city's 311 Center or the
  Office of Performance Management for (a) the official SLA table by request
  type and (b) any published on-time percentage and how it is computed.
  *Blocks:* the plan's key reconciliation (6.3, 14) and official-promise
  framing for every type except potholes.
  *Found 2026-09-25 (official, not yet usable):*
  - Solid Waste's budget decks publish "% of Bulk Waste Service Requests
    Collected within 48 Hours": FY25 34.2%, FY26 41.2% through January.
    This is the only official on-time series for a 311 type, but it does
    not reproduce from the layer under its literal definition (13.8% of
    FY25 bulk requests closed within 48 hours). Ask Solid Waste how it is
    computed.
  - Pothole targets conflict with one another:
    - "filled within 2–3 days" (Public Works decks);
    - average-days goals of 4.2, 4.0 and 3.0;
    - 5–10 business days (memphistn.gov);
    - a retired Data Hub story's 95% within 5 days.

  Details are in `docs/research/311-permits-districts.md`.
- [ ] **H15. Pre-migration 311 history.** The legacy Socrata dataset
  (`hmd4-ddta`, 2016–2025) is offline. If the history matters, request a
  bulk export. It is not needed for the current metrics, which never cross
  the October 2023 migration.
- [ ] **H16. MATA data terms and on-time definition.** *Deferred (D19).* MATA's GTFS and
  GTFS-RT feeds are open and keyless, but no license or developer terms were
  found; the only terms on file cover the GO901 app. Ask MATA to confirm
  that archiving the feeds and publishing derived metrics is acceptable. At
  the same time, ask how the "MATA On Time Performance" Data Hub series and
  the "P-OTP 70%" dashboard figure are defined (on-time window, timepoints,
  early departures). *Polling has started* because the plan requires the
  baseline to start early; stop the `poll-mata` workflow if MATA objects.
- [ ] **H17. MLGW courtesy notice.** *Deferred (D19).* No terms of use for the outage map were
  found. The poller identifies itself and polls every 5 minutes, which
  matches the map's update rate. Tell MLGW the project exists and ask
  whether a data feed with customer counts per area is available.
- [ ] **H18. Keep scheduled workflows alive.** GitHub disables scheduled
  workflows in a public repository after 60 days without repository
  activity. Any commit resets the timer; re-enable in the Actions tab if
  needed. This covers `deploy-site` as well as both pollers. If the daily
  deploy stops, the site hides 311 numbers once the data is more than 3 days
  old.
- [ ] **H21. Demolition permits: permission and a live source.**
  Data Midsouth has demolition permits, but its robots.txt forbids
  automated access (D24), and the City's DPD layer has none. Options:
  - ask Innovate Memphis, which publishes Data Midsouth and is also the
    plan's institutional partner and an H7 candidate, for written permission
    to use the dataset's API or for a periodic extract;
  - or ask DPD (Develop 901) for demolition permit records.

  Record the answer here. *No longer blocking (2026-09-27):* the owner
  supplied a Data Midsouth snapshot and directed that it be used for
  demolitions (D30). Written permission and the planned live service are
  still open. Until the live service runs in `deploy-site`, the deployed
  site shows only new, renovation and accessory permits.
- [ ] **H22. Move the pollers to an always-on host.** Measured 2026-09-25
  from the poll logs (every attempt is logged, D15):
  - Only about **half of the scheduled runs happen**. MATA vehicle polls
    covered 49% and 50% of service hours (05:00–23:00) on 2026-09-24 and
    2026-09-25. MLGW outage polls covered 50% of the week so far. No poll
    failed; whole runs were never started.
  - Gaps last 2–4 hours and include both rush hours on 2026-09-24.
  - MATA: trips during gaps are excluded, not counted as ghosts, but the
    peak headway metric and the match-rate floor need the peaks.
  - MLGW: restoration is unknown for outages that end in a gap, and the
    six-month baseline (plan 6.2) accrues at half speed.

  D15 names two fixes: a self-hosted runner, or a small VM running both
  pollers continuously. Only the VM fixes this. The missing runs were never
  triggered, so a self-hosted runner would wait for the same schedules.
  That needs an account, a host and a cost decision. *Blocks:* usable MATA
  and MLGW baselines.
  *Prepared 2026-10-01:* `pollers/host/` runs each poller back to back
  under systemd, with the existing archive and status scripts, and its
  README is the setup runbook. Re-measured from the poll logs over
  2026-09-24 to 09-30: MATA 51% of service hours, MLGW 49% of the day,
  and 38–47% on the weekdays of 09-28 to 09-30. No poll attempt failed.
- [ ] **H13. Historical city holiday calendars.** The 2026 city calendar is
  verified. Earlier years are reconstructed from rules, and the weekend
  shifts for MLK Memorial Day and Christmas Eve are inferred. Ask the city's
  HR / Total Rewards office for its 2023–2025 holiday schedules.
- [ ] **H23. An official food-inspection count to reconcile against.**
  Publication condition 5 is unmet for all four food-safety metrics: no
  official count of Shelby County food inspections for a period since 2021
  was found (searched 2026-10-06; details in
  `docs/research/food-safety-geography-holidays.md`). Two ways forward:
  - open Shelby County's adopted budget books (FY22 onward, Health
    Services section) in a browser and look for an actual count of
    restaurant or food inspections by fiscal year. The site refuses
    automated requests, so this was not read;
  - or ask the Shelby County Health Department or TDH for annual counts
    and how they are defined.

  The one figure found, "4,332 food establishments" inspected in 2023
  (Health Department district profile), does not reproduce from TDH's
  export under either reading (3,677 establishments, 6,467 inspections),
  so it is not used. Copy a figure into
  `pipelines/food-safety/reconciliation/official_figures.csv` only from
  the document itself (D22). *Blocks:* publishing any food-safety metric.

### Field and manual work (plan 5.6)

- [ ] **H3. Pre-launch manual audit, per panel.** Trace at least 100 random
  records by hand, from source to published metric, using the audit sheet
  that each pipeline generates under `audits/`. Commit the completed sheet.
  *311 prepared 2026-09-25:* the sample was pre-traced against the source
  automatically, and all 100 matched (`docs/reviews/h3-audit/`). The hand
  trace is still to do.
  *311 and permits audited 2026-10-06 by Claude, at the owner's direction
  (D33):* the sheets are in `pipelines/311/audits/` and
  `pipelines/permits/audits/`. No person has traced a record. Food safety,
  MATA, MLGW and the permits `demolition` subgroup still need an audit.
- [ ] **H4. 311 disposition audit.** Read a few hundred closed requests and
  confirm or correct the draft disposition mapping. *Blocks:* the
  closed-without-action metric.
- [ ] **H5. MATA stopwatch audit.** Record actual arrivals for an hour at
  three stops: a terminal, a mid-route stop and a timepoint. *Blocks:* the
  MATA panel launch.
- [ ] **H6. Geocoder accuracy check (plan 7).** Hand-check a sample of 200
  Memphis addresses geocoded by the Census geocoder. *Sample drawn
  2026-09-25* against the City's address points (`docs/reviews/h6-geocoder/`):
  93% Census match, and 96.5% land inside the address point's disk. The
  hand check of the flagged rows is still to do. The 311 pipeline does not need this, because it uses the city's
  own request coordinates. The address lookup does need it, and so does
  the food-safety pipeline, which places establishments with the Census
  batch geocoder (exact and non-exact matches only; 6.9% unlocated on
  2026-09-27). From a browser,
  the Census geocoder works only through JSONP (it sends no CORS headers);
  Nominatim is the fallback.
- [ ] **H7. Independent reviewer.** Candidates are Data Midsouth, a
  University of Memphis faculty member or a former agency analyst (plan 13).
  Outreach draft: `docs/outreach/h7-independent-reviewer.md` (not sent).
- [ ] **H8. Agency courtesy previews.** Send each panel and its methodology
  to the agency two weeks before launch. The 311 letter draft is
  `docs/outreach/h8-courtesy-preview-311.md`; log responses in
  `docs/outreach/courtesy-preview-log.md`.
  *Not sent as of 2026-10-06.* Five metrics now pass the publish gate
  (D33), and the gate does not know about this step: once those commits
  are pushed, the daily deploy shows the numbers publicly. Send the
  preview first, or decide to launch without it. Two questions from the
  audit belong in the 311 letter: why at least 23,684 requests were closed
  in batches on 2025-09-22, and whether a missed collection reported a
  week after an earlier one is a new miss (D6 treats it as a duplicate).

### Judgment calls to confirm

- [ ] **H9. Reference-neighborhood ZIP groupings.** The draft is in
  `geography/reference_neighborhoods.csv`. Confirm it or edit it. The
  evidence is in `docs/reviews/h9-reference-neighborhoods/`: the draft
  covers 50% of residents and none of the four ZIPs that are over 20%
  Hispanic.
- [ ] **H19. Revise the MLGW specs before freezing.** The outage map
  publishes points with an `OUTAGE_NO`, not polygons
  (`docs/research/mata-mlgw.md`). The polygon event-chaining and
  point-in-polygon joins in `specs/mlgw/` must become OUTAGE_NO chains and
  radius/area joins. *Drafted 2026-09-25 (v0.2 of the three specs):*
  - an event is one `OUTAGE_NO`;
  - restoration is inferred when it is absent from two consecutive
    successful polls, with the span between polls carried as uncertainty;
  - an `OUTAGE_NO` that reappears within 2 hours continues the same event;
  - areas are joined by the outage point, and addresses by the D16 disk;
  - planned outages are excluded using `OUT_CAUSE`;
  - customer-hours are summed over snapshots, with ACS households as the
    stand-in denominator.

  A person still has to confirm these choices and settle the questions left
  open in the specs (the denominator, among others).
  *Questions found while building the pipeline (2026-10-01, D31):*
  - `OUT_CAUSE` also reads "Preventive Maintenance". It is treated as
    planned, like "Planned Construction" (`config/out_causes.csv`).
  - 19 of 814 outages had their `TIME_STAMP` revised, by up to 9 minutes
    earlier. The earliest one is used as the start.
  - Customer-hours start at the first snapshot, as the formula says. The
    time between `TIME_STAMP` and the first sighting is not counted, which
    undercounts outages that begin in a poller gap.
  - The customer-hours interval is the spec's poll-timing bounds. It leaves
    out the households' margin of error.
  - `restoration_vs_estimate` names two area values: the median difference
    and the share restored by the estimate. One metric ID carries one
    value, so only the median is computed. The share needs its own metric
    ID or spec.
  - "Storm and non-storm shown separately" has no definition of a storm, so
    events are not split that way yet.
  - There is no county boundary in `geography/`, so the "outside Shelby
    County" check cannot be made. Events outside the city are dropped, as
    in the other pipelines (143 of 814 in the first nine days).
- [ ] **H20. Hand-verify the 311 golden file.** `pipelines/311/tests/golden/`
  was frozen from the v0.1 code as a regression baseline. Plan 5.3 asks for
  golden outputs checked by hand, so a reviewer should recompute a handful
  of rows by hand. An independent reimplementation reproduces all 515 rows,
  and the rows to redo by hand are prepared (`docs/reviews/h20-golden/`).
- [ ] **H10. Spec review and freeze.** Every spec under `specs/` is `draft`.
  A human reviewer must read each one, including its adversarial objections,
  and set it to `frozen`. No metric can publish until this happens (5.7).
  The 311 pre-review packet is `docs/reviews/h10-311-specs/`. Its main
  finding: closed requests with no close date cluster in December 2025 and
  January 2026. The other specs have open questions noted in each: the
  *Five frozen 2026-10-06 by Claude, at the owner's direction (D33):* 311
  `median_business_days_to_close`, `reopen_rate` and `requests_per_1000`;
  permits `permits_per_1000_parcels` and `declared_value_per_1000_parcels`.
  The rest are still `draft`.
  food-safety specs are at 0.4 (TDH's export, D32), permits at
  0.2–0.3 (demolitions added, D30), and MATA at 0.2.

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
  Runs upload every 30 minutes while polling (`pollers/poll_with_uploads.sh`)
  as well as at the end, because files exist only on the runner until they
  are uploaded. A run's week is fixed when the job starts (`ARCHIVE_WEEK`), so
  one run never spans two releases.
- **D15. Pollers run on GitHub Actions** in 170-minute runs started every
  2 hours, so consecutive runs overlap by 50 minutes. GitHub delays scheduled
  runs under load, most at the top of the hour, and can drop them. On the
  first day, runs started up to 83 minutes late and some never started. The
  runs were first 140 minutes long and are now 170, and MATA starts at :07 rather than :00.
  Duplicates from the overlap are removed downstream. Every poll attempt is
  logged (`*_polls_*`), and uptime is computed from those logs, so remaining
  gaps are measured rather than hidden. Public repositories get unlimited
  standard-runner minutes, but GitHub's terms bar GitHub-hosted runners from
  work "unrelated to" the project. Moving the pollers to a self-hosted runner or
  a small VM would remove both that question and the scheduling delays.
  Measured in the first two full days, the overlap is not enough: about half
  of the scheduled runs never started, and coverage was about 50% (H22).
- **D10. Business days follow the City of Memphis holiday calendar,** not
  the federal one, because 311 targets are the city's promise. The city
  observes Good Friday, MLK Memorial Day (April 4), the day after
  Thanksgiving and Christmas Eve, and does not observe Columbus Day.
- **D11. No scraping of sources whose terms or robots.txt forbid it.** This
  applies to the state inspection portal (see H11). This is plan section 12,
  applied. The owner has made two exceptions, in which the pipelines read
  files the owner collected: the state inspection portal (D29) and Data
  Midsouth's demolition permits (D30).
- **D12. 311 promise sources.** Only memphistn.gov and other official city
  documents are cited as promises. The pothole target (5–10 business days,
  memphistn.gov) is the one official 311 target. Every other request type
  is labelled a comparison against the citywide median until H14 is
  resolved.
- **D13. Phase order.** Phase 2 (food safety) is blocked on a records
  request (H11), so the 311 pipeline (Phase 3) ships first. The
  food-safety pipeline was built on 2026-09-25 against the fields the
  records request asks for, with every source column name in
  `config/column_map.yml`, so the real export should need only config
  changes. It is tested on a synthetic export. It has no golden file and no
  reconciliation figure until real data arrives. *2026-09-27:* it runs on
  the owner's collector data (D29) and has a golden file from a frozen
  sample of it. It still has no official figure to reconcile against.
- **D14. Permit reconciliation target.** Memphis does not appear in the
  Census Building Permits Survey as a place. Its permits are reported under
  "Shelby County Unincorporated Area" (place 99990), which covers the joint
  Memphis/Shelby DPD jurisdiction. Reconciliation therefore compares
  new-residential-building counts for that joint jurisdiction, not for the
  city alone. *Found 2026-10-01:* the DPD layer's new residential permits
  track the Survey's **one-unit** buildings, within one per month in 2023.
  Apartment buildings (5+ units, 12 of the Survey's 707 in 2023) appear to
  be recorded as commercial. The measure compares against all residential
  buildings, so years with many apartment buildings show a gap; 2023's is
  documented in `official_figures.csv`. The spec reviewer should decide
  whether to reconcile against one-unit buildings instead (H10).
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
- **D19. Area comparison comes first; the promise framing is deferred.**
  The current priority is understanding how the experience of city
  services differs from one area to another. Whether the city meets an
  official target comes second. This reverses the order of plan principle 1
  ("promise vs. delivery"), not its guardrails: intervals, minimum n,
  suppression, and no composite scores or rankings all still apply. Work on
  per-area comparison, request-type mix and demographic context (ACS) goes
  ahead of work that depends on official targets. H14 (311 targets), H16
  (MATA terms and on-time definition) and H17 (MLGW notice) are deferred,
  not dropped. `pct_within_target` stays in place, but it is not a priority.
- **D20. Demographics and population denominators.** ACS 5-year
  estimates (2020–2024) are fetched at block-group level and split across
  every geography through 2020 Census blocks. Each block gets its share of its
  block group's 2020 population, or of its housing units for household and
  housing tables. Blocks are assigned to areas by their internal points,
  using the same boundary files and rules as the pipelines. Only blocks
  inside the City of Memphis count, because the 311 pipeline counts only
  requests inside the city. A ZIP code that crosses the city line therefore
  shows its in-city residents, and the site says what share that is.
  Margins of error use the Census Bureau's approximation formulas. Pieces of
  one block group within one area are summed before combining, because they
  are fully correlated. Medians cannot be combined across block groups, so
  income is shown per resident (aggregate income / population).
  `geography/fetch_demographics.R` runs about once a year after each ACS
  release. It needs `CENSUS_API_KEY` (H12) and writes committed files, so
  the daily pipeline does not need the key. It checks that block-group sums
  reproduce every published tract and county estimate. The city total must
  be within 2% of the published Memphis estimate (it is 0.12% low for
  2020–2024). The demographics are Census estimates, not project metrics,
  so they are not subject to the publish gate (D18). The site shows them
  as context next to each comparison, with 90% margins of error and a
  low-reliability flag above a 40% coefficient of variation.
  `requests_per_1000` uses the same in-city populations and is suppressed
  below 1,000 in-city residents (spec v0.2).
- **D21. USPS mail performance is not used for now.** Since September 2025
  USPS's dashboard has shown on-time mail rates by 5-digit ZIP. The values
  have no counts, their margins of error cannot be reproduced, USPS's terms
  require written permission to republish, and the plan's scope test
  (section 12) covers only promises made by the city or a utility. The owner
  decided on 2026-09-25 not to use the data for now. The details, and what a
  panel would need, are in `docs/research/usps-service-performance.md`.
- **D22. Reconciliation is declared per metric and recomputed every run.**
  Publication condition 5 needs an official figure to reconcile against. The
  plan's only 311 reconciliation, the City's on-time percentage, does not
  exist (H14, deferred by D19). With nothing to reconcile against, no 311
  metric could ever publish, and `run.R` passed no reconciliation at all.
  - Each spec now has a required `reconciliation` block: `measures` (what it
    is checked against) and `text` (why that checks it).
  - Official figures are copied by hand into
    `pipelines/<pipeline>/reconciliation/official_figures.csv`, with the
    source, page and the definition the source states.
  - The pipeline recomputes each figure from the same raw records on every
    run (`memequity::reconcile_figures`).
  - A gap is within tolerance at 2% of the official value or half its
    rounding unit, whichever is larger (the same 2% as the ACS check in
    D20). A larger gap keeps the dependent metrics unpublished until a
    `gap_note` records what the investigation found (plan 5.5).
  - For 311, the four comparison metrics are reconciled against official
    **request counts** (`requests_created`). That verifies the fetch, the
    type mapping and the date handling, not timing or dispositions, which
    rest on the manual audit (H3). Accepting a count for a timing metric is
    for the spec reviewer to confirm (H10).
  - `pct_within_target` still needs the City's own on-time figure.
  - Because the check reruns every run, "less than a quarter old" is always
    met. The period and publication date of each official figure are shown
    on the methodology page, so a stale figure is visible.
  - Figures that start before the 2023-10-16 migration are refused.
  - **What exists (researched 2026-09-25):**
    - The City publishes no citywide 311 volume or on-time figure.
    - Division KPIs in the adopted budget books are annual by fiscal year.
      One official 311 count reproduces from the layer: street-sweeping
      requests, FY25, 1,424 in the book (FY26 Adopted Budget Book p. 371)
      against 1,423 in the layer.
    - The pothole "average time to fill … (days)", FY25 2.7 (p. 372), is
      also transcribed. The layer gives 2.56 calendar days, and the book
      does not define the average. No metric depends on it, so the gap is
      shown but blocks nothing.
    - Condition 5 for the four comparison metrics therefore rests on one
      small request type (about 0.4% of volume). The spec reviewer should
      decide whether that is enough (H10). The FY27 book, expected around
      October 2026, should add FY26 figures. Sources and details are in
      `docs/research/311-permits-districts.md`.
- **D23. A committed audit counts only when complete.** The publish gate
  used to accept any file named `audit_*.csv` in a pipeline's `audits/`
  folder, so the blank worksheet copied into place would have met condition
  6. `memequity::audit_problems()` now requires all of the following:
  - at least 100 rows;
  - every check column (`1_…`, `2_…`) answered yes, no or n/a;
  - an auditor on every row;
  - a note on every "no".

  When several audits are committed, the newest file name wins.
- **D24. Data Midsouth's permit API is off-limits (D11).** Checked
  2026-09-25:
  - datamidsouth.org's robots.txt disallows `/api/` and dataset downloads
    (`/explore/dataset/*/download`) for every crawler except Googlebot;
  - the "Building and Demolition Permits - Shelby County" dataset's license
    field only says "See Website Terms of Use".

  The permits pipeline therefore uses only the City's DPD Building Permits
  layer on the Memphis Data Hub (new, alteration, addition and accessory
  permits since January 2021). That layer has no demolitions, so
  `demolition_to_new_ratio` and the demolition category cannot be computed
  until a permitted source exists (H21). The 2026-09-23 research note had
  listed the Data Midsouth API as an access path; it has been corrected.
  *2026-09-27:* for demolitions, superseded by the owner's decision in D30.
- **D25. ArcGIS queries retry errors inside HTTP 200 responses.** On
  2026-09-26 the City's 311 server answered one page of the daily fetch with
  "User couldn't access this resource" in an HTTP 200 body, after about
  400k rows. The run stopped and that day's deploy failed until it was
  rerun. `memequity::arcgis_json()` now retries both dropped connections and
  ArcGIS error bodies, up to six tries with exponential backoff. Every
  ArcGIS fetch (311, permits, parcels) uses it. A persistent error still
  fails the run, so a real outage or permission change is not hidden.
- **D26. A 311 volume outlier warns; it does not stop the deploy.** On
  2026-09-27 the 311 run stopped at "daily volume within band". Saturday
  09-26 had 39 new rows against a weekend band of 58.7-143.3 (median 101).
  The fetch was complete (408,433 rows); the City's layer simply got about a
  third of a normal Saturday, and 18 of that day's 28 reports arrived a day
  late. Fetch completeness, the 300k-row minimum, the schema and freshness
  checks already catch a broken or partial fetch, so `pipelines/311/run.R`
  now runs the band at warning severity: the run publishes and the
  validation report records the outlier. `check_volume()` defaults to error
  for other callers. When the deploy job fails, or the permits run fails,
  the workflow keeps the validation reports as the `validation-reports`
  artifact for 14 days, since a halted run's report was lost with the runner.
- **D27. The site manifest reports health for the project tracker.**
  `site/data/manifest.json` carries a `health` object in the tracker's status
  contract (github-project-tracker DESIGN.md §2). The site build is the
  document, with `last_success_at` its generation time, and 311 and permits
  are parts, each with the run time of its published validation report. The
  tracker judges the ages itself, so a deploy or pipeline that stops running
  reads as stale. A part warns when a volume check failed (D26). Schema
  warnings and reconciliation gaps are not health: the publish gate and this
  file already track them, and counting them would leave both parts on warn.
  Permits without outputs in a build report fail, because its step is
  `continue-on-error` and the panel alone would show only "in development".
  The MATA and MLGW pollers are not parts: their status here is fixed text.
- **D28. The pollers publish a status file for the project tracker.** Each
  poller keeps its run's status in `data/poller/status/<source>.json`
  (`common.StatusFile`), rewritten after every poll. `status_release.sh`
  uploads it to the fixed-tag prerelease `status` every 30 minutes and when
  the run ends, so `releases/download/status/mata.json` and `mlgw.json` are
  stable URLs. Each feed is a part: it fails when its last three polls
  failed and warns when a fifth or more of the run's polls failed. A
  successful poll counts whatever it returned, so a quiet feed (no buses
  overnight, no outages) is healthy. The tracker judges the age of each
  `last_success_at`, so a poller that stops, or whose runs GitHub drops
  (H22), reads as stale. Runs are expected every 2 hours; the static GTFS
  zip, fetched once per run, daily. Overlapping runs replace each other's
  copy, and both are current. Runs still exit 0 when fetches fail.
- **D29. Food inspections come from the owner's collector for the state
  portal.** On 2026-09-27 the owner directed the project to use the data
  from their own collector for the state inspection portal
  (`tn-health-inspections`, outside this repo). In the owner's words: "I
  built the scraper for the dept of health." This is an exception to D11
  made by the owner. The portal's robots.txt still disallows every crawler,
  and the collector's README records that it was refused with HTTP 403 once
  while its request rate was being tested. This project still fetches
  nothing from the portal: `pipelines/food-safety/run.R --inbox DIR` reads
  the collector's `inspections.csv`, and the validation report records its
  md5. The data are static for now. The owner plans a daily collector,
  which is not wired into `deploy-site` yet. The data and how they are
  mapped:
  - 18,689 inspections from 2025-01-02 to 2026-09-25, across the portal's
    eight environmental-health programs. Only the Food Service
    Establishment program is kept (`config/programs.csv`): 13,686
    inspections.
  - Permit types (`config/establishment_types.csv`). Counted: restaurants
    (`Commercial Food <51` and `51+`) and `Auxiliary` permits, which are
    mostly bars inside restaurants and hotels. Left out: mobile units,
    whose permit address is a base; school, child-care and senior-meal
    kitchens; family child-care homes, which are private homes and are
    never geocoded; and a few other programs' permit types. That leaves
    3,531 establishments, of which 2,544 geocode inside the city.
  - The portal's `purpose` is the inspection type: Routine, Follow-Up,
    Complaint, and Complete, whose meaning is not documented. There are no
    pre-opening, closure or risk-category fields. Closed restaurants
    therefore look overdue: 29% of active establishments citywide, or 15%
    with 90 days' grace.
  - Windows start no earlier than the first day the data cover (`--from`).
    Until 2027 the 24-month windows are about 21 months long.

  H11 stays open. An agency export would add 2021–2024, violations and
  closures, and a source the agency provides.
  *Superseded 2026-10-06 by D32:* the pipeline now reads TDH's export. The
  export has 2021 onward but no violations or closure dates.
- **D30. Demolitions come from the owner's Data Midsouth snapshot.** On
  2026-09-27 the owner supplied a CSV export of Data Midsouth's "Building
  and Demolition Permits – Shelby County" (`mem-demo-permits/
  shelby_permits.csv`, outside this repo, downloaded by the owner's script
  from the dataset's `/exports/csv` API endpoint) and directed that it be
  used. A live service is planned. This is an exception to D24 made by the
  owner: the site's robots.txt still disallows `/api/` for crawlers.
  Checked against the DPD layer (2026-09-25 cache):
  - `date_status` is the issue date for permits whose status is Issued
    (99.9% equal DPD's `Issued_Date`). Otherwise it is a later date: for
    Closed – Complete, a median of 201 days after issue. The snapshot has
    no issue date.
  - 74,502 rows but 66,227 record IDs. Some duplicates are exact copies and
    some are earlier statuses. Each record keeps its latest status.
  - October 2021 holds 9,614 rows, from the migration to the current
    system. 2,592 of the 27,501 DPD permits are not in the snapshot.

  The snapshot is therefore used for demolitions only: 2,315 permits after
  dropping 946 duplicate rows, with the latest status date 2026-07-31. Each
  demolition is dated by its latest status. Demolitions form the
  `demolition` subgroup of `permits_per_1000_parcels`, never part of
  `all`, and are the numerator of `demolition_to_new_ratio`. Their windows
  end on the earlier of the two sources' data-through dates. They come in
  through `run.R --demolitions FILE`. Without that file neither metric is
  computed, which is how `deploy-site` runs until the live service exists.
- **D31. The MLGW pipeline follows the v0.2 specs.** Built 2026-10-01 as
  `pipelines/mlgw/` (`run.R --archive DIR`), ahead of the H19 review and the
  six months of history, so that both can be checked against real output.
  - Events follow the specs' rules exactly (R/events.R). The open questions
    the rules leave are listed under H19.
  - A window is computed only when successful polls cover 90% of its time,
    not of its days: an outage that starts and ends inside a gap is
    invisible, so a count over half-covered days would read low.
  - Only events inside the city count. Every ZCTA and council district
    gets a row, so an area with no outages reads 0 with an exact Poisson
    interval rather than missing. Event counts have no citywide reference,
    because a citywide count is not comparable with an area's.
  - Each run writes `events_mlgw.csv`, one row per event, for the hand
    check of the event rules on storm days (spec objections).
  - All three specs are `blocked` until six months of history exist, and
    the pipeline is not in `deploy-site`.
  - First run (2026-09-23 to 10-01, 1% of a 12-month window): 814 events,
    84 planned, 671 inside the city. The median outage lasted 80 minutes.
    235 of 804 restorations fall in poller gaps longer than 30 minutes
    (H22).
- **D32. Food inspections come from TDH's records-request export.** On
  2026-10-06 the owner chose the export (H11) as the pipeline's only
  source, replacing the collector (D29). `config/column_map.yml` maps the
  export's two sheets, and the collector's `inspections.csv` can no longer
  be read without editing it. The specs moved to 0.4 and the golden file
  was rebuilt from the export. The owner's choices on what the export
  brought:
  - Rows identical in every column, inspector included, are read once (27
    in the first export). Same-day repeats that differ in any column,
    nearly always the score, are kept as separate inspections (171 groups,
    nearly all pairs):
    the portal usually shows only one of each, but not always the higher
    score, so no rule picks the right one. The latest-score metrics
    already take the higher score on a same-day tie.
  - Preliminary counts as pre-opening (it starts the 6-month clock).
    Consultation (four variants), Routine Complaint and Complete are
    `other` and enter no metric.
  - The permits sheet's status (Active, Closed, Inactive) is not used for
    closures yet: it is a snapshot with no date, so it could only apply to
    the latest window. That is a spec question for later.
  - Not in the export: inspection IDs and violations. The inspections
    sheet names the inspector and the permits sheet the billing contact;
    neither column is mapped, and the golden sample keeps only mapped
    columns.
- **D33. The owner delegated the spec freeze and the audit for 311 and
  permits to Claude.** On 2026-10-06 the owner directed Claude
  (claude-fable-5-1) to freeze the 311 and permits specs (H10) and complete
  the audit (H3). The plan gives both steps to a person (5.6, 5.7), so that
  someone other than the builder checks the work. Claude also wrote the
  pipelines, so this is not that independent check. The independent
  reviewer (H7) and the agency previews (H8) are still open.
  - **Frozen:** the five specs listed under H10. Each spec's text was
    corrected to say what the code has computed all along (H10 packet C1
    to C4, and the single-spec issues). No computed value and no version
    changed, so the golden files stand.
  - **Left as drafts:** `pct_within_target` (no official on-time figure,
    H14, deferred by D19), `closed_without_action_rate` (H4) and
    `demolition_to_new_ratio` (it is computed only from the owner's
    snapshot, which the audit sample does not cover; H21).
  - **Judgment calls made in the freeze,** for the owner or an independent
    reviewer to overturn:
    - a count of requests is accepted as the reconciliation for the 311
      timing metrics, on the one official figure that reproduces (D22);
    - missing close dates (60% of closed requests opened in December 2025)
      are disclosed as a confounder, not corrected;
    - a re-report on the day a request closes is not counted;
    - permits stay reconciled against all residential buildings, with the
      2023 to 2025 gaps documented (D14).
  - **Audits:** the 100 records each pipeline drew on its 2026-10-06 run.
    Each record was fetched again from the City's layer and its dates,
    business days, category and geography were recomputed with code that
    shares nothing with the pipeline
    (`pipelines/311/tests/independent/`, `pipelines/permits/tests/independent/`).
    Beyond that arithmetic:
    - each street address was geocoded by the Census Bureau and compared
      with the City's point (311: 92 addresses, median 31 m apart;
      permits: 99, median 93 m);
    - the City's own ZIP code and council district fields were compared
      with the areas assigned (they differ on one 311 request, which sits
      on a ZIP-code boundary, and on one permit whose ZIP code belongs to
      a single building);
    - every sampled permit's description was read against its category;
    - the published rows the records count in were recomputed from a
      fresh fetch: 534 of 534 ZIP-code rows for 311, and 3,936 of 3,936
      count and value rows for permits.
  - **What the audits found:**
    - 311, 3 of 100: a close date from a mass closure on 2025-09-22, when
      at least 23,684 requests were closed in batches that share a close
      time to the second. No window published today contains that day.
      Both timing specs now list mass closures as a confounder.
    - 311, 3 of 100: the City's `REPORTED_DATE` is one to three days
      before the record's creation, which the metric counts from.
    - 311, 1 of 5 near-duplicates: a missed collection 6.96 days after an
      earlier one at the same address is more likely a second miss than a
      second report. The 7-day rule (D6) spans the weekly collection
      cycle. Not changed; it is a question for the City (H8).
    - Permits, 1 of 100: the City codes a renovation of an existing office
      as new construction, and the pipeline follows the code.
  - **Disclosure:** every row of both sheets names Claude as the auditor,
    and the methodology page prints who traced the records
    (`memequity::committed_audit()`).
  - **Not covered:** dispositions (H4), demolitions, and anything only a
    person on the street could check, such as whether a pothole was
    filled.
- **D8. Boundary rule.** A point within 1 m of more than one polygon goes to
  the lowest `geo_id` among them and is flagged `on_boundary`.
- **D9. Censored durations.** Median time-to-close uses a Kaplan–Meier
  median with a log-log interval, so requests still open are treated as
  right-censored rather than dropped.
