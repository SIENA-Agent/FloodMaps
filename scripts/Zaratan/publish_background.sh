#!/usr/bin/env bash
# Run publish.sh in the background (SSH-safe on login nodes).
#
# Usage:
#   bash scripts/Zaratan/publish_background.sh
#   tail -f logs/zaratan/publish_*.log
#
set -euo pipefail

ZARATAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOODMAPS_ROOT_EARLY="$(cd "${ZARATAN_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${ZARATAN_DIR}/env.config.example.sh"
[[ -f "${ZARATAN_DIR}/env.config.local.sh" ]] && source "${ZARATAN_DIR}/env.config.local.sh"

: "${FLOODMAPS_ROOT:?FLOODMAPS_ROOT not set}"

mkdir -p "$FLOODMAPS_LOG_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${FLOODMAPS_LOG_DIR}/publish_${STAMP}.log"
PIDFILE="${FLOODMAPS_LOG_DIR}/publish.pid"

if [[ -f "$PIDFILE" ]]; then
  OLD_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Publish already running (pid ${OLD_PID})."
    echo "  tail -f ${FLOODMAPS_LOG_DIR}/publish_*.log"
    exit 1
  fi
fi

echo "=== FloodMaps background publish $(date -u) ===" >>"$LOG"
echo "host=$(hostname)" >>"$LOG"
echo "FLOODMAPS_ROOT=${FLOODMAPS_ROOT}" >>"$LOG"
echo "LOG=${LOG}" >>"$LOG"
echo "" >>"$LOG"

FLOODMAPS_PUBLISH_PIDFILE="$PIDFILE" \
  nohup bash "${FLOODMAPS_ROOT}/scripts/publish.sh" >>"$LOG" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" >"$PIDFILE"

echo "Publish started in background."
echo "  pid=${NEW_PID}"
echo "  log=${LOG}"
echo ""
echo "Monitor:"
echo "  tail -f ${LOG}"
echo "  ps -p ${NEW_PID}"
