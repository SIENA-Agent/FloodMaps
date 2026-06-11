#!/usr/bin/env bash
# Transfer geotiffs/*.tif from Zaratan HPC to Mac via Globus CLI.
#
# Prerequisite on HPC (login node):
#   bash scripts/Zaratan/sync_geotiffs.sh
#
# On Mac:
#   globus login
#   # Globus Connect Personal running, writable path includes FLOODMAPS_ROOT
#   cp scripts/globus/env.config.example.sh scripts/globus/env.config.local.sh
#   # edit GLOBUS_SRC_ENDPOINT / GLOBUS_DST_ENDPOINT
#   bash scripts/globus/transfer_geotiffs.sh
#
# Options:
#   --dry-run    Print transfer command only
#   --verify     globus task wait after submit
#
set -euo pipefail

GLOBUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${GLOBUS_DIR}/env.config.example.sh"
[[ -f "${GLOBUS_DIR}/env.config.local.sh" ]] && source "${GLOBUS_DIR}/env.config.local.sh"

DRY_RUN=0
VERIFY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --verify) VERIFY=1; shift ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

require_var() {
  local name="$1" val="$2"
  if [[ -z "$val" || "$val" == REPLACE_WITH_* ]]; then
    echo "ERROR: set ${name} in scripts/globus/env.config.local.sh" >&2
    echo "  Run: bash scripts/globus/find_endpoints.sh" >&2
    exit 1
  fi
}

if ! command -v globus >/dev/null 2>&1; then
  echo "ERROR: globus CLI not found." >&2
  echo "  brew install globus-cli" >&2
  echo "  or: pip install 'globus-cli'" >&2
  exit 1
fi

if ! globus whoami >/dev/null 2>&1; then
  echo "ERROR: not logged in — run: globus login" >&2
  exit 1
fi

require_var GLOBUS_SRC_ENDPOINT "$GLOBUS_SRC_ENDPOINT"
require_var GLOBUS_DST_ENDPOINT "$GLOBUS_DST_ENDPOINT"
require_var HPC_GEOTIFF_PATH "$HPC_GEOTIFF_PATH"

mkdir -p "$MAC_GEOTIFF_DIR" "$GLOBUS_LOG_DIR"

SRC="${GLOBUS_SRC_ENDPOINT}:${HPC_GEOTIFF_PATH}/"
DST="${GLOBUS_DST_ENDPOINT}:${MAC_GEOTIFF_DIR}/"
LABEL="${GLOBUS_LABEL_PREFIX}-$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${GLOBUS_LOG_DIR}/transfer_${LABEL}.log"

echo "=== FloodMaps Globus transfer ===" | tee "$LOG"
echo "time:     $(date -u)" | tee -a "$LOG"
echo "source:   $SRC" | tee -a "$LOG"
echo "dest:     $DST" | tee -a "$LOG"
echo "sync:     ${GLOBUS_SYNC_LEVEL}" | tee -a "$LOG"
echo "log:      $LOG" | tee -a "$LOG"
echo "" | tee -a "$LOG"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN — would run:"
  echo "  globus transfer --recursive --sync-level ${GLOBUS_SYNC_LEVEL} \\"
  echo "    --label ${LABEL} \\"
  echo "    \"${SRC}\" \"${DST}\""
  exit 0
fi

# Ensure Mac GCP is reachable (best-effort)
if globus endpoint show "$GLOBUS_DST_ENDPOINT" --format json 2>/dev/null | grep -q '"activated": true'; then
  echo "Destination endpoint activated." | tee -a "$LOG"
else
  echo "NOTE: start Globus Connect Personal on this Mac if transfer fails." | tee -a "$LOG"
  echo "  https://docs.globus.org/globus-connect-personal/" | tee -a "$LOG"
fi

echo "Submitting transfer…" | tee -a "$LOG"
TRANSFER_OUT="$(
  globus transfer \
    --recursive \
    --sync-level "${GLOBUS_SYNC_LEVEL}" \
    --label "$LABEL" \
    --notify on \
    "$SRC" "$DST" 2>&1 | tee -a "$LOG"
)"
TASK_ID="$(printf '%s\n' "$TRANSFER_OUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | tail -1)"
if [[ -z "$TASK_ID" ]]; then
  echo "ERROR: could not parse task id from globus output — see $LOG" >&2
  exit 1
fi

echo "Task ID: $TASK_ID" | tee -a "$LOG"
echo "Monitor: globus task show $TASK_ID" | tee -a "$LOG"
echo "         globus task wait $TASK_ID" | tee -a "$LOG"
echo "         https://app.globus.org/activity" | tee -a "$LOG"

if [[ "$VERIFY" -eq 1 ]]; then
  echo "" | tee -a "$LOG"
  echo "Waiting for transfer to complete…" | tee -a "$LOG"
  globus task wait "$TASK_ID" 2>&1 | tee -a "$LOG"
  echo "" | tee -a "$LOG"
  TIF_COUNT="$(find "$MAC_GEOTIFF_DIR" -maxdepth 1 -name '*.tif' 2>/dev/null | wc -l | tr -d ' ')"
  echo "Mac geotiffs/: ${TIF_COUNT} .tif file(s)" | tee -a "$LOG"
  echo "Next: cd ${FLOODMAPS_ROOT} && ./scripts/build.sh && ./scripts/publish.sh" | tee -a "$LOG"
fi
