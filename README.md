# Does Memphis work the same for everyone?

The Memphis Service Equity project measures whether five basic systems keep
their promises, and whether the answer changes with where you live:

1. **Transit.** Does the MATA bus arrive when the schedule says it will?
2. **Power.** Does MLGW restore power by the estimated time?
3. **City services.** Is a 311 request resolved within the city's published
   target?
4. **Food safety.** Do nearby restaurants pass inspection, and are they
   inspected as often as the state requires?
5. **Investment.** Is the neighborhood being maintained and invested in?

The full design is in
[`memphis-service-equity-design-plan-v0.2.md`](memphis-service-equity-design-plan-v0.2.md).
[`DECISIONS.md`](DECISIONS.md) lists what needs a human (credentials,
records requests, audits, spec sign-off) and the implementation choices made
so far. Source research is in [`docs/research/`](docs/research/).

## Status (2026-10-06)

| Phase | Plan deliverable | State |
|---|---|---|
| 0 | Geography layer, output schema, spec template, validation harness, business-day calendar | **Done.** `packages/memequity`, `geography/`, `specs/` |
| 1 | MATA and MLGW pollers started | **Running, with gaps.** GitHub Actions every 2 hours, raw data archived to weekly releases (`archive-mata-*`, `archive-mlgw-*`). Because GitHub skips about half the scheduled runs, the polls cover only about 50% of the time (DECISIONS.md H22) |
| 2 | Food safety site | **Built, not yet published.** Runs on TDH's records-request export, 2021-01-04 to 2026-10-02 (DECISIONS.md H11, D32; received 2026-10-06), with its own comparison section on the site. Restaurants and bars only. Not in the daily deploy: the export is a one-off file that is not committed. It has no violations or closure dates |
| 3 | 311 pipeline and address lookup | **Three metrics pass the publish gate (2026-10-06, D33); not yet deployed.** Pipeline, address lookup, area comparison (with "who lives here" demographics and requests per 1,000 residents) and methodology page all work. `deploy-site` runs daily and deploys to GitHub Pages. The other two metrics show which publication conditions they still miss |
| 4 | Permits | **Two metrics pass the publish gate (2026-10-06, D33); not yet deployed.** Permits and declared value per 1,000 parcels by ZIP and council district, from the City's DPD layer, with its own comparison section on the site. Demolitions and the demolition-to-new ratio come from the owner's Data Midsouth snapshot (D30), in local runs only until its live service exists. Reconciled against the Census Building Permits Survey |
| 5 | MATA panel | **Trip matching built** (`pipelines/mata/`): schedule in force per day, matching by trip_id, ghost versus unobserved by block, and arrivals interpolated along the shape. It has run on the first archive. No window has enough data yet, and the pollers cover only about half of service hours on GitHub Actions (DECISIONS.md H22). Stopwatch audit (H5) not done |
| 6 | MLGW panel | Collecting; needs six months of history, which accrues at half speed until H22 is fixed. The specs are restated for point outages (v0.2, H19 awaiting confirmation). **Pipeline built** (`pipelines/mlgw/`, D31): outage events, customer-hours and restoration against the map's estimates, from the poller archive. It has run on the first nine days |

**Current priority (DECISIONS D19):** how the experience of city services
differs from one area to another, with demographic context for each area
(ACS 2020–2024, D20). Work that depends on official targets is deferred.

**Five metrics pass the publish gate** as of 2026-10-06. For 311: median
business days to close, the re-report rate and requests per 1,000
residents. For permits: permits and declared value per 1,000 parcels.
- Their specs were frozen and their audits done by Claude at the owner's
  direction (DECISIONS.md D33). No person has reviewed a spec or traced a
  record, and the audit sheets and the methodology page say so. The
  independent reviewer (H7) and the agency previews (H8) are still open.
- Each audit took the 100 records its run drew, fetched them again, and
  checked them with independent code, the City's own fields and Census
  geocodes. The published rows those records count in were recomputed from
  a fresh fetch and all match. What the audits found is in
  `pipelines/311/audits/` and `pipelines/permits/audits/`.
- The numbers reach the public site when these commits are pushed and the
  daily deploy next runs.

Every other metric's publish-status file says which of the six conditions
is missing.
- For 311, `pct_within_target` has no official on-time figure (H14), and
  the closed-without-action rate waits on the disposition audit (H4). The
  comparison metrics reconcile against the one official count that
  reproduces: FY25 street-sweeping requests (D22).
- For permits, the Census figures for 2021 and 2022 reproduce within 2%,
  and the larger gaps for 2023 to 2025 are investigated and documented in
  `pipelines/permits/reconciliation/official_figures.csv`. The
  demolition-to-new ratio is a draft and is not computed in the deploy
  (D30).
- For food safety, the specs are drafts, no audit exists, and no official
  inspection count has been found to reconcile against (H23). TDH will not
  send recurring exports, so the data end on 2026-10-02 (H11).
- MATA and MLGW wait on data (H22) and on their spec reviews.

Review packets that prepare each human step are in `docs/reviews/`.

## Repository layout

| Path | What it holds |
|---|---|
| `packages/memequity/` | Shared R package: geography layer, grid-hash spatial joins, City of Memphis business-day calendar, stats (suppression, Wilson / bootstrap / Kaplan–Meier intervals), validation harness, output-schema writers, spec parser, publish gate and audit check, reconciliation against official figures, ArcGIS queries with retries, demographics and parcel denominators |
| `geography/` | Boundary files (source and vintage in each file name) plus `registry.csv`, reference neighborhoods, and `fetch_boundaries.R`. `demographics/` holds ACS 5-year estimates apportioned to every geography (DECISIONS D20), written by `fetch_demographics.R`. `parcels/` holds the Assessor's in-city parcel counts per area (the permits denominator), written by `fetch_parcels.R`. `check_geocoder.R` measures the address lookup's geocoder (H6) |
| `specs/<pipeline>/` | Metric specifications. The YAML front matter is machine-read; methodology pages are generated from these files |
| `pipelines/311/` | The 311 pipeline: `run.R`, `R/` (fetch, normalize, metrics, hex, audit, reconcile), `config/`, `reconciliation/` (official City figures, D22), `audits/` (the completed audit, D33), `tests/` (fixtures, properties, golden files, and `independent/`: a second implementation that checks the golden file and pre-traces the audit sample) |
| `pipelines/mata/` | MATA trip matching and metrics from the poller archive: `run.R --archive DIR` (weekly release assets), `R/` (archive, gtfs, match, arrivals, metrics), `tests/` on a synthetic route |
| `pipelines/mlgw/` | MLGW outage events and metrics from the poller archive: `run.R --archive DIR` (weekly release assets), `R/` (archive, events, metrics), `config/out_causes.csv` (which causes are planned), `tests/` on a synthetic archive |
| `pipelines/food-safety/` | The food-safety pipeline: `run.R` reads TDH's records-request export from the gitignored `inbox/` (H11, D32); `config/column_map.yml` maps the columns, and `programs.csv`, `establishment_types.csv` and `inspection_types.csv` say what counts; `tests/` (synthetic fixtures and a golden file from a frozen sample of the real data) |
| `pipelines/permits/` | The permits pipeline, same layout: `run.R`, `R/` (including `demolitions.R` for the Data Midsouth snapshot, D30), `config/` (sector and category maps, subgroup labels, the snapshot's column map), `reconciliation/` (Census Building Permits Survey figures, `fetch_bps.R`), `tests/` |
| `pollers/` | Python collectors for MATA GTFS-Realtime and MLGW outages, with tests and the release-archive script |
| `site/` | Static front end (plain HTML/JS, no build step): `index.html`, `methodology.html`, `assets/`. `build_site_data.R` turns published outputs into sharded JSON under `site/data/` (generated, not committed) and leaves out any metric that fails the publish gate |
| `docs/research/` | Verified notes on every data source |
| `docs/records-requests/` | Drafts of public records requests (see DECISIONS.md for what has been sent) |
| `docs/reviews/` | Packets that prepare each human step (H3 audit, H6 geocoder, H9 reference neighborhoods, H10 spec review, H20 golden file). They say what was checked automatically and what a person still has to do |
| `docs/outreach/` | Drafts for the independent reviewer (H7) and the agency courtesy preview (H8), and the public log of preview responses |
| `.github/workflows/` | Package, pipeline and poller tests, the two poller schedules, and the daily `deploy-site` (test, run 311 and permits, archive, deploy) |

## Running things

All commands run from the repository root. They need R 4.3 or newer, with
the packages listed in `packages/memequity/DESCRIPTION` plus `h3jsr`,
`httr2`, `data.table` and `testthat`.

```sh
# Shared package tests
Rscript -e 'devtools::test("packages/memequity")'

# 311 pipeline tests (fixtures, properties, golden files)
R CMD INSTALL packages/memequity
Rscript -e 'testthat::test_dir("pipelines/311/tests/testthat")'

# 311 pipeline (fetches ~400k requests; about 3 minutes). Set TESTS_PASSED=true
# only after the tests above pass; otherwise the publish status reports
# condition 3 as unmet. The deploy workflow sets it after running the tests.
Rscript pipelines/311/run.R --out data/published/311

# ACS demographics (about once a year, after each December ACS release;
# needs CENSUS_API_KEY). Writes committed files under geography/demographics/
Rscript geography/fetch_demographics.R

# Site data from the published outputs (only metrics that pass the publish gate)
Rscript site/build_site_data.R data/published site/data
# ...or with every metric, for local review only; never deploy this
Rscript site/build_site_data.R data/published site/data --preview

# Serve the site locally at http://localhost:8765
python3 -m http.server 8765 --directory site

# Permits pipeline (about 3 minutes) and its tests. Parcel counts and the
# Census figures are refreshed about once a year:
Rscript pipelines/permits/run.R --out data/published/permits
# ... with demolitions from the owner's Data Midsouth snapshot (D30)
Rscript pipelines/permits/run.R --out data/published/permits --demolitions ../mem-demo-permits/shelby_permits.csv
Rscript -e 'testthat::test_dir("pipelines/permits/tests/testthat")'
Rscript geography/fetch_parcels.R
Rscript pipelines/permits/reconciliation/fetch_bps.R 2021 2025

# Food safety: tests (synthetic fixtures and a golden file); the run reads
# TDH's records-request export in pipelines/food-safety/inbox/ (D32)
Rscript -e 'testthat::test_dir("pipelines/food-safety/tests/testthat")'
Rscript pipelines/food-safety/run.R

# MATA: download a week of the poller archive, then match trips. No window
# is computed until data cover 90% of its days.
gh release download archive-mata-2026-W39 --dir data/cache/mata/2026-W39
Rscript pipelines/mata/run.R --archive data/cache/mata/2026-W39
Rscript -e 'testthat::test_dir("pipelines/mata/tests/testthat")'

# Poller tests
python -m pip install -r pollers/requirements.txt pytest
python -m pytest pollers/tests
```

The 311 run writes these files to `data/published/311/` (not committed):
- the metrics files for each geography
- `points_311.geojson`
- the validation report
- the generated methodology
- the publish status
- `audit/` worksheets for the manual audits

## Publication rule

A metric appears on the site only when all six conditions hold:
1. Its spec is frozen.
2. Source validation passed on the current run.
3. Its tests and golden files pass.
4. Its `n` clears the minimum and it has an interval.
5. Its reconciliation against an official figure is less than a quarter old.
   Each spec names the figures it is checked against. The pipeline
   recomputes them on every run from
   `pipelines/<pipeline>/reconciliation/official_figures.csv`. A gap over
   2% must be explained (DECISIONS D22).
6. Its manual audit is committed and complete: at least 100 records, every
   check answered, and every discrepancy explained (D23).

Otherwise the panel shows which condition is missing. See
`packages/memequity/R/publish.R`.
