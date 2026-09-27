#!/usr/bin/env bash
# Publish a poller's status file (common.StatusFile) as an asset of the
# fixed-tag prerelease "status", replacing the previous copy, so the project
# tracker has a stable URL to read (DECISIONS.md D28):
#   https://github.com/jpbranson/mem-service-equity/releases/download/status/<source>.json
# Overlapping runs replace each other's copy; both are current.
#
# Usage: status_release.sh <file>. A missing file (no poll yet) is not an error.
# ARCHIVE_DRY_RUN=1 prints what would be uploaded, without calling gh.
set -euo pipefail

file="$1"
name="$(basename "$file")"
if [ ! -s "$file" ]; then
  echo "No status file at $file"
  exit 0
fi
if [ -n "${ARCHIVE_DRY_RUN:-}" ]; then
  echo "would upload $name to the status release"
  exit 0
fi

if ! gh release view status >/dev/null 2>&1; then
  gh release create status --prerelease --title "Poller status" \
    --notes "Current status of the MATA and MLGW pollers, read by the project tracker. mata.json and mlgw.json are replaced by every upload; see DECISIONS.md D28." \
    || gh release view status >/dev/null  # a concurrent run may have created it
fi

# Upload a copy: the poller replaces the file after every poll.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp "$file" "$stage/$name"
gh release upload status "$stage/$name" --clobber
echo "Published $name to the status release"
