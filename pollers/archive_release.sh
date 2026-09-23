#!/usr/bin/env bash
# Upload poller output files to a weekly GitHub release (interim storage
# until object storage is configured -- DECISIONS.md D7/H1).
#
# Usage: archive_release.sh <source> <dir>
# Tag: archive-<source>-<ISO year>-W<ISO week>. Weekly releases keep each
# release well under GitHub's 1,000-asset limit.
set -euo pipefail

source_name="$1"
dir="$2"

shopt -s nullglob globstar
files=("$dir"/**/*.gz "$dir"/**/*.zip)
if [ ${#files[@]} -eq 0 ]; then
  echo "No files to archive in $dir"
  exit 0
fi

tag="archive-${source_name}-$(date -u +%G-W%V)"
if ! gh release view "$tag" >/dev/null 2>&1; then
  gh release create "$tag" --prerelease \
    --title "Poller archive: ${source_name} $(date -u +%G-W%V)" \
    --notes "Raw poller output for ${source_name}, ISO week $(date -u +%G-W%V). Files are gzip JSON lines; *_polls_* logs every poll attempt. See pollers/ and docs/research/mata-mlgw.md." \
    || gh release view "$tag" >/dev/null  # a concurrent run may have created it
fi
gh release upload "$tag" "${files[@]}" --clobber
echo "Uploaded ${#files[@]} files to $tag"
