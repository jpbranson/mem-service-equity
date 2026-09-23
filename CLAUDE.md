# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Memphis Service Equity measures whether five systems keep their promises by where you live: MATA transit, MLGW power restoration, 311 city services, food-safety inspections and permits/investment. The output is a static site, and there is no server. Batch pipelines and the shared core are written in R. The long-running collectors are in Python (DECISIONS.md D1).

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

# Static-site data from published outputs. Gated by default; --preview keeps unpublished metrics (local only, D18)
Rscript site/build_site_data.R data/published site/data [--preview]
python3 -m http.server 8765 --directory site     # serve the site locally

# Pollers (Python 3.12)
python -m pip install -r pollers/requirements.txt
python -m pytest pollers/tests
python -m pytest pollers/tests/test_pollers.py::test_parse_outage_fixture
```

CI (`.github/workflows/test-memequity.yml`) runs the package tests and then the 311 tests with `stop_on_failure = TRUE`. `test-pollers.yml` runs pytest. `deploy-site.yml` runs daily: tests, then the 311 pipeline with `TESTS_PASSED=true`, a dated zip to the monthly `data-311-YYYY-MM` release, the gated site build and a GitHub Pages deploy.

## Architecture

**Data flow.** Source → pipeline (fetch → validate → normalize → attach geography → metrics) → flat files in `data/published/<pipeline>/` → `site/build_site_data.R` → sharded JSON in `site/data/` → static front end. The front end reads only pipeline outputs and never computes a statistic. That includes address-level views: each `h3_9` row already covers the cell plus its six neighbours (D16), so the browser only looks one up. The front end (`site/assets/app.js`) is plain JS with no build step. It loads h3-js from jsdelivr (and `methodology.html` loads marked and DOMPurify, pinned versions) and writes data into the page as text only, never as HTML. Metric titles, units and minimum n come from the specs via the manifest, so do not restate definitions in the JS. `data/published/`, `data/poller/`, `data/cache/` and `site/data/` are gitignored. Published runs go to monthly GitHub releases (D17), and poller archives go to weekly releases through `pollers/archive_release.sh` (D7).

**`packages/memequity/`** is the shared core, and every pipeline must go through it:
- `output.R` defines the output contract. `METRICS_COLUMNS` is the exact column order for `metrics_<pipeline>_by_<geo>.csv`, `GEO_TYPES` lists the allowed geographies, and `write_metrics()` refuses invalid tables. Suppressed rows carry no value or interval. Published rows must have both.
- `validation.R` is an in-house harness (not pointblank; D3). It builds a report with `validation_report()`, `check_*()` and `add_check()`. The same JSON format is expected from the Python pollers. `stop_if_failed()` halts the run.
- `specs.R` parses `specs/<pipeline>/<metric>.md`. The YAML front matter is machine-read, `spec_problems()` enforces the rules for freezing a spec, and `render_methodology()` generates the methodology page from the specs. Never hand-edit a generated methodology page.
- `publish.R` holds `publish_gate()`, which evaluates the publication conditions per metric. As of this writing no metric passes, because every spec is `draft` (H10) and no audit is committed (H3).
- `geography.R` / `spatial_join.R`: boundaries are listed in `geography/boundaries/registry.csv`, with source and vintage in each file name. `load_boundaries(geo_type)` returns an sf object with a standard `geo_id`. Distance work uses EPSG:32136 (`MSE_CRS_METERS`) and storage uses 4326. A point within 1 m of multiple polygons goes to the lowest `geo_id` and is flagged `on_boundary` (D8). `geography_dir()` walks up from the working directory, or you can set `MSE_GEOGRAPHY_DIR`.
- `calendar.R` counts business days on the **City of Memphis** holiday calendar (`inst/extdata/city_holidays.csv`), not the federal one (D10). Age counts days `d` with `open < d <= close` in America/Chicago time, so opening and closing on the same day gives 0 (D5).
- `stats.R` handles min-n suppression, Wilson and bootstrap intervals, and the Kaplan–Meier censored median (`km_median_counts`). Open requests are right-censored, never dropped (D9).

**Pipelines (`pipelines/<name>/`)** are not packages. `run.R` and the tests `source()` every file in `R/` and call memequity functions. Request-type mapping, target days and headline flags live in `config/` (`request_types.csv`, `status_map.csv`, `contract.yml` for the source schema). Validation fails if a new source value is not mapped there. The 311 near-duplicate rule is in D6. Audit worksheets are generated into the output `audit/`. Completed ones are committed to `pipelines/311/audits/`, where `run.R` looks for them for the publish gate. Only `311` exists so far. Food safety is blocked on H11, and permits, MATA and MLGW have not been started.

**Specs and versions.** Each metric's spec version appears in two places: the spec's YAML `version` and `SPEC_VERSIONS` in the pipeline's `R/metrics.R`. Keep the two in sync. A definition change bumps MAJOR and starts a new series. Arbitrary thresholds are published as `variant` rows next to `primary` (D4), for example the reopen-rate window and radius variants.

**Golden files.** `pipelines/311/tests/golden/` holds a frozen sample of real data and the metrics computed from it. Rebuild it with `Rscript pipelines/311/tests/build_golden.R <raw.rds>` **only** when a spec version changes, and say why in the commit message. A golden-test failure is otherwise a regression.

**Pollers (`pollers/`).** `mata_poller.py` (GTFS-Realtime protobuf) and `mlgw_poller.py` (outage map) run on GitHub Actions. Each run lasts 170 minutes and runs start every 2 hours (MATA at :07, MLGW at :30, off the busy top of the hour), so they overlap by 50 minutes to absorb GitHub's scheduling delays. Dedup happens downstream (D15). Every poll attempt is logged, including failures, because uptime is published and gaps must not look like ghost buses or restored outages. Output is gzip JSON-lines, written as one gzip member per flush so a crash cannot corrupt earlier data. `poll_with_uploads.sh` uploads the output to the weekly release every 30 minutes during a run, so a lost runner costs at most about 30 minutes plus the unflushed buffer. `archive_release.sh` uploads a copy of each file only if it passes `gzip -t`, so it is safe to run mid-write; set `ARCHIVE_DRY_RUN=1` to test it without uploading. The only third-party dependency is `gtfs-realtime-bindings`. Keep it that way.

## Project rules

- Do not scrape any source whose terms or robots.txt forbid it (D11). The state food-inspection portal is off-limits.
- Only official city sources (memphistn.gov) count as a "promise". memphisgov.com is a commercial look-alike, and its "3–7 days" and "82% on-time" figures must not be used (D12, H14). Metrics without an official target are labelled `comparison` against the citywide median.
- The data vintage of any boundary or calendar must be traceable: source and vintage go in the file name and in `registry.csv`.
