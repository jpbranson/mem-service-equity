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

## Status (2026-09-25)

| Phase | Plan deliverable | State |
|---|---|---|
| 0 | Geography layer, output schema, spec template, validation harness, business-day calendar | **Done.** `packages/memequity`, `geography/`, `specs/` |
| 1 | MATA and MLGW pollers started | **Running, with gaps.** GitHub Actions every 2 hours, raw data archived to weekly releases (`archive-mata-*`, `archive-mlgw-*`). Because GitHub skips about half the scheduled runs, the polls cover only about 50% of the time (DECISIONS.md H22) |
| 2 | Food safety site | **Blocked.** The state inspection portal forbids automated access, so the data needs a records request (DECISIONS.md H11). The request in `docs/records-requests/` was sent on 2026-09-23. The pipeline (`pipelines/food-safety/`) is built and tested on a synthetic export and runs once the export arrives |
| 3 | 311 pipeline and address lookup | **Built, not yet published.** Pipeline, address lookup, area comparison (with "who lives here" demographics and requests per 1,000 residents) and methodology page all work. `deploy-site` runs daily and deploys to GitHub Pages. Every metric shows which publication conditions it still misses |
| 4 | Permits | **Built, not yet published.** Permits and declared value per 1,000 parcels by ZIP and council district, from the City's DPD layer, with its own comparison section on the site. Demolitions are blocked: Data Midsouth forbids automated access (D24, H21). Reconciled against the Census Building Permits Survey |
| 5 | MATA panel | **Trip matching built** (`pipelines/mata/`): schedule in force per day, matching by trip_id, ghost versus unobserved by block, and arrivals interpolated along the shape. It has run on the first archive. No window has enough data yet, and the pollers cover only about half of service hours on GitHub Actions (DECISIONS.md H22). Stopwatch audit (H5) not done |
| 6 | MLGW panel | Collecting; needs six months of history, which accrues at half speed until H22 is fixed. The specs are restated for point outages (v0.2, H19 awaiting confirmation); no pipeline yet |

**Current priority (DECISIONS D19):** how the experience of city services
differs from one area to another, with demographic context for each area
(ACS 2020–2024, D20). Work that depends on official targets is deferred.

**No metric is publishable yet.** Every metric's publish-status file says
which of the six publication conditions is missing.
- For every metric, the spec has not been frozen by a reviewer (H10), and
  no manual audit has been committed (H3).
- For 311, the comparison metrics reconcile against the one official count
  that reproduces: FY25 street-sweeping requests (D22). `pct_within_target`
  has no official on-time figure (H14).
- For permits, the 2023 Census figure is 2.1% off and not yet explained.

Review packets that prepare each human step are in `docs/reviews/`.

## Repository layout

| Path | What it holds |
|---|---|
| `packages/memequity/` | Shared R package: geography layer, grid-hash spatial joins, City of Memphis business-day calendar, stats (suppression, Wilson / bootstrap / Kaplan–Meier intervals), validation harness, output-schema writers, spec parser, publish gate |
| `geography/` | Boundary files (source and vintage in each file name) plus `registry.csv`, reference neighborhoods, and `fetch_boundaries.R`. `demographics/` holds ACS 5-year estimates apportioned to every geography (DECISIONS D20), written by `fetch_demographics.R`. `parcels/` holds the Assessor's in-city parcel counts per area (the permits denominator), written by `fetch_parcels.R`. `check_geocoder.R` measures the address lookup's geocoder (H6) |
| `specs/<pipeline>/` | Metric specifications. The YAML front matter is machine-read; methodology pages are generated from these files |
| `pipelines/311/` | The 311 pipeline: `run.R`, `R/` (fetch, normalize, metrics, hex, audit, reconcile), `config/`, `reconciliation/` (official City figures, D22), `tests/` (fixtures, properties, golden files, and `independent/`: a second implementation that checks the golden file and pre-traces the audit sample) |
| `pipelines/mata/` | MATA trip matching and metrics from the poller archive: `run.R --archive DIR` (weekly release assets), `R/` (archive, gtfs, match, arrivals, metrics), `tests/` on a synthetic route |
| `pipelines/food-safety/` | The food-safety pipeline for the records-request export (H11): `config/column_map.yml` maps the export's columns, `inbox/` (gitignored) receives the files, `tests/` run on a synthetic export |
| `pipelines/permits/` | The permits pipeline, same layout: `run.R`, `R/`, `config/` (sector and category maps), `reconciliation/` (Census Building Permits Survey figures, `fetch_bps.R`), `tests/` |
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
Rscript -e 'testthat::test_dir("pipelines/permits/tests/testthat")'
Rscript geography/fetch_parcels.R
Rscript pipelines/permits/reconciliation/fetch_bps.R 2021 2025

# Food safety: tests run on a synthetic export; the run needs the H11 export
# in pipelines/food-safety/inbox/
Rscript -e 'testthat::test_dir("pipelines/food-safety/tests/testthat")'
Rscript pipelines/food-safety/run.R

# MATA: download a week of the poller archive, then match trips. No window
# is computed until data cover 90% of its days.
gh release download archive-mata-2026-W39 --dir data/cache/mata/2026-W39
Rscript pipelines/mata/run.R --archive data/cache/mata/2026-W39
Rscript -e 'testthat::test_dir("pipelines/mata/tests/testthat")'

# Poller tests
python -m pip install -r pollers/requirements.txt
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
