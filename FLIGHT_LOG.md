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
| 1 | 311 reconciliation: find an official figure, record a D-entry, wire it into the gate | [ ] |
| 2a | H10 spec freeze: pre-review packet for the 311 specs | [ ] |
| 2b | H3 manual audit: 100-record sample with an automated source trace | [ ] |
| 2c | H20 golden file: independent recomputation of sample rows | [p] all 515 rows agree; hand check open |
| 2d | H9 reference ZIPs: evidence packet | [ ] |
| 2e | H6 geocoder check: draw the 200-address sample, automated comparison | [ ] |
| 2f | H7 reviewer: outreach draft | [ ] |
| 2g | H8 courtesy preview: letter draft | [ ] |
| 3a | H11 follow-up: letter draft for use after 2026-10-02 | [ ] |
| 4a | Permits pipeline (Phase 4) | [ ] |
| 4b | Food-safety ingest against the expected export (D13) | [ ] |
| 4c | H19: MLGW spec revision draft | [ ] |
| 4d | MATA trip matching (Phase 5) | [ ] |

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

## Next action

Step 1: wait for the research result, then finish the 311 part (list
under 19:40). Commit step 2c files with step 1 or separately.
