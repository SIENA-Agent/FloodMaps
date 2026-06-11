#!/usr/bin/env bash
# Mac pipeline: Globus ZIP sync → build → publish (background by default).
#
#   bash scripts/mac/orchestrate_build_publish.sh
#   /path/to/FloodMaps/scripts/mac/orchestrate_build_publish.sh
#
# Config (local only, not in git):
#   scripts/globus/env.config.local.sh   — paths + Globus UUIDs
#   scripts/mac/env.config.local.sh      — optional overrides
#
# Monitor:
#   tail -f logs/mac/pipeline_*.log
#
set -euo pipefail

MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${MAC_DIR}/../.." && pwd)"

FOREGROUND=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --foreground|-f) FOREGROUND=1; shift ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

load_config() {
  # shellcheck disable=SC1091
  source "${ROOT}/scripts/globus/env.config.example.sh"
  [[ -f "${ROOT}/scripts/globus/env.config.local.sh" ]] && \
    source "${ROOT}/scripts/globus/env.config.local.sh"
  # shellcheck disable=SC1091
  [[ -f "${MAC_DIR}/env.config.example.sh" ]] && source "${MAC_DIR}/env.config.example.sh"
  [[ -f "${MAC_DIR}/env.config.local.sh" ]] && source "${MAC_DIR}/env.config.local.sh"
  export FLOODMAPS_ROOT="${FLOODMAPS_ROOT:-$ROOT}"
  export MAC_LOG_DIR="${MAC_LOG_DIR:-${FLOODMAPS_ROOT}/logs/mac}"
}

load_config

LOG_DIR="${MAC_LOG_DIR}"
mkdir -p "$LOG_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${LOG_DIR}/pipeline_${STAMP}.log"
PIDFILE="${LOG_DIR}/pipeline.pid"

if [[ "${FLOODMAPS_MAC_PIPELINE_BG:-}" != 1 && "$FOREGROUND" -eq 0 ]]; then
  if [[ -f "$PIDFILE" ]]; then
    OLD_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "Mac pipeline already running (pid ${OLD_PID})."
      echo "  tail -f ${LOG_DIR}/pipeline_*.log"
      exit 1
    fi
  fi

  echo "=== FloodMaps Mac pipeline $(date -u) ===" >>"$LOG"
  echo "host=$(hostname)" >>"$LOG"
  echo "FLOODMAPS_ROOT=${FLOODMAPS_ROOT}" >>"$LOG"
  echo "LOG=${LOG}" >>"$LOG"
  echo "" >>"$LOG"

  FLOODMAPS_MAC_PIPELINE_BG=1 nohup bash "$0" --foreground >>"$LOG" 2>&1 &
  NEW_PID=$!
  echo "$NEW_PID" >"$PIDFILE"

  echo "Mac pipeline started in background."
  echo "  pid=${NEW_PID}"
  echo "  log=${LOG}"
  echo ""
  echo "Monitor:"
  echo "  tail -f ${LOG}"
  echo "  ps -p ${NEW_PID}"
  exit 0
fi

cleanup() {
  rm -f "${PIDFILE:-}"
}
trap cleanup EXIT

cd "$FLOODMAPS_ROOT"

echo "=== FloodMaps Mac pipeline worker $(date -u) ==="
echo "FLOODMAPS_ROOT=${FLOODMAPS_ROOT}"
echo "WORKERS=${WORKERS:-4}"
echo ""

echo "--- Step 1/3: Globus ZIP sync ---"
bash "${ROOT}/scripts/globus/sync_geotiffs_from_zip.sh"

echo ""
echo "--- Step 2/3: Build tiles ---"
bash "${ROOT}/scripts/build.sh"

echo ""
echo "--- Step 3/3: Publish ---"
bash "${ROOT}/scripts/publish.sh"

echo ""
echo "=== Mac pipeline complete $(date -u) ==="
