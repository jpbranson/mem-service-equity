#!/usr/bin/env bash
# Upload poller output files to a weekly GitHub release (interim storage
# until object storage is configured -- DECISIONS.md D7/H1).
#
# Usage: archive_release.sh <source> <dir>
# Tag: archive-<source>-<ISO year>-W<ISO week>. Weekly releases keep each
# release well under GitHub's 1,000-asset limit. Set ARCHIVE_WEEK (e.g.
# 2026-W39) to pin the week, so every upload from one run lands in the same
# release even if the run crosses a week boundary.
#
# Safe to run while a poller is still writing (poll_with_uploads.sh does
# this every 30 minutes): each .gz file is copied and the copy is checked with
# gzip -t before upload, so a flush caught half-written is retried rather
# than uploaded. Re-uploads replace the earlier copy of the same file.
#
# Static GTFS zips are named by content hash and shared by overlapping runs,
# so a zip whose name is already in the release is skipped, not replaced.
#
# ARCHIVE_DRY_RUN=1 stages and checks files and prints what would be
# uploaded, without calling gh.
set -euo pipefail

source_name="$1"
dir="$2"
week="${ARCHIVE_WEEK:-$(date -u +%G-W%V)}"
dry_run="${ARCHIVE_DRY_RUN:-}"

# find, not globstar, so the script also runs under macOS's bash 3.2.
files=()
while IFS= read -r -d '' f; do files+=("$f"); done \
  < <(find "$dir" -type f \( -name '*.gz' -o -name '*.zip' \) -print0 2>/dev/null | sort -z)
if [ ${#files[@]} -eq 0 ]; then
  echo "No files to archive in $dir"
  exit 0
fi

tag="archive-${source_name}-${week}"
if [ -z "$dry_run" ] && ! gh release view "$tag" >/dev/null 2>&1; then
  gh release create "$tag" --prerelease \
    --title "Poller archive: ${source_name} ${week}" \
    --notes "Raw poller output for ${source_name}, ISO week ${week}. Files are gzip JSON lines; *_polls_* logs every poll attempt. See pollers/ and docs/research/mata-mlgw.md." \
    || gh release view "$tag" >/dev/null  # a concurrent run may have created it
fi

existing=""
if [ -z "$dry_run" ]; then
  existing="$(gh release view "$tag" --json assets -q '.assets[].name')"
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
upload=()
for f in "${files[@]}"; do
  name="$(basename "$f")"
  if [[ "$name" == *.zip ]]; then
    if grep -qxF "$name" <<<"$existing"; then continue; fi
    cp "$f" "$stage/$name"
    upload+=("$stage/$name")
    continue
  fi
  ok=""
  for attempt in 1 2 3; do
    cp "$f" "$stage/$name"
    if gzip -t "$stage/$name" 2>/dev/null; then ok=1; break; fi
    sleep 1
  done
  if [ -n "$ok" ]; then
    upload+=("$stage/$name")
  else
    echo "::warning::$name failed gzip -t three times; skipped this round"
  fi
done

if [ ${#upload[@]} -eq 0 ]; then
  echo "Nothing new to upload to $tag"
  exit 0
fi
if [ -n "$dry_run" ]; then
  printf 'would upload to %s: %s\n' "$tag" "$(basename -a "${upload[@]}" | tr '\n' ' ')"
  exit 0
fi
gh release upload "$tag" "${upload[@]}" --clobber
echo "Uploaded ${#upload[@]} files to $tag"
