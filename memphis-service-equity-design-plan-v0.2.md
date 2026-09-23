# Memphis Service Equity Project — Design Plan

*Working title: "Does Memphis work the same for everyone?"*
*Draft v0.2 — September 2026*

---

## 1. The question

**Do the basic systems Memphians depend on deliver what they promise, and does the answer change depending on where you live?**

Every city service makes an implicit or explicit promise: the bus comes at 8:12, the pothole is filled in 3–7 business days, power is restored by the estimate on the outage map, the restaurant on the corner passes inspection, the block is being maintained and invested in. Each of those promises is measurable, each is spatial, and each is currently reported (if at all) as a single citywide number.

This project measures promise-vs-delivery for five systems at the level of a resident's address and lets people compare their answer to the rest of the city.

## 2. What this is and isn't

**It is:**
- An address lookup: enter an address, see five service-reliability metrics for the area around it, each compared against the citywide median and a few reference neighborhoods, each with its uncertainty shown.
- A neighborhood comparison view: pick two ZIPs or council districts and see the same five metrics side by side.
- A set of five independent, tested, documented data pipelines that anyone can inspect, rerun, and reuse.

**It is not:**
- A composite "livability score." Collapsing five systems into one number invites arguments about weights and reads as editorializing. The five metrics stand side by side; the pattern speaks for itself.
- A crime map, school ranking, or walkability score. Those exist (SpotCrime, Niche, Walk Score, the city's Crime Analytics dashboard). This covers what nobody covers: whether the services around you actually function.
- A real-time tool. Everything here is *historical* reliability. Real-time bus positions and live outages already have apps.

## 3. Audience and use cases

| Who | What they're asking | What they do with the answer |
|---|---|---|
| Renter or buyer comparing neighborhoods | "What's it actually like to live at this address?" | Checks an address alongside Zillow and a crime map |
| Resident with a 311 ticket that's been open for weeks | "Is this normal, or is my street getting ignored?" | Screenshots the comparison, posts it, calls their council member |
| Neighborhood association / CDC | "Is our area getting worse or better?" | Uses the trend view in meetings and grant applications |
| Council member or candidate | "How does my district compare?" | Cites it in budget hearings |
| Local reporter (Daily Memphian, WREG, MLK50, Flyer) | "Is there a story here?" | Uses the pipelines and downloads as source data |
| Agency analyst (MATA, MLGW, 311, Health Dept) | "Is this number right?" | Reads the methodology, files a correction, or concedes the point |

The first two are the mass audience; the middle three are the amplifiers. The last is the adversary, and the project is designed for them: **every number should survive a hostile analyst with access to the same source data.**

## 4. Design principles

1. **Promise vs. delivery, never just delivery.** Every metric is framed against a stated standard — the schedule, the city's published 311 timeframes, MLGW's estimated restoration time, a passing inspection score. Where no official promise exists, the citywide median is the reference and the metric is labeled as a comparison, not a compliance measure.
2. **Address is the unit.** Aggregates by ZIP and council district are the fallback and the comparison layer, but the front door is "type your address."
3. **Five metrics, not one.** No index, no weights, no ranking of neighborhoods. Side-by-side comparison only.
4. **Every number carries its uncertainty.** Sample size, time window, and a confidence interval travel with every value. Small samples are suppressed, not rounded into false precision.
5. **Definitions before data.** A metric's definition, exclusions, and thresholds are written, reviewed, and frozen before the first number is published. Changing a definition creates a new versioned series; it never silently rewrites the old one.
6. **Reproducible and boring.** Every pipeline is a public repo, runs on a schedule, has tests, and writes flat files. A stranger should be able to clone it and get the same numbers.
7. **Each pipeline is usable alone.** The project ships incrementally; the first pipeline is a standalone product on day one.

## 5. Rigor and validation framework

This section is the core of the project. The five pipelines in Section 6 each apply it. The framework has six layers; a metric is not published until it passes all six.

### 5.1 Layer 1 — Definition review

Before any code:

- Write a **metric specification** for each metric: plain-English definition, exact formula, unit, time window, geographic unit, inclusion and exclusion rules, minimum sample size, the promise it's measured against (with a link to the source of that promise), and known confounders.
- **Adversarial read.** For each spec, write down the three most damaging objections an agency analyst would raise, and either answer them in the spec or change the metric. Examples: "your on-time window is stricter than ours," "you're counting duplicate 311 tickets as separate failures," "declared permit value is meaningless."
- **Sensitivity plan.** Identify every arbitrary threshold (on-time window, walking radius, "low score" cutoff) and commit to publishing the metric under at least two alternative thresholds so readers can see whether the conclusion depends on the choice.
- Specs live in the repo as `specs/<pipeline>/<metric>.md` and are versioned. The methodology page is generated from them.

### 5.2 Layer 2 — Source data validation

Every fetch runs a validation suite before anything downstream touches the data. Failures halt the pipeline and open an issue; they never produce a partial publish.

- **Schema contract:** expected columns, types, and allowed value sets. Any new category value (a new 311 status code, a new permit subtype) fails the run until it's mapped.
- **Freshness:** the newest record must be within the expected lag; a source that stops updating is flagged, and the published panel shows "data current through <date>" prominently.
- **Volume bounds:** daily record counts must fall within a rolling band (e.g., ±3 MAD of the trailing 60 days). A sudden drop usually means a broken scraper or a source outage, not a real change.
- **Duplicate detection:** exact and near-duplicate records (same location, same type, within a short window) are identified and their handling rule is documented per pipeline.
- **Geocoding quality:** every geocoded record carries a match quality field; records below a stated match level are excluded from spatial metrics and counted in a published "unlocated" figure.
- **Referential checks:** e.g., every observed MATA vehicle maps to a known route; every 311 request type maps to a known category.
- Implemented with `pointblank` (R) or `pandera`/`great_expectations` (Python); results written to a validation report alongside the data.

### 5.3 Layer 3 — Metric computation tests

- **Unit tests on every metric function** with hand-built fixtures whose correct answer is known. Fixtures include edge cases: empty windows, single observation, records straddling a window boundary, daylight-saving transitions, business-day vs. calendar-day counting, records with missing close dates.
- **Property tests:** metrics must be invariant to record order, must not change when duplicate records are added, must degrade to NA (not zero) when `n` is below the minimum.
- **Golden files:** a frozen sample of real source data with the metrics computed once by hand and checked; every pipeline change must reproduce the golden outputs.
- **Business-day logic** uses a single shared calendar (federal and city holidays) and is tested against the city's own published examples where they exist.

### 5.4 Layer 4 — Statistical treatment

- **Minimum sample size** per cell, set per metric and stated in the spec. Default: 30 observations for proportions, 20 for medians. Cells below the minimum display "insufficient data," never a number.
- **Confidence intervals on everything.** Wilson score intervals for proportions; bootstrap percentile intervals for medians. Displayed as a range next to the point estimate, and drawn on every chart.
- **Comparisons are only made between cells with overlapping windows and comparable `n`.** The UI refuses to put a 90-day cell next to a 12-month cell.
- **Medians, not means,** as the central reference. Every one of these datasets is heavy-tailed.
- **Small-area stability:** for ZIP- and hex-level cells, compute the metric over the smallest window that clears the minimum `n`, and label which window was used. A quiet neighborhood may legitimately show a 12-month figure where a busy one shows 90 days.
- **Seasonality:** where a metric has a known seasonal pattern (outages, 311 volume), the comparison reference is the same window in the citywide series, not the annual median.
- **Multiple-comparison awareness:** the site doesn't run hypothesis tests or declare "significant" differences. It shows intervals; if they overlap, the UI says the areas are not clearly different.

### 5.5 Layer 5 — External reconciliation

Each pipeline is checked against an independent published figure before launch and on a schedule after.

- **311:** reproduce the city's own citywide on-time percentage from the same data. If the project's method gives 82% citywide and the city says 82%, the neighborhood breakdowns inherit that credibility. If it doesn't, the discrepancy is investigated and documented before anything is published.
- **MATA:** reconcile observed trip counts against scheduled trip counts per route per day; reconcile against any on-time performance figures MATA reports to the National Transit Database or its board.
- **MLGW:** reconcile event counts and customer-hours against MLGW's reliability metrics (SAIDI/SAIFI — standard utility indices for outage duration and frequency) in its annual reports or TVA filings.
- **Health inspections:** reconcile weekly counts against WREG's published roundups; spot-check a sample of scores against the state site by hand.
- **Permits:** reconcile monthly counts against the Census Building Permits Survey figures for Memphis.
- Reconciliation results are published on the methodology page with the date and the size of any gap.

### 5.6 Layer 6 — Human audit and challenge

- **Manual audit before each panel launches:** a random sample of at least 100 records is traced end-to-end by hand from source to published metric, and the audit sheet is committed to the repo.
- **Disposition mapping audit (311 specifically):** a few hundred closed requests read by hand to establish what each status code actually means before "closed without action" is defined.
- **Independent review:** before launch, at least one person who did not build the pipeline reads the specs and tries to break the numbers. Ideally someone from the relevant agency or a local academic.
- **Courtesy preview:** each agency receives the panel and methodology two weeks before public launch. Not for approval; for accuracy. Responses and any changes made are logged publicly.
- **Standing correction channel:** a public issue tracker where anyone can challenge a number. Every challenge gets a documented response; accepted corrections produce a new data version with a changelog entry.
- **Post-launch drift review:** quarterly, rerun the reconciliations and re-audit a fresh sample.

### 5.7 What "published" means

A metric appears on the site only when:

1. Its spec is frozen and versioned.
2. Source validation passes for the current run.
3. Metric tests pass against fixtures and golden files.
4. Its `n` clears the minimum and its interval is computed.
5. Its reconciliation is current (within the last quarter) and any gap is documented.
6. Its pre-launch manual audit is committed.

Otherwise the panel shows what's missing and why.

## 6. The five pipelines

Each pipeline has the same shape: **fetch → validate → normalize → attach geography → compute metrics → test → write flat files + validation report**. They share one geography layer (Section 7) and one output schema (Section 8). Each subsection lists the metrics, the specific validation concerns, and the reconciliation target.

### 6.1 Transit reliability (MATA) — built from scratch

- **Promise:** The bus arrives at the scheduled time at the scheduled stop.
- **Source:** MATA's public real-time vehicle feed (TransLoc endpoints; or a GTFS-Realtime feed if MATA publishes one — confirm first) joined to MATA's GTFS static feed (schedule, stops, routes, trips). This is a new poller; nothing from prior work is reused.
- **Cadence:** Positions polled every 30–60 seconds; metrics recomputed nightly.
- **Metrics (per stop and per route, rolling 30/90 days):**
  - On-time %: arrivals within [−1, +5] minutes of schedule. The window is an industry convention, not MATA's; publish the metric under [−1, +5] and [0, +10] and, if MATA states its own standard, under that too.
  - Ghost-bus rate: scheduled trips with no observed vehicle within ±15 minutes of any timepoint.
  - Median headway gap during peak hours vs. scheduled headway.
- **Address join:** Stops within a 0.5-mile network walk (not straight-line) of the address; roll up to the routes serving those stops.
- **Validation concerns specific to this pipeline:**
  - *Trip matching is the whole ballgame.* Assigning an observed vehicle position to a scheduled trip is where every transit-reliability analysis goes wrong. Start with the simplest defensible rule (nearest scheduled trip on the same route and direction within a window), publish it, and measure match rate per route. Routes with a match rate below a stated floor (e.g., 85%) are not published until the rule improves.
  - *Arrival inference.* A position feed gives locations, not arrivals; "arrived at stop" must be inferred from proximity and heading. Test the inference against manual observation: stand at a stop for an hour with a stopwatch, record actual arrivals, compare. Do this at three stops of different types (terminal, mid-route, timepoint) before launch.
  - *Poller gaps.* Any minute where the poller was down is excluded from the denominator, not counted as a ghost bus. Uptime is published.
  - *Detours and service changes.* GTFS feed versions are tracked; metrics are computed against the feed version in force on that date.
- **Reconciliation target:** scheduled trips per route per day from GTFS vs. observed trips; MATA's own on-time performance if reported to its board or the National Transit Database.
- **Existing products displaced:** None. TransLoc, Moovit, Transit, and GO901 are all live-position only.

### 6.2 Power reliability (MLGW)

- **Promise:** Power stays on; when it doesn't, it's restored by the estimated time shown on the outage map.
- **Source:** MLGW outage summary map, polled every 5–10 minutes and archived. Confirm a JSON/GeoJSON endpoint before building; if the map is rendered polygons only, scraping is harder and terms of use must be checked first.
- **Cadence:** Poll continuously; metrics recomputed daily.
- **Metrics (per outage-map polygon, rolled up to ZIP/district, rolling 12 months):**
  - Outage events per year affecting the area.
  - Customer-hours out per 1,000 customers (if customer counts are exposed; otherwise event-hours, clearly labeled as such).
  - Restoration time vs. estimate: median actual minus estimated, and % restored by the first published estimate. Estimates get revised; the spec must state which estimate is the reference (first published is the honest choice).
  - Storm comparison: for a given event, how this area's restoration time compared to the citywide median for the same event.
- **Address join:** Point-in-polygon against the outage map's own geography; fallback to ZIP.
- **Validation concerns specific to this pipeline:**
  - *Event segmentation.* A single outage may appear as one polygon that splits, merges, or is re-drawn across polls. Define an event as a connected chain of overlapping polygons and test the rule on real storm days by hand.
  - *Poller gaps during storms* are exactly when they're most likely (the map slows down) and most damaging. Retry logic, gap logging, and exclusion from denominators are mandatory; a storm with more than a stated share of missed polls is flagged in the UI.
  - *No history exists before polling starts.* Launch this poller early and do not publish until at least six months and at least one significant weather event are in the archive.
- **Reconciliation target:** MLGW's reported SAIDI/SAIFI reliability indices in its annual report or TVA filings, at the citywide level.
- **Existing products displaced:** None. The MLGW map, WREG, and WKNO show current outages only.

### 6.3 City services (311)

- **Promise:** The city's published target timeframes — potholes 3–7 business days, streetlights 5–10, graffiti 3–10 — and an "82% on-time" citywide claim.
- **Source:** City of Memphis 311 service requests dataset on the Data Hub (Socrata API), all requests since January 2016.
- **Cadence:** Daily pull; metrics recomputed daily.
- **Metrics (per request type, per ZIP/district and per street segment, rolling 90 days and 12 months):**
  - Median business days from open to close.
  - % resolved within the city's published target (where a target exists).
  - Closed-without-action rate: closed with a disposition indicating no work performed — defined only after the manual disposition audit in 5.6.
  - Reopen rate: same address, same type, reopened within 30 days.
  - Request volume per 1,000 residents, shown separately and labeled as a demand measure, not a performance measure.
- **Address join:** Requests within 0.25 miles of the address; roll up to street, ZIP, district.
- **Validation concerns specific to this pipeline:**
  - *The October 2023 platform migration.* Treat pre- and post-migration data as separate series; test for schema breaks, status-code changes, and volume discontinuities at the boundary. Do not compute any metric across it.
  - *Duplicates.* Residents file the same pothole repeatedly. Define a dedup rule (same type, within 50 m, within 7 days) and publish both raw and deduplicated counts.
  - *Business-day counting* must match the city's convention. Test against any examples the city publishes.
  - *Open requests.* Requests still open at computation time are right-censored; the median must be computed with a survival-style estimator or restricted to a window old enough that nearly all requests have closed, and the spec must say which.
  - *Who calls.* Request volume is confounded by resident engagement. The UI never presents volume as a quality measure and the methodology says why.
- **Reconciliation target:** the city's own citywide on-time percentage, reproduced from the same dataset. This is the single most important reconciliation in the project.
- **Existing products displaced:** Partially. The Data Hub tracks individual requests; the city publishes citywide self-reported on-time %. Neither offers independent, neighborhood-level resolution times.

### 6.4 Food safety (health inspections)

- **Promise:** Food establishments are inspected regularly and pass.
- **Source:** Tennessee Department of Health restaurant inspection scores (Shelby County). Check for a bulk export, API, or open-records option before writing a scraper.
- **Cadence:** Weekly scrape; metrics recomputed weekly.
- **Metrics (per establishment, rolled up to walking radius and ZIP, rolling 24 months):**
  - Current score and score trend.
  - % of establishments in the area with a score below the state's follow-up threshold (confirm the threshold and cite it).
  - Reinspection rate: share of inspections that were follow-ups.
  - Time since last inspection vs. the state's required frequency.
- **Address join:** Establishments within 1 mile of the address.
- **Validation concerns specific to this pipeline:**
  - *Establishment identity.* Names change, chains share names, addresses are entered inconsistently. Build a stable establishment ID from normalized address + permit number where available, and test the matching on a hand-labeled sample.
  - *Inspection type.* Routine, follow-up, and complaint inspections are not comparable; the spec must state which are included in each metric.
  - *Scores are point-in-time.* A single bad day skews a small area; minimum-`n` rules and intervals apply.
  - *Spot-check* a random sample of scores each week against the state site by hand and log the agreement rate.
- **Reconciliation target:** weekly counts and the specific scores in WREG's published roundups.
- **Existing products displaced:** WREG's weekly high/low roundup and the state lookup site. Neither offers a map, per-restaurant history, or geographic comparison. This is the best standalone product of the five and the natural first launch.

### 6.5 Investment and maintenance (permits and demolitions)

- **Promise:** The neighborhood is being maintained and invested in, not abandoned. No official standard exists; this panel is explicitly labeled a comparison, not a compliance measure.
- **Source:** Memphis Data Hub building permits (new, alteration, addition; since 2021); Data Midsouth building and demolition permits for Shelby County; Memphis Property Hub / Assessor for parcel context.
- **Cadence:** Weekly pull; metrics recomputed weekly.
- **Metrics (per ZIP/district, rolling 12 months and 5-year trend):**
  - Permit count per 1,000 parcels.
  - Total declared value per 1,000 parcels — shown with a standing caveat that declared value is self-reported and understated, and with the median declared value as a robustness check.
  - New construction vs. renovation vs. demolition mix.
  - Demolition-to-new-construction ratio.
  - Residential vs. commercial share.
- **Address join:** Permits within 0.5 miles of the address, listed individually with plain-English descriptions.
- **Validation concerns specific to this pipeline:**
  - *Two sources, one reality.* The city Data Hub and Data Midsouth datasets overlap; reconcile them against each other and document which is authoritative for which fields.
  - *Permit subtypes* are free-text-ish; the category mapping is a spec artifact and is tested against a hand-labeled sample.
  - *Lag.* Permits lead construction by months; the trend view is labeled accordingly.
- **Reconciliation target:** monthly permit counts against the Census Building Permits Survey for the City of Memphis.
- **Existing products displaced:** None as a product. Raw tables exist on the Data Hub and Data Midsouth; the Daily Memphian covers major projects editorially.

### 6.6 Optional sixth: emergency department wait times

Fits the same frame ("how long until someone sees you at the nearest ER") and could be added as a sixth panel once its pipeline meets the Section 5 bar. Noted here so the schema and geography layer accommodate it; out of scope for the first release.

## 7. Shared geography layer

One small package or module that every pipeline imports, with its own tests.

- **Boundaries:** ZIP Code Tabulation Areas (Census), Memphis City Council districts (city GIS; confirm current post-redistricting file), Shelby County Commission districts, and Census tracts. Store as GeoJSON in the repo with source and vintage in the filename.
- **Geocoding:** U.S. Census Bureau geocoder (free, no key, batch endpoint) as primary; Nominatim as fallback. Cache every geocoded address with its match quality. Validate the geocoder on a hand-checked sample of 200 Memphis addresses before use; publish the accuracy rate.
- **Address lookup:** Geocode → point-in-polygon for each boundary set → radius queries against each pipeline's point layer, all client-side against precomputed data (Section 9).
- **Reference neighborhoods:** A fixed set of six to eight named areas (e.g., Frayser, Whitehaven, Midtown, East Memphis, Cordova, South Memphis, Downtown, Raleigh) used as comparison anchors in every view. Define them as ZIP groupings and publish the mapping.
- **Denominators:** ACS 5-year population by ZCTA and tract; parcel counts from the Assessor. Refresh annually and version.
- **Boundary effects:** every spatial join is tested for records that fall exactly on boundaries or outside all polygons, and the "unassigned" count is published.

## 8. Output schema

Every pipeline writes the same four files:

1. `metrics_<pipeline>_by_<geography>.csv` — one row per geography × metric × time window: `geo_type`, `geo_id`, `metric`, `metric_version`, `window_start`, `window_end`, `value`, `ci_low`, `ci_high`, `n`, `suppressed` (boolean), `citywide_median`, `computed_at`, `data_current_through`.
2. `points_<pipeline>.geojson` — the underlying point events with the minimum fields needed for radius queries and display, plus geocode match quality.
3. `validation_<pipeline>_<run_date>.json` — the Layer 2 validation report for that run: checks run, passed, failed, record counts, freshness, unlocated share.
4. `methodology_<pipeline>.md` — generated from the specs: metric definitions, versions, exclusions, thresholds and their alternatives, latest reconciliation result, latest audit date.

The front end reads only these files and refuses to render any row where `suppressed` is true or `data_current_through` is older than the pipeline's stated freshness limit.

## 9. Architecture ($0–10/month)

- **Pipelines:** R (tidyverse, sf, httr2, pointblank, testthat) for the batch pipelines; the MATA and MLGW pollers in either R or Python, whichever is easier to keep running on GitHub Actions. Each pipeline is its own folder with a workflow on a cron schedule and a test job that runs on every commit.
- **Storage:** Flat files pushed to free-tier object storage (Cloudflare R2 or S3). Continuous pollers append to daily partitioned files and compact monthly. Every published dataset is versioned; old versions are never deleted.
- **Front end:** Static site. Quarto with Observable JS, or plain HTML + MapLibre GL, reading the flat files directly. Hosted on GitHub Pages or Cloudflare Pages.
- **Address lookup without a server:** Precompute metrics on a hexagonal grid (H3, resolution 8–9) covering the city. The browser geocodes the address via the Census API, finds the hex, and reads precomputed values with their intervals and `n`. No backend, no database, no per-request cost.
- **Email digests (later):** GitHub Actions + a free-tier transactional email service; subscriber list in a private repo.
- **Cost drivers to watch:** GitHub Actions minutes for the pollers (public repos are free), object-storage egress if traffic spikes, geocoding rate limits.

## 10. Phasing

Each phase ships something usable on its own, and nothing ships until it clears Section 5.7.

| Phase | Deliverable | Why this order |
|---|---|---|
| 0 | Geography layer with tests, output schema, spec template, validation harness, shared business-day calendar | Everything else depends on it |
| 1 | **MLGW poller and MATA poller started** (collection only, no UI) | Both need months of baseline; start accumulating immediately |
| 2 | **Food safety** as a standalone map site with per-restaurant history | Highest standalone adoption, simplest validation story, fastest path to a real user base |
| 3 | **311** added; first two-panel address lookup; citywide on-time % reconciled against the city's figure | Establishes the promise-vs-delivery framing and the project's credibility |
| 4 | **Permits** added | Low effort, rounds out the "investment" dimension |
| 5 | **MATA** panel goes live after trip-matching passes the match-rate floor and the stopwatch audit | Highest analytical difficulty; the baseline from Phase 1 supports it |
| 6 | **MLGW** panel goes live after six months and one significant weather event; neighborhood comparison view; email digests | Full five-panel product |
| 7 | ED wait times as optional sixth panel | If its pipeline meets the bar |

Target: Phase 2 live within two months; five panels within nine to twelve months at a few hours a week. The validation work is most of the time, and that's the point.

## 11. Distribution

- **Launch channel for Phase 2:** r/memphis, neighborhood Facebook groups, and a direct pitch to WREG (which already runs the restaurant-score series) and the Daily Memphian.
- **Institutional partner:** Innovate Memphis / Data Midsouth, which launched a regional open-data hub in April 2026 and ran a civic hackathon. Natural host for the pipelines' output and the most credible endorser; also a candidate for the independent reviewer role in 5.6.
- **Amplifiers:** Neighborhood CDCs, the Blight Elimination Steering Team network, transit advocacy groups, council staff.
- **Make it quotable:** Every panel has a "share this comparison" image export that includes the `n`, the interval, and the data-current-through date, so screenshots carry their own caveats.

## 12. Risks

| Risk | Mitigation |
|---|---|
| A published number is wrong and gets quoted | Six-layer validation; reconciliation against agency figures; manual audits committed to the repo; versioned corrections with a public changelog |
| Scraper blocked (state health site, MLGW map) | Check terms of use first; request bulk exports or open-records access in parallel; a blocked source degrades to a stale, clearly labeled panel, never a broken site |
| MATA trip-matching is unreliable | Match-rate floor per route; stopwatch audit at real stops before launch; publish the rule and the match rate; start with one high-frequency route |
| 311 disposition codes are ambiguous | Hand-read a few hundred closed requests before defining anything; publish the mapping; reproduce the city's own on-time % as proof of method |
| Arbitrary thresholds drive the conclusion | Every threshold published under at least two alternatives; if the conclusion flips, say so |
| Small-area noise read as signal | Minimum `n`, suppression, intervals on every value, no comparisons between non-overlapping intervals without a "not clearly different" label |
| Metrics get read as a neighborhood ranking anyway | No composite score, no sorted leaderboard; comparison view requires the user to pick the two areas |
| Volume vs. performance confusion | Separate visually and in the methodology; never present request counts as a quality measure |
| Agency pushback | Methodology transparency, courtesy previews, correction channel, and the ability to say "we reproduced your own number first" |
| Project stalls partway | Each phase is a complete product; pollers keep accumulating baseline regardless |
| Scope creep toward "everything data hub" | Test for any new panel: does it measure a promise the city or a utility makes to a resident at an address, and can it clear Section 5.7? If not, it doesn't belong |

## 13. Open questions (resolve before Phase 1)

- Does MATA publish a current GTFS static feed and a GTFS-Realtime feed, or is the TransLoc endpoint the only real-time source? What does it expose per vehicle (trip ID, route, heading, timestamp)?
- Does the MLGW outage map expose a JSON/GeoJSON layer, and at what geography? Does it show customer counts and estimated restoration times per polygon, and are estimates revised in place?
- What are the actual 311 status and disposition codes, and how did they change at the October 2023 migration?
- Does the TN Department of Health offer a bulk download, API, or open-records path for inspection records?
- Does MATA report on-time performance anywhere public (board packets, NTD)? Does MLGW publish SAIDI/SAIFI?
- Which council-district boundary file is current after the most recent redistricting?
- Who can serve as the independent reviewer in 5.6 — Data Midsouth, a U of M faculty member, a former agency analyst?

## 14. Success criteria (12 months)

- All five panels live, each with a frozen spec, passing validation, current reconciliation, and a committed audit.
- Citywide 311 on-time % reproduced within 2 percentage points of the city's figure, and the discrepancy (if any) explained publicly.
- At least one challenge received through the correction channel and resolved with a documented response — evidence the methodology is being read.
- Address lookup used by a few hundred unique people per month in normal conditions, with spikes during outage or transit news.
- At least one local news story or council discussion that cites the data without the number being disputed on method.
- Pipelines running unattended with under two hours per month of maintenance, and every scheduled validation run green.
