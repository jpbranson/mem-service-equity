---
type: Operations
title: Poller scheduling and coverage
description: The pollers run as 170-minute GitHub Actions jobs every 2 hours, which covers only about half the time; an always-on host is prepared (H22).
tags: [collection, poller, github-actions, coverage]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-04T20:45:00-05:00 }
stale_after: 2026-11-04T00:00:00-06:00
sources:
  - id: poll-mata
    resource: ../../.github/workflows/poll-mata.yml
    title: poll-mata workflow
    last_modified: 2026-09-27T16:47:08-04:00
  - id: poll-mlgw
    resource: ../../.github/workflows/poll-mlgw.yml
    title: poll-mlgw workflow
    last_modified: 2026-09-27T16:47:08-04:00
  - id: decisions
    resource: ../../DECISIONS.md
    title: DECISIONS.md D15 and H22
    last_modified: 2026-10-01T21:20:45-05:00
  - id: host-readme
    resource: ../../pollers/host/README.md
    title: Always-on pollers (H22)
    last_modified: 2026-10-01T20:57:49-05:00
---

# Current schedule

| Workflow | Cron (UTC) | Poll time | Job timeout |
|---|---|---|---|
| `poll-mata.yml` | `7 */2 * * *` | 170 min | 190 min |
| `poll-mlgw.yml` | `30 */2 * * *` | 170 min | 190 min |

Runs start every 2 hours and last 170 minutes, so consecutive runs overlap
by 50 minutes. They start off the top of the hour because GitHub delays and
drops scheduled runs most there.[^poll-mata][^poll-mlgw] Both workflows also
accept `workflow_dispatch` with a `minutes` input.

# Coverage

The overlap is not enough. About half of the scheduled runs never start.
Measured from the poll logs for 2026-09-24 to 09-30, MATA covered 51% of
service hours and MLGW 49% of the day. No poll attempt failed: whole runs
were missing.[^decisions] Consequences:

- MATA: trips that fall in gaps are excluded rather than counted as ghost
  buses, but the peak-headway metric and the match-rate floor need the
  peaks.
- MLGW: an outage that ends in a gap has no known restoration time, and
  the six-month baseline builds up at half speed.

D15 also notes that GitHub's terms bar hosted runners from work "unrelated
to" the project.

# Prepared fix (H22)

`pollers/host/` runs each poller back to back under systemd
(`mse-poller@mata`, `mse-poller@mlgw`), with 120-minute runs by default and
the same archive and status scripts. A self-hosted runner would not help,
because the missing runs are never triggered. It still needs a host, a
fine-grained token and a cost decision. The README describes the
switch-over: run both for a few days, then remove the `schedule:`
triggers and keep `workflow_dispatch`.[^host-readme]

Update this concept when H22 closes.

[^poll-mata]: poll-mata workflow
[^poll-mlgw]: poll-mlgw workflow
[^decisions]: DECISIONS.md D15 and H22
[^host-readme]: Always-on pollers (H22)
