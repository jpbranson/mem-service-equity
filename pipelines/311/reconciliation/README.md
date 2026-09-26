# 311 reconciliation figures

`official_figures.csv` holds figures the City of Memphis has published about
311, copied by hand from the cited document. On every run the pipeline
recomputes each one from the same raw records (`R/reconcile.R`) and compares
the two (plan 5.5, DECISIONS.md D22). The results go to
`reconciliation_311.csv`, the validation report and the methodology page. A
metric can publish only when every figure whose `measure` its spec names is
reproduced within tolerance, or the gap has been explained (condition 5).

## Adding a figure

- **Official sources only:** memphistn.gov and its subdomains, City Council
  documents, and the City's budget books and financial reports.
  memphisgov.com is not a City site (D12).
- **Periods from 2023-10-16 onward only,** when the current 311 system went
  live. The run stops on an earlier figure rather than compare across the
  migration.
- Copy the value exactly as printed. Put the rounding unit in `precision`:
  `1` for an exact count, `1000` for "about 250,000", and so on.
- `measure` must be one the pipeline knows how to compute (`MEASURES_311` in
  `R/reconcile.R`). If the City's definition differs from every existing
  measure, add a new one; don't bend the figure to fit.
- `subgroup` is empty for all requests, request types separated by `|`, or
  `category:<prefix>` (for example `category:SWM`) for every type in that
  category of `config/request_types.csv`.
- `definition` says what the City counted, in its own words where possible.
- `gap_note` stays empty. Fill it in only after a gap outside tolerance has
  been investigated, saying what was found. An unexplained gap keeps the
  dependent metrics unpublished.

## Tolerance

A gap is within tolerance when it is no more than 2% of the official value,
or half the rounding unit, whichever is larger. This matches the 2% check
used for the ACS city total (D20). The live layer changes after the City
counts, as records are merged, deleted or re-typed, so small gaps are
expected.

## Columns

| Column | Meaning |
|---|---|
| `figure_id` | Unique short id |
| `measure` | What is counted (see `MEASURES_311`) |
| `subgroup` | Which requests (see above) |
| `period_start`, `period_end` | Inclusive dates, Memphis local time |
| `value` | The published figure |
| `precision` | Rounding unit of the published figure |
| `definition` | What the City says it counted |
| `source_title`, `source_url`, `source_page` | Where it was published |
| `published` | Publication date of the source |
| `transcribed` | Date it was copied into this file |
| `gap_note` | Explanation of a gap outside tolerance, after investigation |
