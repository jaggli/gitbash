#!/usr/bin/env bash
# Release a new version: apply the pending changesets (their highest bump wins),
# commit, tag, push and publish to npm.
# Usage: npm run release
set -euo pipefail

cd "$(dirname "$0")/.."

pending=0
for file in .changeset/*.md; do
  [ -e "$file" ] || continue
  [ "$(basename "$file")" = "README.md" ] && continue
  pending=$((pending + 1))
done
if [ "$pending" -eq 0 ]; then
  echo "No pending changesets, nothing to release. Add one with: npm run changeset" >&2
  exit 1
fi

npm run version
version="$(node -p "require('./package.json').version")"
./bin/gitbash commit --yes -p "chore: release v$version"
git tag "v$version"
git push origin "v$version"
npm publish
