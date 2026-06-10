#!/usr/bin/env bash
# Copy new SIENA *_RGB_*.tif products into FLOODMAPS_ROOT/geotiffs/ and prune old dates.
set -euo pipefail

ZARATAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${ZARATAN_DIR}/env.config.example.sh"
[[ -f "${ZARATAN_DIR}/env.config.local.sh" ]] && source "${ZARATAN_DIR}/env.config.local.sh"

: "${FLOODMAPS_ROOT:?FLOODMAPS_ROOT not set}"
: "${SIENA_OUTPUT_BASE:?SIENA_OUTPUT_BASE not set}"

GEOTIFF_DIR="${FLOODMAPS_ROOT}/geotiffs"
mkdir -p "$GEOTIFF_DIR"

if [[ ! -d "$SIENA_OUTPUT_BASE" ]]; then
  echo "ERROR: SIENA output not found: $SIENA_OUTPUT_BASE" >&2
  exit 1
fi

is_demo_date() {
  local sdate="$1"
  local d
  for d in ${KEEP_DEMO_DATES}; do
    [[ "$sdate" == "$d" ]] && return 0
  done
  return 1
}

echo "=== sync geotiffs ==="
echo "Source:  ${SIENA_OUTPUT_BASE}  (*_RGB_*.tif)"
echo "Target:  ${GEOTIFF_DIR}"
echo "Keep:    ${KEEP_DAYS} day(s) of sensing dates"
echo "Demo:    always keep ${KEEP_DEMO_DATES}"
echo ""

NEW=0
SKIPPED=0

while IFS= read -r -d '' src; do
  base="$(basename "$src")"
  dest="${GEOTIFF_DIR}/${base}"
  if [[ -f "$dest" ]] && [[ ! "$src" -nt "$dest" ]]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  cp -f "$src" "$dest"
  NEW=$((NEW + 1))
  echo "  + ${base}"
done < <(find "$SIENA_OUTPUT_BASE" -type f -name '*_RGB_*.tif' -print0 2>/dev/null)

echo ""
echo "Copied ${NEW} new/updated file(s), skipped ${SKIPPED} unchanged."

# Prune geotiffs older than KEEP_DAYS (sensing date = first YYYYMMDD in filename)
if [[ "${KEEP_DAYS}" -gt 0 ]]; then
  CUTOFF="$(date -u -d "${KEEP_DAYS} days ago" +%Y%m%d 2>/dev/null || date -u -v-"${KEEP_DAYS}"d +%Y%m%d)"
  PRUNED=0
  KEPT_DEMO=0
  for tif in "$GEOTIFF_DIR"/*.tif; do
    [[ -f "$tif" ]] || continue
    name="$(basename "$tif")"
    if [[ "$name" =~ ([0-9]{8})T[0-9]{6} ]]; then
      sdate="${BASH_REMATCH[1]}"
      if is_demo_date "$sdate"; then
        KEPT_DEMO=$((KEPT_DEMO + 1))
        continue
      fi
      if [[ "$sdate" < "$CUTOFF" ]]; then
        rm -f "$tif"
        PRUNED=$((PRUNED + 1))
        echo "  - pruned ${name} (date ${sdate} < ${CUTOFF})"
      fi
    fi
  done
  echo "Pruned ${PRUNED} file(s) older than ${KEEP_DAYS} days (${KEPT_DEMO} demo date file(s) protected)."
fi

TOTAL="$(find "$GEOTIFF_DIR" -maxdepth 1 -name '*.tif' | wc -l | tr -d ' ')"
echo "geotiffs/ total: ${TOTAL} .tif file(s)"

if [[ "$TOTAL" -eq 0 ]]; then
  echo "WARNING: no GeoTIFFs in geotiffs/ after sync." >&2
  exit 1
fi
