#!/usr/bin/env bash
# Regenerates the dynamic lines in HANDOFF.md.
set -e

REPO="/home/dad/dev/KidulWM"
cd "$REPO"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD="$(git rev-parse --short HEAD)"

sed -i "s/| Branch | .* |/| Branch | \`$BRANCH\` |/" "$REPO/HANDOFF.md"
sed -i "s/| Head | .* |/| Head | \`$HEAD\` |/" "$REPO/HANDOFF.md"

echo "Updated HANDOFF.md: branch=$BRANCH head=$HEAD"
