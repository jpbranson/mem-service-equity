#!/usr/bin/env bash
# Run a poller and archive its output every <interval> seconds while it runs.
# The files live only on the runner until they are uploaded, so without this a
# lost runner would lose the whole run (170 minutes); with it, at most one
# interval. The workflow's final archive step (if: always()) still uploads
# everything once the poller has exited or timed out.
#
# Usage: poll_with_uploads.sh <source> <dir> <interval_s> <poller command...>
# Exits with the poller's exit code. A failed mid-run upload is a warning,
# not an error; the next round or the final step uploads the same files.
set -uo pipefail

source_name="$1"
dir="$2"
interval="$3"
shift 3
here="$(cd "$(dirname "$0")" && pwd)"

"$@" &
poller=$!
trap 'kill "$poller" 2>/dev/null' TERM INT

last=$(date +%s)
while kill -0 "$poller" 2>/dev/null; do
  sleep 10
  if (( $(date +%s) - last >= interval )) && kill -0 "$poller" 2>/dev/null; then
    bash "$here/archive_release.sh" "$source_name" "$dir" \
      || echo "::warning::mid-run upload of $source_name failed; the next round will retry"
    last=$(date +%s)
  fi
done
wait "$poller"
