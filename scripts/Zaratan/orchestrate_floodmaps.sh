#!/usr/bin/env bash
# Login-node orchestrator: sync SIENA RGB tifs → sbatch build → wait → publish.
#
# Usage:
#   bash scripts/Zaratan/orchestrate_floodmaps.sh
#   bash scripts/Zaratan/orchestrate_floodmaps.sh --sync-only
#   bash scripts/Zaratan/orchestrate_floodmaps.sh --no-publish
#   bash scripts/Zaratan/orchestrate_floodmaps.sh --build-only
#   bash scripts/Zaratan/orchestrate_floodmaps.sh --wait-publish   # block until push finishes
#
set -euo pipefail

ZARATAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOODMAPS_ROOT_EARLY="$(cd "${ZARATAN_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${FLOODMAPS_ROOT_EARLY}/scripts/load_github_credentials.sh"
# shellcheck disable=SC1091
source "${ZARATAN_DIR}/env.config.example.sh"
[[ -f "${ZARATAN_DIR}/env.config.local.sh" ]] && source "${ZARATAN_DIR}/env.config.local.sh"

SYNC_ONLY=0
BUILD_ONLY=0
NO_PUBLISH=0
WAIT_PUBLISH=0
POLL_SEC="${POLL_SEC:-60}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sync-only) SYNC_ONLY=1; shift ;;
    --build-only) BUILD_ONLY=1; shift ;;
    --no-publish) NO_PUBLISH=1; shift ;;
    --wait-publish) WAIT_PUBLISH=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

: "${FLOODMAPS_ROOT:?FLOODMAPS_ROOT not set}"
[[ -d "$FLOODMAPS_ROOT" ]] || { echo "ERROR: FLOODMAPS_ROOT not found: $FLOODMAPS_ROOT" >&2; exit 1; }
[[ -x "$PYTHON_BIN" ]] || { echo "ERROR: PYTHON_BIN not executable: $PYTHON_BIN" >&2; exit 1; }

mkdir -p "$FLOODMAPS_LOG_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${FLOODMAPS_LOG_DIR}/orchestrate_${STAMP}.log"

if [[ -t 1 ]]; then
  exec > >(tee -a "$LOG") 2>&1
else
  # nohup — write log only (do not also redirect nohup to the same file)
  exec >>"$LOG" 2>&1
fi

echo "=== FloodMaps orchestrator $(date -u) ==="
echo "host=$(hostname)"
echo "FLOODMAPS_ROOT=${FLOODMAPS_ROOT}"
echo "SIENA_OUTPUT_BASE=${SIENA_OUTPUT_BASE}"
echo "PYTHON_BIN=${PYTHON_BIN}"
echo "LOG=${LOG}"

cd "$FLOODMAPS_ROOT"

if [[ "$BUILD_ONLY" -eq 0 ]]; then
  echo ""
  bash "${ZARATAN_DIR}/sync_geotiffs.sh"
fi

if [[ "$SYNC_ONLY" -eq 1 ]]; then
  echo "Sync only — done."
  exit 0
fi

SLURM_SCRIPT="${ZARATAN_DIR}/slurm_build_floodmaps.template.sh"
[[ -f "$SLURM_SCRIPT" ]] || { echo "ERROR: missing $SLURM_SCRIPT" >&2; exit 1; }

EXPORT_VARS="FLOODMAPS_ROOT,PYTHON_BIN,WORKERS,BASE_PATH,SLURM_CPUS_PER_TASK"

echo ""
echo "Submitting Slurm build job…"
JOB_ID="$(
  sbatch --parsable \
    --job-name="${SLURM_JOB_NAME}" \
    --partition="${SLURM_PARTITION}" \
    --cpus-per-task="${SLURM_CPUS_PER_TASK}" \
    --mem="${SLURM_MEM}" \
    --time="${SLURM_TIMELIMIT}" \
    --chdir="${FLOODMAPS_ROOT}" \
    --export="${EXPORT_VARS}" \
    "$SLURM_SCRIPT"
)"
echo "Submitted job ${JOB_ID}  (partition=${SLURM_PARTITION}, cpus=${SLURM_CPUS_PER_TASK}, mem=${SLURM_MEM})"
echo "Monitor: squeue -j ${JOB_ID}   log: ${FLOODMAPS_ROOT}/floodmaps_build_${JOB_ID}.out"

echo ""
echo "Waiting for build job ${JOB_ID}…"
while squeue -j "$JOB_ID" -h 2>/dev/null | grep -q .; do
  echo "  …still running ($(date -u +%H:%M:%S))"
  sleep "$POLL_SEC"
done

# Slurm exit code (may take a moment after job leaves queue)
sleep 5
EXIT_LINE="$(sacct -j "$JOB_ID" -n -X -o State,ExitCode 2>/dev/null | head -1 || true)"
echo "Job finished: ${EXIT_LINE:-unknown}"

EXIT_CODE="$(echo "$EXIT_LINE" | awk '{print $2}' | cut -d: -f1)"
if [[ -z "$EXIT_CODE" || "$EXIT_CODE" != "0" ]]; then
  echo "ERROR: build job failed. See floodmaps_build_${JOB_ID}.out" >&2
  exit 1
fi

if [[ ! -f "${FLOODMAPS_ROOT}/docs/index.html" ]] || [[ ! -d "${FLOODMAPS_ROOT}/docs/tiles" ]]; then
  echo "ERROR: docs/ missing after build." >&2
  exit 1
fi

if [[ "$NO_PUBLISH" -eq 1 ]]; then
  echo "Build OK — skipping publish (--no-publish)."
  exit 0
fi

echo ""
if [[ "$WAIT_PUBLISH" -eq 1 ]]; then
  echo "Running publish on login node (foreground — use --wait-publish only when SSH is stable)…"
  bash "${FLOODMAPS_ROOT}/scripts/publish.sh"
else
  echo "Starting publish in background (SSH-safe)…"
  bash "${ZARATAN_DIR}/publish_background.sh"
fi

echo ""
echo "=== Orchestrator complete $(date -u) ==="
