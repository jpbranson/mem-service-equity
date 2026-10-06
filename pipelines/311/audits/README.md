# 311 audits

Completed audit sheets for publication condition 6 (plan 5.6, DECISIONS.md
H3, D23). The publish gate reads the newest `audit_*.csv` here.

## audit_sample_2026-10-06.csv

The 100 records the 2026-10-06 run drew (seed 20261006), audited the same
day by Claude (claude-fable-5-1) at the owner's direction (D33). **No person
has traced these records.** Every row names the auditor.

Columns:
- the pipeline's values for the record;
- `auto_*`: the pre-trace (`tests/independent/trace_audit.py`), which
  fetches the record again and recomputes dates, business days and
  geography with independent code;
- `ev_*`: further evidence (`tests/independent/audit_evidence.py`): the
  City's own date, ZIP code and council district fields, the street address
  geocoded by the Census Bureau, how many requests share the exact close
  time, business days counted a third way, and the published ZIP-code rows
  the record counts in, recomputed from a fresh fetch of its request type;
- the five checks, `auditor` and `notes`.

`published_rows_recomputed_2026-10-06.csv` lists those recomputed rows: 534
rows of the three frozen metrics, all equal to the published ones (n, value
and interval).

| Check | yes | no | n/a |
|---|---|---|---|
| Found in the source | 100 | | |
| Dates match | 97 | 3 | |
| Location matches | 100 | | |
| Business days correct | 96 | | 4 |
| Geography correct | 100 | | |

What the notes record:
- **Mass closure (the three "no"):** three requests were closed on
  2025-09-22, each at a time shared to the second by 753 to 999 requests. At least
  23,684 requests were closed that afternoon in such batches. The close
  date matches the source but is not when the work was done. No window
  published on 2026-10-06 contains that day.
- **Reported before created:** on three requests the City's
  `REPORTED_DATE` is one to three days before the record's creation, which
  the metric counts from.
- **No close date:** four requests have status Closed and no close date,
  so they are left out of the timing metrics (the four "n/a").
- **Near-duplicates:** four of the five marked look like second reports.
  The fifth is a missed collection 6.96 days after an earlier one, more
  likely a second miss; the 7-day rule (D6) spans the weekly cycle.
- **Location:** 92 records have a street address. The Census geocoder
  places them a median of 31 m from the City's point (90th percentile
  75 m, largest 423 m, a vacant lot), and 91 land in the same ZIP code and
  council district.

## Rerunning

```sh
Rscript pipelines/311/tests/independent/export_holidays.R holidays.csv 2026
python pipelines/311/tests/independent/trace_audit.py data/published/311/audit/audit_sample_2026-10-06.csv holidays.csv pretrace_2026-10-06.csv
python pipelines/311/tests/independent/audit_evidence.py pretrace_2026-10-06.csv holidays.csv data/published/311 evidence_2026-10-06.csv rows_2026-10-06.csv
```

The second script takes about five minutes. Both read the live layer, so
records edited since the run can differ, and the scripts say how many were.
The check columns are the auditor's: no script fills them in.
