# H3 review packet: the 311 manual audit

_Prepared 2026-09-25 by Claude for the person doing the audit. **H3 is not
done.** Plan 5.6 requires at least 100 random records traced by hand, and no
one has traced them yet. The publish gate counts an audit only when a person
has filled in every check column and signed each row (D23)._

## What is here

[`audit_sample_2026-09-25_pretrace.csv`](audit_sample_2026-09-25_pretrace.csv)
holds the 100 random records the 311 run of 2026-09-25 drew for the audit
(`audit/audit_sample_2026-09-25.csv` in that run's output). Seed 20260925;
the sample is included, in-city requests, duplicates allowed. Each row has
three groups of columns:

1. **What the pipeline says:**
   - request type and status;
   - local open time and close date;
   - business days to close and age;
   - ZIP (ZCTA), council district and H3 cell;
   - whether it was marked a near-duplicate.
2. **`auto_*` columns: an automated pre-trace**
   ([`trace_audit.py`](../../../pipelines/311/tests/independent/trace_audit.py)),
   run on 2026-09-25:
   - It fetched each request again from the City's 311 layer.
   - It recomputed the dates, business days, ZIP and council district
     with the independent code from the H20 check (no shared code with the
     pipeline).
   - It asked the layer for earlier requests of the same type within 50 m
     and 7 days, to test the near-duplicate call (D6).
   - `auto_summary` is "ok" or lists what differs.
3. **Blank columns for you:** `1_found_in_source` to
   `5_geography_correct`, `auditor`, `notes`. Two links help:
   `source_lookup_url` opens the record in the City's layer, and `map_url`
   opens its location on a map.

**Pre-trace result: all 100 records matched on every automated check.** In
detail:
- found in the source, with the same type;
- the same local open time and close date;
- the same business days to close and age;
- inside the city, with the same ZIP and council district.

All six records marked as near-duplicates point to an earlier request of the
same type within 50 m and 7 days. No record left as a primary had an
unexplained earlier neighbor. Three requests are still open, and two are
"Resolved" (treated as closed; see H4).

## What the pre-trace cannot do for you

The pre-trace re-reads the same source and applies the same rules, so it
checks the pipeline's arithmetic, not its judgment. By hand, check:
- **Dates**:
  - Does the open time shown in the City's own 311 interface match?
  - Does the close date look real, not a placeholder?
  - Count the business days on a calendar for a few records. Skip weekends
    and City holidays; the open date itself is not counted (D5).
- **Location**:
  - On the map, is the point plausible for the request, e.g. on or next to a
    street for a pothole, at a house for missed trash?
  - Is it in the ZIP and council district shown? Use the City's council
    district map, not the pipeline's.
- **Duplicates**: for the six marked records, open both requests. Are they
  really the same problem?
- **Trace to a published number**: pick at least five records and find the
  published row they count in. That row has the same request type and
  area, a window that contains the open date (or close date for the
  re-report rate), and a variant of `primary`. Check that the record meets
  that metric's inclusion rules in its spec.

## Filling in and committing

1. Answer every check column with `yes`, `no` or `n/a`. Put your name in
   `auditor` on every row. Explain every `no` in `notes`: what was wrong
   and what was done about it.
2. Save the sheet as `pipelines/311/audits/audit_sample_2026-09-25.csv`.
   You may keep or delete the `auto_*` and link columns; the gate reads only
   the check columns, `auditor` and `notes`.
3. Commit it. The next run's publish status will then show condition 6 as
   met, or say what is still missing.

`memequity::audit_problems("pipelines/311/audits/audit_sample_2026-09-25.csv")`
lists anything still incomplete before you commit.

## Re-running the pre-trace

```sh
Rscript pipelines/311/tests/independent/export_holidays.R /tmp/holidays.csv 2026
python pipelines/311/tests/independent/trace_audit.py data/published/311/audit/audit_sample_2026-09-25.csv /tmp/holidays.csv /tmp/trace.csv
```

It takes about a minute. A status or close date that changed after the run
is reported as a change, not an error.
