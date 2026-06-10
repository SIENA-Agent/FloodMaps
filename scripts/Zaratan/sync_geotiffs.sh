#!/usr/bin/env bash
# Copy SIENA *_RGB_*.tif from date-scoped granule folders into geotiffs/, then prune.
# Sensing date comes from granule folder/filename (Sentinel-1 time), never mtime.
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

# First YYYYMMDD from Sentinel-1 datetime token in folder or filename.
sensing_date_from_name() {
  local name="$1"
  if [[ "$name" =~ (20[0-9]{6})T[0-9]{6} ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

is_demo_date() {
  local sdate="$1"
  local d
  for d in ${KEEP_DEMO_DATES}; do
    [[ "$sdate" == "$d" ]] && return 0
  done
  return 1
}

should_keep_sensing_date() {
  local sdate="$1"
  is_demo_date "$sdate" && return 0
  [[ "$sdate" ge "$CUTOFF" ]]
}

CUTOFF="$(date -u -d "${KEEP_DAYS} days ago" +%Y%m%d 2>/dev/null || date -u -v-"${KEEP_DAYS}"d +%Y%m%d)"

echo "=== sync geotiffs ==="
echo "Source:  ${SIENA_OUTPUT_BASE}/<granule_folder>/*_RGB_*.tif"
echo "Target:  ${GEOTIFF_DIR}"
echo "Window:  sensing date >= ${CUTOFF} (last ${KEEP_DAYS} days)"
echo "Demo:    always sync/keep ${KEEP_DEMO_DATES}"
echo ""

NEW=0
SKIPPED=0
FOLDERS_SCANNED=0
FOLDERS_SYNCED=0
FOLDERS_SKIPPED=0

for granule_dir in "$SIENA_OUTPUT_BASE"/*; do
  [[ -d "$granule_dir" ]] || continue
  folder="$(basename "$granule_dir")"
  [[ "$folder" == .* ]] && continue
  FOLDERS_SCANNED=$((FOLDERS_SCANNED + 1))

  sdate="$(sensing_date_from_name "$folder" || true)"
  if [[ -z "$sdate" ]]; then
    FOLDERS_SKIPPED=$((FOLDERS_SKIPPED + 1))
    continue
  fi

  if ! should_keep_sensing_date "$sdate"; then
    FOLDERS_SKIPPED=$((FOLDERS_SKIPPED + 1))
    continue
  fi

  FOLDERS_SYNCED=$((FOLDERS_SYNCED + 1))
  shopt -s nullglob
  rgb_files=("$granule_dir"/*_RGB_*.tif)
  shopt -u nullglob
  [[ ${#rgb_files[@]} -gt 0 ]] || continue

  for src in "${rgb_files[@]}"; do
    base="$(basename "$src")"
    dest="${GEOTIFF_DIR}/${base}"
    # Confirm filename sensing date matches folder (fallback if names differ)
    file_date="$(sensing_date_from_name "$base" || true)"
    if [[ -n "$file_date" ]] && ! should_keep_sensing_date "$file_date"; then
      continue
    fi
    if [[ -f "$dest" ]] && [[ "$(stat -c '%s' "$src" 2>/dev/null || stat -f '%z' "$src")" == "$(stat -c '%s' "$dest" 2>/dev/null || stat -f '%z' "$dest")" ]]; then
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    cp -f "$src" "$dest"
    NEW=$((NEW + 1))
    echo "  + ${base}"
  done
done

echo ""
echo "Folders: scanned ${FOLDERS_SCANNED}, synced ${FOLDERS_SYNCED}, skipped ${FOLDERS_SKIPPED} (outside window)."
echo "Copied ${NEW} new/updated file(s), skipped ${SKIPPED} unchanged (same size)."

# Prune flat geotiffs/ by sensing date in filename (not mtime)
PRUNED=0
KEPT_DEMO=0
for tif in "$GEOTIFF_DIR"/*.tif; do
  [[ -f "$tif" ]] || continue
  name="$(basename "$tif")"
  sdate="$(sensing_date_from_name "$name" || true)"
  [[ -n "$sdate" ]] || continue
  if is_demo_date "$sdate"; then
    KEPT_DEMO=$((KEPT_DEMO + 1))
    continue
  fi
  if [[ "$sdate" < "$CUTOFF" ]]; then
    rm -f "$tif"
    PRUNED=$((PRUNED + 1))
    echo "  - pruned ${name} (sensing ${sdate} < ${CUTOFF})"
  fi
done
echo "Pruned ${PRUNED} file(s) with sensing date before ${CUTOFF} (${KEPT_DEMO} demo file(s) protected)."

TOTAL="$(find "$GEOTIFF_DIR" -maxdepth 1 -name '*.tif' | wc -l | tr -d ' ')"
echo "geotiffs/ total: ${TOTAL} .tif file(s)"

if [[ "$TOTAL" -eq 0 ]]; then
  echo "WARNING: no GeoTIFFs in geotiffs/ after sync." >&2
  exit 1
fi
