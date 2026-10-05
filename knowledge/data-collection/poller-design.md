---
type: Collection Method
title: Poller design
description: "Shared design of the Python pollers: stdlib fetch with retries, a multi-rate loop, crash-safe gzip JSON lines, and a log of every poll attempt."
resource: ../../pollers/common.py
tags: [collection, poller, python]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-04T20:45:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: common
    resource: ../../pollers/common.py
    title: pollers/common.py
    last_modified: 2026-09-27T20:05:32-05:00
  - id: research
    resource: ../../docs/research/mata-mlgw.md
    title: "Research: MATA and MLGW feeds"
    last_modified: 2026-09-25T20:55:57-05:00
  - id: decisions
    resource: ../../DECISIONS.md
    title: DECISIONS.md D15
    last_modified: 2026-10-01T21:20:45-05:00
---

# Why poll

MATA's realtime feed and MLGW's outage map show only the present. Restored
outages disappear and outage fields are revised in place. MATA regenerates
its static GTFS nightly as a rolling 30-day window and does not keep old
copies. History exists only if the project takes its own
snapshots.[^research]

# Parts

| Part | What it does |
|---|---|
| `fetch()` | GET with `urllib`, user agent `memphis-service-equity/0.1 (+https://github.com/jpbranson/mem-service-equity; civic research poller)`, 30 s timeout by default, 2 retries after 3 s and 6 s. Returns a `FetchResult` rather than raising. |
| `run_loop()` | Runs each `(interval_s, fn)` task on its own cadence until the run's time is up. Tasks run at the start and then every interval. A late task restarts its interval from now and never fires catch-up requests. |
| `JsonlGzWriter` | Buffers JSON lines and writes one gzip member per flush. Concatenated members form a valid gzip stream, so a crash loses at most the unflushed buffer. |
| `StatusFile` | This run's health for the project tracker (D28). A feed is failing after three failed polls in a row, and warns when a fifth of its polls failed. |

[MATA](mata-poller.md) and [MLGW](mlgw-poller.md) each build a poller class
on these parts.[^common]

# Every attempt is logged

Each poller writes a `*_polls_*` file with one line per attempt, failures
included: poll time, feed, ok, HTTP status, error, elapsed ms and bytes.
Uptime is computed from these logs, so a gap is measured instead of being
read as a ghost bus or a restored outage.[^decisions]

# Dependencies

Python 3.12. The only third-party package is `gtfs-realtime-bindings`, and
CLAUDE.md says to keep it that way.

[^common]: pollers/common.py
[^research]: "Research: MATA and MLGW feeds"
[^decisions]: DECISIONS.md D15
