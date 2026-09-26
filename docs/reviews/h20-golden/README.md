# H20 review packet: the 311 golden file

_Prepared 2026-09-25 by Claude for a human reviewer. **H20 is not done**:
plan 5.3 asks for golden outputs checked by hand, and only the mechanical
half below has been done._

## What was checked mechanically

`pipelines/311/tests/golden/golden_metrics.csv` (515 rows, frozen from the
v0.1 code) was recomputed by a second implementation,
[`pipelines/311/tests/independent/recompute_golden.py`](../../../pipelines/311/tests/independent/recompute_golden.py).
It was written from the specs and DECISIONS (D5 business days, D6 near
duplicates, D8 boundary rule, D9 censoring) and shares no code with the R
pipeline. It uses only the Python standard library, with its own US Central
time conversion, its own EPSG:32136 projection, point-in-polygon, Kaplan–Meier
median with log-log interval, and Wilson interval.

**Result: all 515 rows agree** (`n`, value, both interval bounds and the
suppression flag, to 1e-9), and the recomputation produces no rows that the
golden file lacks. Full row-by-row output: [`comparison.csv`](comparison.csv).

To show the comparison can fail, six deliberate mutations were made to the
independent code. Each one broke agreement:

| Mutation | Rows that then disagree |
|---|---|
| Business days count the open date too (breaks D5) | 74 |
| Near-duplicate window 6 days instead of 7 (D6) | 125 |
| Near-duplicate radius 45 m instead of 50 m (D6) | 105 |
| No daylight saving time (always UTC−6) | 172 |
| A request opened the same day as the close counts as a re-report | 193 |
| z = 1.96 instead of 1.959964 in the intervals | 245 |

### What this does not cover

The two implementations share their inputs, so an error in any of these
would pass unnoticed:
- the raw golden records (`golden_raw.rds`);
- the config (`status_map.csv`, `request_types.csv` targets, reference ZIPs);
- the boundary files;
- the holiday dates, which are taken from `memequity::holiday_calendar()`
  (the calendar is its own open item, H13).

Both implementations also follow the same reading of the specs. Where a spec
is ambiguous, they agree because the second one was written to the documented
convention. Two such conventions are worth a reviewer's attention, and both
are listed in the H10 packet:
- A re-report must open **at least one calendar day after** the close date.
  A same-day re-report does not count. `reopen_rate` does not say this.
- When the Kaplan–Meier curve sits exactly at 0.5, the median is the midpoint
  to the next event time (the `survival` package convention).

## What a person still has to do

1. Recompute the three worksheet rows by hand with a calendar. Each file's
   first line gives the published value, interval and `n`:
   - [`handcheck_pct_within_target.csv`](handcheck_pct_within_target.csv):
     potholes in ZIP 38117, 90 days, 36 requests. Check each request's
     business days to close (the open date is not counted; weekends and city
     holidays are skipped) and whether it is within 10.
   - [`handcheck_median_business_days_to_close.csv`](handcheck_median_business_days_to_close.csv):
     potholes in ZIP 38104, 12 months, 21 requests. With no open requests
     the Kaplan–Meier median is the ordinary median of the 21 values.
   - [`handcheck_reopen_rate.csv`](handcheck_reopen_rate.csv): potholes in
     ZIP 38117, 90 days, 30 closed requests. Two were re-reported within
     50 m, after 18 and 33 days. Only the first is within 30 days, so the
     rate is 1/30. Spot-check both against the map: a later pothole request
     within 50 m, opened 1–30 (or 1–60) days after the close.
2. For a few of those requests, look the `sr_id` up in the city's 311
   layer and confirm the dates. This also checks the shared raw input.
3. If everything agrees, mark H20 done in `DECISIONS.md` with your name
   and the date.

## Re-running

```sh
Rscript pipelines/311/tests/independent/export_golden.R /tmp/golden_export
python pipelines/311/tests/independent/recompute_golden.py /tmp/golden_export --out /tmp/golden_check
```

It takes about 5 seconds and exits with status 1 if any row disagrees. Rerun
it whenever the golden file is rebuilt, which only happens on a spec version
change. The Python must then be updated to the new spec independently, or it
proves nothing.
