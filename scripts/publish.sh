#!/usr/bin/env bash
# Model C: build locally, deploy docs/ to gh-pages (force-push, no tile history on main).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! compgen -G "geotiffs/*.tif" > /dev/null; then
  echo "No .tif files in geotiffs/ — add source granules before publishing." >&2
  exit 1
fi

if ! git remote get-url origin &>/dev/null; then
  echo "No git remote 'origin' — add: git remote add origin <url>" >&2
  exit 1
fi

REMOTE="$(git remote get-url origin)"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "Building site from local geotiffs/…"
python scripts/build_site.py --mode tiles --workers 4 --base-path /FloodMaps/

GRANULES="$(python -c "import json; print(json.load(open('data/catalog.json'))['product_count'])")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -a docs/. "$WORK/"
cd "$WORK"
git init -q
git checkout -b gh-pages
git add -A
git commit -m "Deploy ${STAMP} — ${GRANULES} granules"

echo "Deploying to origin/gh-pages (force-push, replaces prior site)…"
git push -f "$REMOTE" HEAD:gh-pages

echo "Done. Site: https://siena-agent.github.io/FloodMaps/"
echo "main branch unchanged — only scripts live in git history."
