# Where 311 runs slow

A standalone spatial analysis of Memphis 311 service requests. It asks:
**where do requests take longer to close than the same request types take
citywide, and do those places cluster?** The report is
[`output/report.html`](output/report.html), which opens in any browser. It
covers the question, four figures, methods, limitations and a data inventory.

This is an exploratory analysis, not a project metric: nothing here passes the
publication rule (specs are drafts, H10; no manual audit, H3).

## Result in brief (requests opened June–August 2026)

- Type-adjusted closing times cluster strongly: global Moran's I = 0.76 over
  181 census tracts (none of 9,999 permutations as high).
- 30 **fast-cluster** tracts in the north (ZIPs 38127, 38128) had 0.57× the
  expected number of slow requests. 29 **slow-cluster** tracts in the
  southwest (ZIPs 38116, 38109) had 1.31×.
- Most of the contrast is solid-waste collection. Bulk trash had a median of
  1 business day in the fast cluster, 7 citywide and 15 in the slow cluster.
  The two clusters close those requests with different resolution codes
  (88% no code against 92% `SWMCT4`). So part of the gap may be in how
  requests are closed rather than in when trash is collected (H4).
- Checks:
  - **Six nearest tracts as neighbors:** almost the same result.
  - **June–July 2025:** the fast cluster is in the same place, but the slow
    cluster was mostly elsewhere (ZIPs 38114, 38111, 38104).
  - **Without solid-waste types:** Moran's I falls to 0.34, and only 3 slow
    and 2 fast cores remain.

Every number in the report is computed from the saved results. This summary was
copied from the 2026-09-28 run.

## Rerun

From the repository root (R 4.3+, packages as in the root README):

```sh
R CMD INSTALL packages/memequity
Rscript analysis/311-slow-service/run.R                 # full analysis; reuses the prep cache
Rscript analysis/311-slow-service/run.R --rebuild-prep  # also rebuilds the prep cache (~3 min extra)
Rscript analysis/311-slow-service/run.R --report-only   # page and figures from saved results
```

The full run takes about 5 minutes after prep. It is deterministic: the seed
is fixed (20260923), and the same inputs give identical numbers.

### Inputs (offline; none are committed)

| Input | Used for |
|---|---|
| `data/cache/311/raw_2026-09-25.rds` | 311 requests (the City's layer, fetched 2026-09-25) |
| `data/cache/permits/raw_2026-09-25.rds` | DPD building permits (context) |
| `../mem-demo-permits/shelby_permits.csv` | Demolitions, the owner's Data Midsouth snapshot (D30; context; optional) |
| `../tn-health-inspections/data/` + `data/cache/food-safety/geocode.csv` | Food inspections (D29; data inventory only; optional; geocodes read from the cache, never fetched) |
| `geography/` | 2020 tracts, city limits, ZCTAs, ACS 2020–2024 components, reference neighborhoods |

The prep step (`R/prep.R`) runs each pipeline's own normalize and geography
code, including exclusions, near-duplicate removal (D6) and the boundary rule
(D8). It adds only a census-tract assignment, and caches the result in
`data/cache/analysis/311-slow-service/`.

### Outputs (`output/`)

- `report.html`: the report, self-contained apart from two Google Fonts
  (it falls back to system fonts offline).
- `figures/fig1_map.svg` … `fig4_robustness.svg`: each figure with its
  title and source.
- `results/`, one CSV per table:

  | File | What it holds |
  |---|---|
  | `tract_results.csv` | Each tract's numbers under every specification |
  | `specifications.csv` | Summary of each specification |
  | `type_thresholds.csv` | Thresholds per request type |
  | `type_by_group.csv` | Request-type results for each cluster group |
  | `group_ratios.csv`, `group_context.csv` | Group summaries and neighborhood context |
  | `bulk_trash_closure_codes.csv` | Resolution codes on closed bulk-trash requests |
  | `request_flow.csv` | Where requests were dropped |
  | `data_inventory.csv` | The data inventory |

  `results.rds` (gitignored) holds everything, for `--report-only`.

## Method, in short

All parameters are in `PARAMS` at the top of `run.R`, fixed before any
result was seen. The code is in `R/`:

1. **Measure (`R/measure.R`).**
   - Each request type's threshold is its citywide Kaplan–Meier median of
     business days to close; open requests are censored (D9).
   - A request is *slow* if it was not closed within that threshold. It is
     eligible once its threshold day has passed.
   - A tract's expected slow count is the sum of the citywide slow share of
     each of its requests' types. The ratio is observed / expected, with a
     Wilson interval.
   - Tracts with fewer than 30 eligible requests are not reported.
   - Types with fewer than 20 requests, or with no median yet, are left out.
2. **Spatial statistics (`R/spatial.R`).** These are written out here, with
   no spdep dependency:
   - empirical-Bayes standardization of the ratios (Assunção–Reis, using a
     binary-outcome variance);
   - queen contiguity with a 10 m tolerance, row-standardized;
   - global Moran's I with 9,999 permutations and analytic moments;
   - local Moran's I with 99,999 conditional permutations, two-sided, with
     a Benjamini–Hochberg FDR of 5%.
3. **Checks (`R/analysis.R`, `run.R`).** Two sensitivity checks were fixed in
   advance: six nearest neighbors, and June–July 2025. One interpretation check
   was added after the per-service breakdown: excluding solid-waste types.
4. **Context.** ACS shares with margins of error, pooled over each group.
   Permits and demolitions per 1,000 housing units, with Poisson intervals.
5. **Report (`R/figures.R`, `R/svg.R`, `R/report.R`).** Hand-built SVG in
   light and dark themes, with hover tooltips and a full tract table.
