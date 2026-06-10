#!/usr/bin/env bash
# Slurm compute job: bake PNG tiles (scripts/build.sh).
# Submitted from login node by orchestrate_floodmaps.sh.
#
#SBATCH --job-name=floodmaps_build
#SBATCH --output=floodmaps_build_%j.out

set -euo pipefail

echo "======================================"
echo "FloodMaps build  Job=${SLURM_JOB_ID:-local}  Host=$(hostname)"
echo "Start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "======================================"

: "${FLOODMAPS_ROOT:?FLOODMAPS_ROOT not exported to job}"
: "${PYTHON_BIN:?PYTHON_BIN not exported to job}"

cd "$FLOODMAPS_ROOT"

ZARATAN_DIR="${FLOODMAPS_ROOT}/scripts/Zaratan"
# shellcheck disable=SC1091
source "${ZARATAN_DIR}/runtime_env.sh"

echo "PYTHON_BIN=${PYTHON_BIN}"
echo "PROJ_DATA=${PROJ_DATA:-unset}"
echo "WORKERS=${WORKERS:-4}"
echo ""

"${PYTHON_BIN}" -c "import rasterio, mercantile, PIL; print('Python deps OK')" || {
  echo "ERROR: missing Python packages. On login node run:" >&2
  echo "  ${PYTHON_BIN} -m pip install -r ${FLOODMAPS_ROOT}/requirements.txt" >&2
  exit 1
}

export WORKERS="${WORKERS:-8}"
export BASE_PATH="${BASE_PATH:-/FloodMaps/}"

bash "${FLOODMAPS_ROOT}/scripts/build.sh"

echo ""
echo "Build finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "docs/ ready for publish on login node."
