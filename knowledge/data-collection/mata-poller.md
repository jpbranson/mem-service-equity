---
type: Poller
title: MATA poller
description: Polls MATA's GTFS-Realtime vehicle positions every 30 s and alerts every 15 min, and archives the static GTFS zip once per run.
resource: ../../pollers/mata_poller.py
tags: [collection, poller, mata, gtfs, transit]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-04T20:45:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: mata-poller
    resource: ../../pollers/mata_poller.py
    title: pollers/mata_poller.py
    last_modified: 2026-09-27T20:05:32-05:00
  - id: research
    resource: ../../docs/research/mata-mlgw.md
    title: "Research: MATA and MLGW feeds"
    last_modified: 2026-09-25T20:55:57-05:00
  - id: h16
    resource: ../../DECISIONS.md
    title: DECISIONS.md H16 (MATA data terms)
    last_modified: 2026-10-01T21:20:45-05:00
---

# Feeds

| Feed | URL | Every | Written to |
|---|---|---|---|
| Vehicle positions | `https://gtfsrt.mata.cadavl.com/ProfilGtfsRt2_0RSProducer-MATA/VehiclePosition.pb` | 30 s | `mata_positions_<run>.jsonl.gz`, one line per new report |
| Alerts | `https://gtfsrt.mata.cadavl.com/ProfilGtfsRt2_0RSProducer-MATA/Alert.pb` | 15 min | `mata_alerts_<run>.jsonl.gz`, one line per poll |
| Static GTFS | `https://gtfs.mata.cadavl.com/MATA/GTFS/GTFS_MATA.zip` | once, at the start of each run | `mata_gtfs_<date>_<sha256 prefix>.zip` |
| Every attempt | | | `mata_polls_<run>.jsonl.gz` |

Files go to `<out>/mata/<YYYY-MM-DD>/`. The run id is the start time,
`YYYYMMDDTHHMMSSZ`.[^mata-poller] `TripUpdate.pb` exists but is not
polled.[^research]

# Details

- Protobuf is decoded with `gtfs-realtime-bindings`. A body that fails to
  decode is logged as a failed poll (`decode: …`) and does not stop the run.
- Within a run, reports are deduplicated on (vehicle id, or entity id if
  there is none, and timestamp). Duplicates between overlapping runs are
  removed downstream.
- The static zip counts as fetched only if it starts with `PK`. Its name
  carries a content hash, so overlapping runs share one file and the
  archive skips names it already has.
- The feeds are open and need no key. No license or developer terms were
  found. Asking MATA to confirm archiving and publishing is H16, which is
  deferred.[^h16]

# Downstream

`gh release download archive-mata-<week>`, then
`pipelines/mata/run.R --archive DIR` matches trips. A window is computed
only when the data cover 90% of its days. See
[scheduling and coverage](poller-scheduling.md).

[^mata-poller]: pollers/mata_poller.py
[^research]: "Research: MATA and MLGW feeds"
[^h16]: DECISIONS.md H16 (MATA data terms)
