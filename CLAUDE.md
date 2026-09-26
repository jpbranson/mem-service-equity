# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Memphis Service Equity measures whether five systems keep their promises by where you live: MATA transit, MLGW power restoration, 311 city services, food-safety inspections and permits/investment. The output is a static site, and there is no server. Batch pipelines and the shared core are written in R. The long-running collectors are in Python (DECISIONS.md D1).

Current priority (D19): understanding how the experience of services differs between areas comes before the "did the city keep its promise" framing. The guardrails still apply: intervals, minimum n, suppression, no composite scores or rankings.

Read these first:
- `memphis-service-equity-design-plan-v0.2.md` is the design plan. Section references in code comments, README and DECISIONS ("plan 5.3", "section 8", "6.1") point into it.
- `DECISIONS.md` has two lists. "Needs a human" (H*) holds items that block work, such as credentials, records requests, audits and spec sign-off. "Decisions made" (D*) records implementation choices. Cite and extend these IDs rather than re-deciding.
- `docs/research/` holds verified notes on each data source, including endpoints, terms and pitfalls. `docs/records-requests/` holds draft records requests; DECISIONS records whether each was sent.

Where the plan conflicts with verified research, the research and DECISIONS win. For example, the plan says Socrata for 311, "3–7 days / 82%" promises and MLGW polygons. DECISIONS D12, D14, H14 and H19 record the corrections.

## Commands

Run everything from the repo root. R 4.3+ is needed, plus `h3jsr`, `httr2`, `data.table` and `testthat` beyond the DESCRIPTION imports.

```sh
# Shared package tests
Rscript -e 'devtools::test("packages/memequity")'
Rscript -e 'devtools::test("packages/memequity", filter = "stats")'   # one file: test-stats.R

# 311 pipeline tests. These use the INSTALLED memequity, so reinstall after changing the package.
R CMD INSTALL packages/memequity
Rscript -e 'testthat::test_dir("pipelines/311/tests/testthat")'
Rscript -e 'testthat::test_dir("pipelines/311/tests/testthat", filter = "311")'

# 311 pipeline end to end (fetches about 400k rows, about 3 min). --raw-cache avoids refetching during dev.
# The publish gate treats tests as passed only when TESTS_PASSED=true is set (the deploy workflow does this after testing).
Rscript pipelines/311/run.R --out data/published/311 --raw-cache data/cache/311_raw.rds [--as-of YYYY-MM-DD]

# Permits pipeline (about 3 min; the DPD layer is refreshed monthly) and its tests
Rscript pipelines/permits/run.R --out data/published/permits --raw-cache data/cache/permits_raw.rds [--as-of YYYY-MM-DD]
Rscript -e 'testthat::test_dir("pipelines/permits/tests/testthat")'
Rscript geography/fetch_parcels.R                                   # yearly: parcel denominators
Rscript pipelines/permits/reconciliation/fetch_bps.R 2021 2025       # yearly: Census permit figures

# Food safety: tests on a synthetic export; the run needs the H11 export in pipelines/food-safety/inbox/
Rscript -e 'testthat::test_dir("pipelines/food-safety/tests/testthat")'
Rscript pipelines/food-safety/run.R [--through YYYY-MM-DD]

# Static-site data from published outputs. Gated by default; --preview keeps unpublished metrics (local only, D18)
Rscript site/build_site_data.R data/published site/data [--preview]
CENSUS_API_KEY=... Rscript geography/fetch_demographics.R   # yearly ACS refresh (D20)
python3 -m http.server 8765 --directory site     # serve the site locally

# Pollers (Python 3.12)
python -m pip install -r pollers/requirements.txt
python -m pytest pollers/tests
python -m pytest pollers/tests/test_pollers.py::test_parse_outage_fixture
```

CI (`.github/workflows/test-memequity.yml`) runs the package tests and then the 311 and permits tests with `stop_on_failure = TRUE`. `test-pollers.yml` runs pytest. `deploy-site.yml` runs daily: tests, then the 311 pipeline with `TESTS_PASSED=true` and a dated zip to the monthly `data-311-YYYY-MM` release; then permits the same way (`data-permits-YYYY-MM`), which is allowed to fail without blocking 311; then the gated site build and a GitHub Pages deploy.

## Architecture

**Data flow.** Source → pipeline (fetch → validate → normalize → attach geography → metrics) → flat files in `data/published/<pipeline>/` → `site/build_site_data.R` → sharded JSON in `site/data/` → static front end. The front end reads only pipeline outputs and never computes a statistic. That includes address-level views: each `h3_9` row already covers the cell plus its six neighbours (D16), so the browser only looks one up. The front end (`site/assets/app.js`) is plain JS with no build step; tables, freshness and area comparisons are keyed by pipeline (`renderMetricTable(key, …)`, `setupComparison`). It loads h3-js from jsdelivr (and `methodology.html` loads marked and DOMPurify, pinned versions) and writes data into the page as text only, never as HTML. Metric titles, units and minimum n come from the specs via the manifest, and demographic labels come from `geography/demographics/measures.csv` via `demographics.json`, so do not restate definitions in the JS. `data/published/`, `data/poller/`, `data/cache/` and `site/data/` are gitignored. Published runs go to monthly GitHub releases (D17), and poller archives go to weekly releases through `pollers/archive_release.sh` (D7).

**`packages/memequity/`** is the shared core, and every pipeline must go through it:
- `output.R` defines the output contract. `METRICS_COLUMNS` is the exact column order for `metrics_<pipeline>_by_<geo>.csv`, `GEO_TYPES` lists the allowed geographies, and `write_metrics()` refuses invalid tables. Suppressed rows carry no value or interval. Published rows must have both.
- `validation.R` is an in-house harness (not pointblank; D3). It builds a report with `validation_report()`, `check_*()` and `add_check()`. The same JSON format is expected from the Python pollers. `stop_if_failed()` halts the run.
- `specs.R` parses `specs/<pipeline>/<metric>.md`. The YAML front matter is machine-read, `spec_problems()` enforces the rules for freezing a spec, and `render_methodology()` generates the methodology page from the specs. Never hand-edit a generated methodology page.
- `publish.R` holds `publish_gate()`, which evaluates the publication conditions per metric. `audit_problems()` makes condition 6 require a *completed* audit sheet, not just the file (D23). As of this writing no metric passes, because every spec is `draft` (H10) and no audit is committed (H3).
- `reconcile.R` handles condition 5 (D22). Each spec's `reconciliation.measures` names official figures in `pipelines/<pipeline>/reconciliation/official_figures.csv`. The pipeline recomputes them every run (`pipelines/311/R/reconcile.R` for 311), and `spec_reconciliation()` gives the gate the result for one spec. Only copy figures from official sources, and leave `gap_note` empty unless a gap was investigated.
- `geography.R` / `spatial_join.R`: boundaries are listed in `geography/boundaries/registry.csv`, with source and vintage in each file name. `load_boundaries(geo_type)` returns an sf object with a standard `geo_id`. Distance work uses EPSG:32136 (`MSE_CRS_METERS`) and storage uses 4326. A point within 1 m of multiple polygons goes to the lowest `geo_id` and is flagged `on_boundary` (D8). `geography_dir()` walks up from the working directory, or you can set `MSE_GEOGRAPHY_DIR`.
- `demographics.R`: ACS 5-year estimates apportioned to every geography through 2020 blocks, for the part of each area inside the city (D20). `geography/fetch_demographics.R` refreshes them (needs `CENSUS_API_KEY`); `load_demographics(geo_type)` derives the measures in `geography/demographics/measures.csv` with margins of error, and `area_population(geo_type)` gives rate denominators. If `reference_neighborhoods.csv` changes, rerun the fetch script (a package test checks this).
- `calendar.R` counts business days on the **City of Memphis** holiday calendar (`inst/extdata/city_holidays.csv`), not the federal one (D10). Age counts days `d` with `open < d <= close` in America/Chicago time, so opening and closing on the same day gives 0 (D5).
- `stats.R` handles min-n suppression, Wilson and bootstrap intervals (median and total), and the Kaplan–Meier censored median (`km_median_counts`). Open requests are right-censored, never dropped (D9).
- `parcels.R`: `area_parcels(geo_type)` gives in-city parcel counts per area, the permits denominator (`geography/parcels/`, Assessor 2022 snapshot).

**Pipelines (`pipelines/<name>/`)** are not packages. `run.R` and the tests `source()` every file in `R/` and call memequity functions. Request-type mapping, target days and headline flags live in `config/` (`request_types.csv`, `status_map.csv`, `contract.yml` for the source schema). Validation fails if a new source value is not mapped there. The 311 near-duplicate rule is in D6. Audit worksheets are generated into the output `audit/`. Completed ones are committed to `pipelines/<name>/audits/`, where `run.R` looks for them for the publish gate. `311` and `permits` exist. Permits uses only the City's DPD layer (D24: Data Midsouth's robots.txt forbids automated access), so demolitions and `demolition_to_new_ratio` are blocked (H21; the spec's `blocked` field makes the gate say so). Its data run through the end of the month before the layer's last edit (`permits_through()`). `food-safety` is built and tested on a synthetic export; it reads the H11 export from its gitignored `inbox/`, and every source column name lives in `config/column_map.yml` (never hard-code them in R). MATA and MLGW have not been started.

**Independent checks and review packets.** `pipelines/311/tests/independent/` is a stdlib-only Python reimplementation that recomputes the golden file (H20) and pre-traces the audit sample against the live source (H3). If a 311 spec version changes, update it independently of the R code. `docs/reviews/` holds the packets for each human step; never mark an H-item done on the strength of a packet alone.

**Specs and versions.** Each metric's spec version appears in two places: the spec's YAML `version` and `SPEC_VERSIONS` in the pipeline's `R/metrics.R`. Keep the two in sync. A definition change bumps MAJOR and starts a new series. Arbitrary thresholds are published as `variant` rows next to `primary` (D4), for example the reopen-rate window and radius variants.

**Golden files.** `pipelines/311/tests/golden/` holds a frozen sample of real data and the metrics computed from it. Rebuild it with `Rscript pipelines/311/tests/build_golden.R <raw.rds>` **only** when a spec version changes, and say why in the commit message. A golden-test failure is otherwise a regression.

**Pollers (`pollers/`).** `mata_poller.py` (GTFS-Realtime protobuf) and `mlgw_poller.py` (outage map) run on GitHub Actions. Each run lasts 170 minutes and runs start every 2 hours (MATA at :07, MLGW at :30, off the busy top of the hour), so they overlap by 50 minutes to absorb GitHub's scheduling delays. Dedup happens downstream (D15). Every poll attempt is logged, including failures, because uptime is published and gaps must not look like ghost buses or restored outages. Output is gzip JSON-lines, written as one gzip member per flush so a crash cannot corrupt earlier data. `poll_with_uploads.sh` uploads the output to the weekly release every 30 minutes during a run, so a lost runner costs at most about 30 minutes plus the unflushed buffer. `archive_release.sh` uploads a copy of each file only if it passes `gzip -t`, so it is safe to run mid-write; set `ARCHIVE_DRY_RUN=1` to test it without uploading. The only third-party dependency is `gtfs-realtime-bindings`. Keep it that way.

## Project rules

- Do not scrape any source whose terms or robots.txt forbid it (D11). The state food-inspection portal is off-limits.
- Only official city sources (memphistn.gov) count as a "promise". memphisgov.com is a commercial look-alike, and its "3–7 days" and "82% on-time" figures must not be used (D12, H14). Metrics without an official target are labelled `comparison` against the citywide median.
- The data vintage of any boundary or calendar must be traceable: source and vintage go in the file name and in `registry.csv`.
