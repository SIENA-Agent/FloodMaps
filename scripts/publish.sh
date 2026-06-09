#!/usr/bin/env bash
# Deploy pre-built docs/ to gh-pages (run on HPC login node — no tile bake).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git remote get-url origin &>/dev/null; then
  echo "No git remote 'origin' — add: git remote add origin <url>" >&2
  exit 1
fi

if [[ ! -f docs/index.html ]] || [[ ! -d docs/tiles ]]; then
  echo "docs/ is not built — run ./scripts/build.sh first." >&2
  exit 1
fi

PNG_COUNT="$(find docs/tiles -name '*.png' | wc -l | tr -d ' ')"
if [[ "$PNG_COUNT" -eq 0 ]]; then
  echo "docs/tiles/ has no PNG files — run ./scripts/build.sh first." >&2
  exit 1
fi

CATALOG="${ROOT}/data/catalog.json"
if [[ ! -f "$CATALOG" ]]; then
  CATALOG="${ROOT}/docs/data/catalog.json"
fi
if [[ ! -f "$CATALOG" ]]; then
  echo "catalog.json missing — run ./scripts/build.sh first." >&2
  exit 1
fi

REMOTE="$(git remote get-url origin)"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GRANULES="$(python -c "import json; print(json.load(open('${CATALOG}'))['product_count'])")"

echo "=== SIENA Flood Maps — publish ==="
echo "Deploying docs/ (${GRANULES} granules, ${PNG_COUNT} PNGs) to gh-pages…"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -a docs/. "$WORK/"
cd "$WORK"
git init -q
git checkout -b gh-pages
git add -A
git commit -m "Deploy ${STAMP} — ${GRANULES} granules (${PNG_COUNT} PNGs)"

git push -f "$REMOTE" HEAD:gh-pages

echo ""
echo "Done. Site: https://siena-agent.github.io/FloodMaps/"
echo "main branch unchanged — only scripts live in git history."
