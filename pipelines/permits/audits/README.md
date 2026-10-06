# Permits audits

Completed audit sheets for publication condition 6 (plan 5.6, DECISIONS.md
H3, D23). The publish gate reads the newest `audit_*.csv` here.

## audit_sample_2026-10-06.csv

The 100 permits the 2026-10-06 run drew (seed 20261006), audited the same
day by Claude (claude-fable-5-1) at the owner's direction (D33). **No person
has traced these records.** Every row names the auditor.

The `ev_*` columns come from `tests/independent/trace_audit.py`, which
fetches each permit again and, with code that shares nothing with the
pipeline, recomputes the issue date, reads sector and kind of work from the
permit number, geocodes the street address with the Census Bureau, and
re-assigns ZIP code and council district. The auditor also read every
sampled permit's description in the City's layer against its category. The
descriptions are not stored here.

| Check | yes | no |
|---|---|---|
| Found in the source | 100 | |
| Issue date matches | 100 | |
| Category correct | 99 | 1 |
| Location matches | 100 | |
| Geography correct | 100 | |

What the notes record:
- **Category (the one "no"):** the City codes one renovation of an
  existing office as new construction, and the pipeline follows the code.
- **Location:** the Census geocoder matched 99 of 100 addresses, a median
  of 93 m from the City's point (90th percentile 273 m). The largest gaps
  are large sites such as the airport terminal (906 m). 97 land in the
  same ZIP code and council district as the point.
- **Source ZIP code:** blank on eight permits from 2021, and a
  single-building ZIP code on one.

The same script refetched all 27,848 permits and recomputed every
published row a count or a sum can check: permits per 1,000 parcels
(primary and excl_minor) and the declared-value total and median, for the
city, ZIP codes and council districts. All 3,936 rows equal the published
ones. Intervals and the trimmed and capped variants were not recomputed.
On all 27,585 permits with a current-format number, the number agrees with
the mapped sector and category.

**Not covered:** demolitions. The sample is drawn from the City's DPD
layer, so the `demolition` subgroup and `demolition_to_new_ratio` need
their own audit of the Data Midsouth snapshot (D30) before they publish.

## Rerunning

```sh
python pipelines/permits/tests/independent/trace_audit.py data/published/permits/audit/audit_sample_2026-10-06.csv data/published/permits evidence_2026-10-06.csv rows_2026-10-06.csv
```

It reads the live layer, so run it against outputs from the same day. The
check columns are the auditor's: no script fills them in.
