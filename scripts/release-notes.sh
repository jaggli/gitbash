#!/usr/bin/env bash
# Print the CHANGELOG.md section for a version (with or without leading "v").
# Usage: scripts/release-notes.sh <version> [changelog]
set -euo pipefail

version="${1:?usage: release-notes.sh <version> [changelog]}"
version="${version#v}"
changelog="${2:-CHANGELOG.md}"

notes="$(awk -v v="$version" '
  /^## / { if (found) exit; if ($2 == v) { found = 1; next } }
  found && (started || NF) { started = 1; print }
' "$changelog")"

if [ -z "$notes" ]; then
  echo "No changelog entry for $version in $changelog" >&2
  exit 1
fi
printf '%s\n' "$notes"
