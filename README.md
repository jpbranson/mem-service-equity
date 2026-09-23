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

## Status (2026-09-23)

| Phase | Plan deliverable | State |
|---|---|---|
| 0 | Geography layer, output schema, spec template, validation harness, business-day calendar | **Done.** `packages/memequity`, `geography/`, `specs/` |
| 1 | MATA and MLGW pollers started | **Running.** GitHub Actions every 2 hours; raw data archived to weekly releases (`archive-mata-*`, `archive-mlgw-*`) |
| 2 | Food safety site | **Blocked.** The state inspection portal forbids automated access; waiting on a records request (DECISIONS.md H11) |
| 3 | 311 pipeline and address lookup | **Built, not yet published.** Pipeline, address lookup, area comparison and methodology page all work. `deploy-site` runs daily and deploys to GitHub Pages. Every metric shows which publication conditions it still misses |
| 4 | Permits | Not started (specs drafted; sources researched) |
| 5 | MATA panel | Collecting; trip matching not started |
| 6 | MLGW panel | Collecting; needs six months of history |

**No metric is publishable yet.** Every metric's publish-status file says
which of the six publication conditions is missing. For every metric, the
spec has not been frozen by a reviewer (H10) and no manual audit has been
committed (H3). For 311 there is also no official figure to reconcile
against (H14).

## Repository layout

| Path | What it holds |
|---|---|
| `packages/memequity/` | Shared R package: geography layer, grid-hash spatial joins, City of Memphis business-day calendar, stats (suppression, Wilson / bootstrap / Kaplan–Meier intervals), validation harness, output-schema writers, spec parser, publish gate |
| `geography/` | Boundary files (source and vintage in each file name) plus `registry.csv`, reference neighborhoods, and `fetch_boundaries.R` |
| `specs/<pipeline>/` | Metric specifications. The YAML front matter is machine-read; methodology pages are generated from these files |
| `pipelines/311/` | The 311 pipeline: `run.R`, `R/` (fetch, normalize, metrics, hex, audit), `config/`, `tests/` (fixtures, properties, golden files) |
| `pollers/` | Python collectors for MATA GTFS-Realtime and MLGW outages, with tests and the release-archive script |
| `site/` | Static front end (plain HTML/JS, no build step): `index.html`, `methodology.html`, `assets/`. `build_site_data.R` turns published outputs into sharded JSON under `site/data/` (generated, not committed) and leaves out any metric that fails the publish gate |
| `docs/research/` | Verified notes on every data source |
| `.github/workflows/` | Package and poller tests, the two poller schedules, and the daily `deploy-site` (test, run 311, archive, deploy) |

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

# 311 pipeline (fetches ~400k requests; about 3 minutes)
Rscript pipelines/311/run.R --out data/published/311

# Site data from the published outputs (only metrics that pass the publish gate)
Rscript site/build_site_data.R data/published site/data
# ...or with every metric, for local review only; never deploy this
Rscript site/build_site_data.R data/published site/data --preview

# Serve the site locally at http://localhost:8765
python3 -m http.server 8765 --directory site

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
6. Its manual audit is committed.

Otherwise the panel shows which condition is missing. See
`packages/memequity/R/publish.R`.
