#!/usr/bin/env bash
# Build PNG tiles from geotiffs/ into docs/ (run on HPC compute nodes).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORKERS="${WORKERS:-4}"
BASE_PATH="${BASE_PATH:-/FloodMaps/}"

if ! compgen -G "geotiffs/*.tif" > /dev/null; then
  echo "No .tif files in geotiffs/ — add source granules before building." >&2
  exit 1
fi

echo "=== SIENA Flood Maps — build ==="
echo "Input:   geotiffs/*.tif"
echo "Output:  docs/              (deployed site root)"
echo "         data/catalog.json  (build metadata)"
echo "Workers: ${WORKERS}"
echo ""

python scripts/build_site.py --mode tiles --workers "$WORKERS" --base-path "$BASE_PATH"

CATALOG="${ROOT}/data/catalog.json"
GRANULES="$(python -c "import json; print(json.load(open('${CATALOG}'))['product_count'])")"
PNG_COUNT="$(find docs/tiles -name '*.png' | wc -l | tr -d ' ')"

echo ""
echo "Build complete."
echo "  Granules: ${GRANULES}"
echo "  PNG tiles: ${PNG_COUNT} in docs/tiles/"
echo "  Viewer:    docs/index.html, docs/js/, docs/css/"
echo ""
echo "On login node (after rsync docs/ if needed): ./scripts/publish.sh"
