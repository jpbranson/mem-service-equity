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
[`memphis-service-equity-design-plan.md`](memphis-service-equity-design-plan.md).
Open items and the choices made during implementation are in
[`DECISIONS.md`](DECISIONS.md).

## Repository layout

| Path | What it holds |
|---|---|
| `packages/memequity/` | Shared R package: geography layer, business-day calendar, stats (suppression, Wilson and bootstrap intervals, censored medians), validation harness, output-schema writers, spec parser and publish gate |
| `geography/` | Boundary files (source and vintage in each file name), reference neighborhoods, denominators |
| `specs/<pipeline>/` | Metric specifications. The YAML front matter is machine-read; methodology pages are generated from these files |
| `pipelines/<pipeline>/` | One folder per pipeline: fetch → validate → normalize → attach geography → compute → test → write |
| `pollers/` | Continuous collectors for MATA vehicle positions and MLGW outages |
| `site/` | Static front end (MapLibre) that reads only the published flat files |
| `docs/` | Research notes on the data sources |

## Running the tests

```sh
cd packages/memequity
Rscript -e 'devtools::test()'
```

## Publication rule

A metric appears on the site only when (1) its spec is frozen, (2) source
validation passed on the current run, (3) its tests and golden files pass,
(4) its `n` clears the minimum and it has an interval, (5) its
reconciliation against an official figure is less than a quarter old, and
(6) its manual audit is committed. Otherwise the panel shows which of these
is missing. See `packages/memequity/R/publish.R`.
