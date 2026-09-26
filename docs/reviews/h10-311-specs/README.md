# H10 review packet: the 311 specs

_Prepared 2026-09-25 by Claude for the human reviewer. **Nothing here is
frozen.** Freezing a spec is the reviewer's decision (plan 5.7, condition 1),
and every spec under `specs/311/` is still `draft`._

This packet compares each spec with what the code actually computes, using
the independent recomputation (`docs/reviews/h20-golden/`) and the
2026-09-23 raw data. Where they disagree, it sets out the options. It does not
decide which one is right: fixing the code or fixing the spec text is the
reviewer's call.

## How to freeze a spec

1. Read the spec, including its three adversarial objections.
2. Resolve the issues below: edit the spec, ask for a code change, or accept
   the issue and note why.
3. Set `status: frozen`. `spec_problems()` must then return nothing: at
   least three answered objections, at least two alternatives for every
   arbitrary threshold, a `reconciliation` block with measures and text,
   and a source URL for an official promise. The package test "every
   repository spec parses and has no problems" enforces this in CI.
4. From then on, a definition change bumps MAJOR and starts a new series. It
   also means rebuilding the golden file, and the H20 recomputation must be
   updated to match.

Freezing a spec is not enough to publish. The publish status lists the other
conditions: the H3 audit, reconciliation, and so on.

## Status at a glance

| Spec | Computed? | Can publish once frozen? |
|---|---|---|
| `requests_per_1000` v0.2 | yes | once H3 is done and reconciliation passes |
| `median_business_days_to_close` v0.1 | yes | same, but see C3 on missing close dates first |
| `reopen_rate` v0.1 | yes | same |
| `pct_within_target` v0.1 | yes (potholes only) | **no.** It needs the City's own on-time figure (H14, deferred by D19) |
| `closed_without_action_rate` v0.1 | **no** | **no.** It needs the disposition audit first (H4) |

## Issues that affect several specs

**C1. Geographies.** The specs for the median, the target share and the
re-report rate list `[citywide, zcta, council_district, h3_9]`. The code
also publishes `super_district` and `reference_neighborhood` rows for all
three (`geo_levels()` in `pipelines/311/R/metrics.R`), and the site shows
them.
- Option A: add both to the specs. This matches what is published.
- Option B: stop computing them.

**C2. What "citywide" includes.** `pct_within_target` says "all requests for
citywide". The code counts only requests located inside the city limits, for
every geography including citywide. On 2026-09-23, 1,307 of 407,054 records
(0.3%) had no usable location: 24 were missing one and 1,283 were outside
the county box.
- Option A: correct the spec text. A request with no location cannot be
  placed inside the city, and this keeps citywide consistent with the sum of
  its areas.
- Option B: count unlocated requests in citywide only.

**C3. Closed requests with no close date (material).** The median and target
specs list "close before open" as their only close-date exclusion. The code
excludes every close-date problem, and on 2026-09-23 there were 17,531 of
them among 381,765 closed, included requests (4.6%):

| Problem | Requests |
|---|---|
| Missing close date | 16,774 |
| Close before open | 734 |
| Sentinel close date (year 0001 or 1202) | 21 |
| Close in the future | 2 |

The missing close dates are **concentrated in time, not in place.** By
council district (the City's own field) the share ranges only from 4.2% to
5.2%. By month opened it swings widely:

| Opened | Share of closed requests with no close date |
|---|---|
| 2023-10 to 2025-07 | 0.0–0.9% |
| 2025-08 | 11.8% |
| 2025-09 | 16.9% |
| 2025-10 | 2.3% |
| 2025-11 | 15.0% |
| **2025-12** | **60.0%** |
| **2026-01** | **45.9%** |
| 2026-02 to 2026-04 | 0.9–4.2% |
| 2026-05 | 16.5% |
| 2026-06 to 2026-09 | 0.1–0.2% |

Almost all are status "Closed" (16,542); 232 are "Resolved". The worst
months cover the late-January 2026 ice storm, and bulk closure without dates
is one possible cause, **not confirmed**. Any 12-month window that includes
December 2025 or January 2026 therefore drops about half of those months'
closed requests from the timing metrics. If the dropped requests closed
unusually fast or slow, the median is biased. The current 90-day window is
barely affected.
- Decide: list all four close problems in `exclusions`, and add a confounder
  about the concentration in time.
- Consider: a validation check on the monthly share of missing close dates,
  plus a methodology note that names the affected months.
- Ask the City (H8 question 3): why do these requests have no close date?

**C4. Business-day calendar.** D5 says the business-day convention "must
still be checked against any worked examples the city publishes". None have
been found. Separately, holidays for 2023–2025 are rebuilt from rules, and the
weekend shifts for MLK Memorial Day and Christmas Eve are inferred (H13).
Current 12-month windows include October–December 2025.

**C5. Broken references in spec text. Fixed 2026-09-25**, in text only and
recorded in each change log. These had no effect on any definition:
- `requests_per_1000` and `reopen_rate` cite `docs/research/311.md`, which
  does not exist. The note is `docs/research/311-permits-districts.md`.
- `pct_within_target` says targets live in
  `pipelines/311/config/targets.csv`. They are columns of
  `config/request_types.csv` (`target_low_bd`, `target_high_bd`,
  `target_source_url`).
- `closed_without_action_rate` cites `pipelines/311/config/disposition_map.csv`,
  which does not exist yet (H4).

## Issues in single specs

**`requests_per_1000`**
- Objection 2's answer says small-population areas "are flagged". Since v0.2
  they are suppressed below 1,000 in-city residents (`min_population`).
- Objection 3's answer promises a split by origin "if the source
  distinguishes internal from resident-originated requests". No documented
  origin field was found:
  - `GROUP_NAME` mixes city names ("Memphis" 250,075, "MEMPHIS" 77,712,
    "MEM", "MEMPHI") with "CITIZEN" (61,239).
  - The only clear origin signal is SeeClickFix (`SCF_URL` set on 19% of
    records), which the pipeline already records as `origin`.
  - Decide: split by SeeClickFix versus other, drop the promise, or ask the
    City first (H8 question 4).

**`median_business_days_to_close`**
- Objection 3's answer says the calendar "is tested against the city's worked
  examples where they exist". None exist (C4). Reword, or find an example.
- `h3_9` rows exist only for the eight headline request types
  (`headline = TRUE` in `config/request_types.csv`). The spec does not say
  this. The same applies to the target share and the re-report rate.

**`pct_within_target`**
- The threshold alternative "the city's own on-time rule, once identified"
  is not computed, since there is no such rule yet. The published variants
  are the upper bound (primary) and lower bound.
- The exclusion "Test or internal records identified in source validation"
  has nothing behind it: no such records are identified.
- It cannot publish even when frozen, because its reconciliation measure
  (`on_time_rate`) has no official figure (H14).

**`reopen_rate`**
- **Same-day re-reports never count.** The code requires the new request to
  open at least one calendar day after the close date (`0 < lag`). A resident
  who re-files the day a request is closed is not counted. The spec says
  "within 30 days of the close". Say "1 to 30 days after the close date", or
  change the code. The H20 check shows the choice matters: counting same-day
  re-reports changes 193 of the 515 golden rows.
- Objection 2's answer: "Our system has an explicit reopen status; use it."
  The source has statuses "Back to Department" (1,139 on 2026-09-23) and
  "Back to MCSC" (477) that may work as reopen statuses. Ask the City (H8
  question 3) what they mean before freezing.

**`closed_without_action_rate`**
- Cannot be frozen until the disposition audit (H4) defines the mapping. The
  worksheet is generated on every run: `audit/disposition_worksheet_<date>.csv`.

## New in this review: the reconciliation field (D22)

Each spec now declares what it is reconciled against. Please confirm the
declarations are adequate:
- The four comparison metrics are reconciled against **official request
  counts** (`requests_created`). That checks the fetch, the type mapping and
  the date handling. It does **not** check timing or dispositions, which rely
  on the manual audit (H3). Accepting a volume check for a timing metric is
  a judgment call the reviewer should make explicitly.
- `pct_within_target` names `on_time_rate`, which does not exist yet.

## Sign-off

For each spec, record the decision here and in the spec's change log.

| Spec | Read | Issues resolved | Frozen (name, date) |
|---|---|---|---|
| `requests_per_1000` | | | |
| `median_business_days_to_close` | | | |
| `reopen_rate` | | | |
| `pct_within_target` | | | |
| `closed_without_action_rate` | | | |
