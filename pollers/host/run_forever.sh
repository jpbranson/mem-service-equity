#!/usr/bin/env bash
# Run one poller continuously on an always-on host (DECISIONS.md H22), in
# back-to-back runs of RUN_MINUTES, so the gaps are seconds between runs
# rather than the hours GitHub's dropped schedules leave. Each run uploads
# through the same scripts as the workflows: archive and status every 30
# minutes while polling (poll_with_uploads.sh), then everything at the end.
#
# archive_release.sh uploads every file under the directory it is given, so
# each run polls into its own directory and moves to done/ once its final
# upload succeeds. A run whose upload failed stays in runs/ and is retried
# before the next run starts, into the week it was pinned to.
#
# Usage: run_forever.sh <mata|mlgw>
# Environment: GH_TOKEN and GH_REPO (required, for gh); MSE_DATA (default
# /var/lib/mse-pollers); RUN_MINUTES (default 120); KEEP_DAYS, how long
# uploaded runs are kept locally (default 30); PYTHON (default python3).
set -uo pipefail

source_name="${1:-}"
case "$source_name" in
  mata|mlgw) ;;
  *) echo "usage: $0 mata|mlgw" >&2; exit 2 ;;
esac
: "${GH_TOKEN:?GH_TOKEN is not set}" "${GH_REPO:?GH_REPO is not set}"
here="$(cd "$(dirname "$0")/.." && pwd)"
data="${MSE_DATA:-/var/lib/mse-pollers}/$source_name"
minutes="${RUN_MINUTES:-120}"
keep="${KEEP_DAYS:-30}"
python="${PYTHON:-python3}"
mkdir -p "$data/runs" "$data/done"

# Final upload of a finished run, into the week the run was pinned to.
finish() {
  local run="$1"
  ARCHIVE_WEEK="$(cat "$run/week")" bash "$here/archive_release.sh" "$source_name" "$run/$source_name" \
    && mv "$run" "$data/done/"
}

while true; do
  for old in "$data"/runs/*/; do
    [ -d "$old" ] || continue
    finish "${old%/}" || echo "warning: upload of ${old%/} failed; retrying before the next run"
  done
  find "$data/done" -mindepth 1 -maxdepth 1 -type d -mtime +"$keep" -exec rm -rf {} +

  run="$data/runs/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$run"
  ARCHIVE_WEEK="$(date -u +%G-W%V)"
  export ARCHIVE_WEEK
  echo "$ARCHIVE_WEEK" > "$run/week"
  bash "$here/poll_with_uploads.sh" "$source_name" "$run/$source_name" 1800 \
    "$python" "$here/${source_name}_poller.py" --minutes "$minutes" --out "$run"
  bash "$here/status_release.sh" "$run/status/$source_name.json" \
    || echo "warning: status upload of $source_name failed"
  finish "$run" || echo "warning: upload of $run failed; retrying before the next run"
done
