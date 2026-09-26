# Flight log

Running log for the multi-step work started 2026-09-25 ("complete all the
next steps"). If a session is interrupted, read this file top to bottom,
then continue from **Next action**. Entries are appended, never rewritten.

Status markers: `[ ]` not started · `[~]` in progress · `[x]` done and
verified · `[!]` blocked, needs a human (reason given) · `[p]` prepared for a
human; the human part is still open. Nothing is marked `[x]` unless it was
actually done. Items that belong to a person (the H-items) are never marked
done by Claude, only `[p]`.

## Environment notes (for resuming)

- Local R: use `C:\Program Files\R\R-4.3.3\bin\Rscript.exe` (4.3.3 has every
  package; 4.6.1 has none). In Git Bash:
  `RS="/c/Program Files/R/R-4.3.3/bin/Rscript.exe"`,
  `RCMD="/c/Program Files/R/R-4.3.3/bin/R.exe"`.
- Raw 311 cache from 2026-09-23: `data/cache/311/raw.rds`.
- Commits go straight to `main` (user preference). **Nothing is pushed
  without asking the user.** Pushing to `main` triggers `deploy-site`.

## Plan

Order follows the "next steps" list, except 3b runs first: the USPS branch
adds D21, so it has to land before any new D-entry to avoid an ID clash.

| # | Step | Status |
|---|---|---|
| 0 | Baseline: package, 311 and poller tests pass locally | [x] |
| 3b | USPS branch: review, then merge into local `main` (or recommend deletion) | [x] merged locally; remote branch deletion left to user |
| 1 | 311 reconciliation: find an official figure, record a D-entry, wire it into the gate | [x] one official count reproduces; adequacy flagged for H10 |
| 2a | H10 spec freeze: pre-review packet for the 311 specs | [p] packet written; freeze is the reviewer's |
| 2b | H3 manual audit: 100-record sample with an automated source trace | [p] 100/100 pass the pre-trace; manual audit open |
| 2c | H20 golden file: independent recomputation of sample rows | [p] all 515 rows agree; hand check open |
| 2d | H9 reference ZIPs: evidence packet | [p] packet written; decision is the user's |
| 2e | H6 geocoder check: draw the 200-address sample, automated comparison | [p] sample drawn + measured (96.5% in disk); hand check open |
| 2f | H7 reviewer: outreach draft | [p] draft written; not sent |
| 2g | H8 courtesy preview: letter draft | [p] draft + public log written; not sent |
| 3a | H11 follow-up: letter draft for use after 2026-10-02 | [p] draft written; send only if no reply by 10-02 |
| 4a | Permits pipeline (Phase 4) | [x] built, tested, on the site (gated); demolitions blocked (H21) |
| 4b | Food-safety ingest against the expected export (D13) | [x] built + tested on a synthetic export; real export pending (H11) |
| 4c | H19: MLGW spec revision draft | [p] v0.2 drafts written; H19 confirmation is the reviewer's |
| 4d | MATA trip matching (Phase 5) | [x] built + tested; runs on the archive; windows need more data (H22) |

## Log

### 2026-09-25

- 19:00 CT. Log created. Local R 4.3.3 found with all packages; 4.6.1 has
  none. Starting step 0.
- 19:10 CT. Step 0 done. memequity tests pass, 311 tests pass (after
  `R CMD INSTALL packages/memequity`), pollers 11/11 pass. pytest is not in
  the global Python 3.14, so there is a throwaway venv in the session
  scratchpad (`.../scratchpad/venv`); recreate it with
  `python -m venv <dir>` + `pip install -r pollers/requirements.txt pytest`.

- 19:20 CT. Step 3b done. Read the USPS note (245 lines, consistent with
  plan 12 and D11) and D21 (records the owner's own 2026-09-25 decision).
  Fast-forwarded local `main` to `1f83bbe`. The remote branch
  `claude/usps-service-performance-uwwldp` can be deleted once `main` is
  pushed; that is the user's call. New D-entries start at **D22**.

- 19:40 CT. Step 1 in progress.
  - Found: `run.R` passes `reconciliation = NULL` to the gate, so condition
    5 can never pass for 311; the only named 311 reconciliation (city
    on-time %) does not exist (H14, deferred by D19).
  - Research on official 311 figures delegated to a background agent
    (budget books, Feb 2026 Council deck, Data Hub dashboards). Result
    pending; if the session dies, re-run that research.
  - Built the general mechanism (uncommitted until the 311 part is done):
    `packages/memequity/R/reconcile.R` (`read_official_figures`,
    `reconcile_figures`, `spec_reconciliation`, `write_reconciliation`;
    tolerance 2% or half the rounding unit, larger gaps need a
    `gap_note`), `reconciliation` is now a required spec field
    (`measures` + `text`), methodology renders per-figure lines. Template
    and all non-311 specs carry plan-5.5 reconciliation declarations.
    memequity tests pass (incl. 6 new tests).
  - Still to do for step 1: 311 spec declarations, the official figures
    file, `pipelines/311/R/reconcile.R`, wiring in `run.R`, a repo-wide
    spec test, D22, docs.

- 20:15 CT. Step 2c prepared (H20 stays open for a human).
  - `pipelines/311/tests/independent/` (export_golden.R +
    recompute_golden.py, stdlib-only second implementation): **all 515
    golden rows agree** exactly; six deliberate mutations each break
    agreement (74–245 rows), so the check has teeth.
  - Packet: `docs/reviews/h20-golden/` (README, comparison.csv, three
    by-hand worksheets). Human still has to redo the three worksheet rows
    and look a few `sr_id`s up in the source.
  - Found for H10: `reopen_rate` silently requires a re-report to open
    >= 1 day after the close (same-day re-reports never count).

- 20:45 CT. While the research agent runs:
  - Gate hardening for H3 (uncommitted, goes with step 1): `publish_gate`
    now calls new `audit_problems()`. A blank worksheet copied into
    `pipelines/311/audits/` used to satisfy condition 6; now the sheet needs
    >= 100 rows, every `N_*` check answered yes/no/n/a, an auditor on every
    row, and a note on every "no". Tests added; memequity tests pass.
  - Drafts written (uncommitted): `docs/records-requests/h11-follow-up.md`,
    `docs/outreach/h7-independent-reviewer.md`,
    `docs/outreach/h8-courtesy-preview-311.md`,
    `docs/outreach/courtesy-preview-log.md`. Nothing sent.
  - H9 packet needs 311 volumes by ZIP; the local 9/23 outputs predate
    `requests_per_1000`, so it waits for a fresh pipeline run (after
    step 1).

- 21:30 CT. Step 1 code done except the figures themselves (uncommitted):
  `pipelines/311/R/reconcile.R` (`requests_created` measure; refuses
  pre-migration figures), wired into `run.R` (warning-level validation
  checks, `reconciliation_311.csv`, methodology, per-spec gate input;
  newest committed audit wins), `pipelines/311/reconciliation/README.md`,
  311 spec declarations (`requests_created` for the four comparison
  metrics, `on_time_rate` for `pct_within_target`), tests: repo-wide spec
  check, SPEC_VERSIONS sync, reconciliation tests. All suites pass.
- 21:30 CT. Step 2a prepared: `docs/reviews/h10-311-specs/README.md`.
  Key finding: 16,774 closed requests have no close date and they cluster
  in time (Dec 2025 60%, Jan 2026 46%), so 12-month timing metrics drop
  about half of those months. Also found: geographies, citywide scope and
  same-day re-report mismatches between specs and code. Fixed broken
  references in 4 specs (text only), change-log line added to every spec.

- 22:10 CT. Committed step-1 mechanism + D22/D23 + H10 packet (72f6255),
  H3 + H9 packets (c9d8f29). Fresh 311 run as of 2026-09-25 is in
  `data/published/311` (raw cache `data/cache/311/raw_2026-09-25.rds`,
  408,375 rows, validation pass).
- 22:15 CT. H6: the parcel layer's PropertyAddress is empty on all
  350,835 records, so `geography/check_geocoder.R` now reverse-geocodes
  random in-city parcels with the City's own address-point locator
  (311/LiveLinkGeolocator, no robots.txt) and tests the Census geocoder
  against those official points. First run ran out of candidates (31%
  yield); rerunning with an 8x draw.
- 22:20 CT. Step 4a started. **Found: Data Midsouth robots.txt disallows
  /api/ for all but Googlebot**, so it cannot be used (D11). Recorded D24,
  new H21 (demolition permits), corrected the research note. Permits
  pipeline will use the DPD layer only (27,501 permits, 2021-01 to
  2026-08, last edited 2026-09-01; no demolitions).

- 23:10 CT. H6 packet committed (7ad103e): 93% Census match, median 35 m,
  96.5% inside the address point's disk; Nominatim put "HWY 78" 9-20 km
  off. Parcel denominators committed (032e7bd): 236,552 in-city parcels,
  vintage 2022-08.
- 23:40 CT. Step 1 done. Research agent: no citywide 311 figure exists;
  budget-book KPIs only. **Verified on the PDF pages** and transcribed:
  FY25 street-sweeping requests 1,424 (p. 371; layer 1,423, within
  tolerance) and FY25 pothole mean days 2.7 (p. 372; layer 2.56, outside
  tolerance, gates nothing). D22 and H14 updated (bulk waste 48 h series;
  conflicting pothole targets), research note updated (incl. Granicus
  robots.txt disallows all), H10 packet notes condition 5 rests on one
  small figure. Removed a scratch file with staff usernames.
- 23:40 CT. Permits so far: `pipelines/permits/R/fetch.R`,
  `reconciliation/fetch_bps.R` + `official_figures.csv` (BPS 99990,
  2021-2025: 843/875/707/519/929; DPD new residential 834/891/692/779/906;
  the Census itself revised 2024 from 824 (Dec YTD) to 519 (annual) and
  2025 from 816 to 929). `memequity::bootstrap_total_ci` added (untested
  yet). Raw DPD cache `data/cache/permits/raw_2026-09-25.rds`.

- 00:40 CT (09-26). Step 4a done.
  - Commits: 4096036 (step 1 figures), 6cfc243 (permits pipeline); this
    commit adds the site, workflows and docs.
  - Permits run end to end on 2026-09-25 data: validation pass (3
    reconciliation warnings); 18,771 in-city permits; about 2.5 min
    (bootstrap).
  - Reconciliation: 2021 and 2022 within 2%; 2023 −2.1% has no note (so
    the permits metrics stay blocked on condition 5, honestly); 2024 and
    2025 carry factual notes about the Census's own YTD-vs-annual
    revisions.
  - Site: app.js generalized by pipeline, with a new "Compare areas:
    investment" section. The methodology page loads both pipelines. Checked
    in the browser pane (gated and preview builds; no console errors).
    `.claude/launch.json` (static server on :8765) is local and not
    committed.
  - deploy-site runs permits after 311 with continue-on-error.
  - New spec field `blocked` (the gate reports it first).

- 01:25 CT. Step 4b done.
  - `pipelines/food-safety/`: ingest via `config/column_map.yml`
    (placeholder column names from the records request), inspection-type
    map, rules.yml (threshold 70 from the 2014 TDH release; 6-month
    interval from Rule 1200-23-01-.08), a pluggable geocoder (Census
    exact/non-exact only), and four metrics over citywide, ZIP, district
    and h3_8.
  - Tests on a synthetic export (fictitious "Test Grill N") pass, and
    run.R ran end to end offline via a pre-filled geocode cache.
  - The inbox is gitignored except its README.
  - Specs bumped to 0.2. No golden file or reconciliation figure until the
    real export arrives.

- 01:40 CT. Step 4c drafted.
  - The three MLGW specs are now v0.2, restated for point outages from the
    research note and the committed poller fixture: OUTAGE_NO events,
    two-poll restoration, 2-hour reappearance rule, point-in-area joins
    plus the D16 disk, planned outages excluded via OUT_CAUSE ("Planned
    Construction" seen), and customer-hours summed over snapshots with ACS
    households as the denominator.
  - H19 stays unchecked, with a note. Nothing is implemented; the MLGW
    pipeline needs 6 months of history anyway.

- 02:40 CT. Step 4d done.
  - **Found (H22, new):** the pollers cover only about half of the time.
    MATA vehicle polls covered 49% and 50% of service hours on 9/24 and
    9/25, and MLGW 50%, because GitHub never starts about half of the
    scheduled runs (0 failed polls). Gaps last 2-4 h and include both 9/24
    rush hours. D15 updated with the numbers.
  - `pipelines/mata/`:
    - `R/`: archive, gtfs, match, arrivals, metrics, pipeline; plus
      `run.R --archive DIR`.
    - Schedule in force per date; match by trip_id (RT start_date is
      empty; the service date is the local date).
    - Measurable trips need their full span ±15 min covered. Ghost versus
      unobserved is decided by block.
    - Arrivals are interpolated along the shape (shape_dist_traveled is in
      metres, about 0.3% longer than projected; rescaled). The first stop
      is excluded.
    - Windows need 90% of days with data.
  - First archive (9/23-9/25, local cache `data/cache/mata/2026-W39`):
    391 measurable trips, 7.4% ghost, about 66-67% on time [-1,+5]; 15 of
    24 routes above the 85% floor. By default no metric is written, because
    no window has enough data.
  - Spec findings, all recorded in the specs:
    - No route runs every ≤30 min at peak (the best is 45), so
      peak_headway_ratio is empty under its own rule.
    - The ghost rate conflicted with the match floor; the floor now applies
      only to on-time.
    - Specs bumped to 0.2.
  - Tests on a synthetic 5 km route (arrivals exact to 1 s). CI runs them.

- 02:55 CT. Final pass: memequity, 311, permits, food-safety and MATA
  suites all pass; pollers 11/11; independent golden check 515/515;
  app.js parses. Preview server stopped.

## Handoff: what is left for a person

Nothing is pushed. `origin/main` is at bdb1300 and local `main` is ahead
by every commit above.
- **Push and branch cleanup (the user's call).** Push `main`; then
  `origin/claude/usps-service-performance-uwwldp` can be deleted, since it
  is merged. The first push triggers `deploy-site`, which now also runs
  permits.
- **Prepared, still open** (packets in `docs/reviews/`, drafts in
  `docs/outreach/` and `docs/records-requests/`):
  - H3: audit the 311 sample by hand.
  - H6: hand-check the geocoder sample; decide the Nominatim fallback.
  - H7 and H8: send the outreach letters.
  - H9: decide the reference ZIPs.
  - H10: review and freeze the specs; confirm D22 (count-only
    reconciliation for timing metrics).
  - H11: follow up on 2026-10-05 if TDH is silent.
  - H19: confirm the MLGW v0.2 specs.
  - H20: redo three golden rows by hand.
- **New human items:**
  - H21: a source of demolition permits.
  - H22: an always-on host for the pollers.
- **Spec questions raised:**
  - The permits 2023 Census gap (−2.1%) is unexplained.
  - peak_headway_ratio's 30-minute rule excludes every route.
  - The MLGW denominator: households or housing units.
- **Local-only files, not committed:** `.claude/launch.json` (static
  server on :8765) and the data caches under `data/cache/`.

### 2026-09-26

- 20:55 CT (09-25). At the user's request: pushed `main` (bdb1300..c8ae9a2,
  17 commits) and deleted `origin/claude/usps-service-performance-uwwldp`
  (merged).
- The push's CI passed on Linux:
  - `test-memequity` succeeded (package, 311, permits, food-safety and
    MATA suites).
  - `deploy-site` succeeded, including the permits tests, run and archive
    (new release `data-permits-2026-09`).
- The live site was rebuilt at 01:51Z, not a preview: 311 through 9/24,
  permits through 8/31, 0 metrics publishable (expected).

## Next action

None pending. The handoff list above still stands (H-items, H21, H22 and
the spec questions); the push and branch items are done. Parts: parcel denominators
(`geography/fetch_parcels.R`), `pipelines/permits/` (fetch DPD without
Description, normalize, category map, metrics for permits_per_1000 and
declared value; demolition ratio blocked by H21), BPS reconciliation,
tests + golden, site + deploy integration, docs. Step 1 figures still
pending from the research agent.
