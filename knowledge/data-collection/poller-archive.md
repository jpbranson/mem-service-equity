---
type: Storage
title: Poller archive
description: Poller output is uploaded every 30 minutes, after a gzip -t check, to weekly GitHub releases named archive-<source>-<YYYY>-W<ww>.
tags: [collection, poller, storage, github-releases]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-04T21:00:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: archive-release
    resource: ../../pollers/archive_release.sh
    title: pollers/archive_release.sh
    last_modified: 2026-09-23T16:02:12-05:00
  - id: poll-with-uploads
    resource: ../../pollers/poll_with_uploads.sh
    title: pollers/poll_with_uploads.sh
    last_modified: 2026-09-27T16:47:08-04:00
  - id: status-release
    resource: ../../pollers/status_release.sh
    title: pollers/status_release.sh
    last_modified: 2026-09-27T16:47:08-04:00
  - id: d7
    resource: ../../DECISIONS.md
    title: DECISIONS.md D7 (interim storage) and H1
    last_modified: 2026-10-01T21:20:45-05:00
---

# Layout

- One prerelease per source and ISO week, tagged
  `archive-<source>-<ISO year>-W<ISO week>`. Weekly releases stay under
  GitHub's 1,000-asset limit, and the raw data (about 1 GB a year) are kept
  out of git history.[^d7]
- Assets are each run's gzip JSON-lines files, plus MATA's static GTFS zips.
- `ARCHIVE_WEEK` is fixed when the job starts, so one run never spans two
  releases.

# Upload

- `poll_with_uploads.sh` starts the poller in the background and, at an
  interval its caller sets (1,800 s from both workflows and from
  `pollers/host/`), calls `archive_release.sh` and `status_release.sh`. A failed mid-run upload is only a warning. A lost
  runner therefore costs at most about 30 minutes plus the unflushed
  buffer.[^poll-with-uploads]
- A final workflow step with `if: always()` uploads everything once the
  poller has exited or timed out.
- `archive_release.sh` copies each `.gz` file and checks the copy with
  `gzip -t`, up to three times, so a flush caught half-written is retried
  instead of uploaded. Uploads use `--clobber` and replace the earlier copy.
  A zip already in the release is skipped. `ARCHIVE_DRY_RUN=1` checks and
  lists files without uploading.[^archive-release]
- `status_release.sh` replaces `<source>.json` in the fixed `status`
  release, which the project tracker reads (D28).[^status-release]

# Reading it back

```sh
gh release download archive-mata-2026-W39 --dir data/cache/mata/2026-W39
Rscript pipelines/mata/run.R --archive data/cache/mata/2026-W39
```

Duplicate reports from overlapping runs are removed in the pipelines.

# Interim

This is the interim store. Once object storage exists (H1, Cloudflare R2 or
S3), the upload step moves there.[^d7]

[^archive-release]: pollers/archive_release.sh
[^poll-with-uploads]: pollers/poll_with_uploads.sh
[^status-release]: pollers/status_release.sh
[^d7]: DECISIONS.md D7 (interim storage) and H1
