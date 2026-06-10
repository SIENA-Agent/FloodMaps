#!/usr/bin/env bash
# PROJ/GDAL paths for rasterio from PYTHON_BIN (no conda activate).
# Source from Slurm build jobs after PYTHON_BIN is set.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: source scripts/Zaratan/runtime_env.sh" >&2
  exit 1
fi

: "${PYTHON_BIN:?PYTHON_BIN not set}"

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "ERROR: PYTHON_BIN not found: ${PYTHON_BIN}" >&2
  return 1 2>/dev/null || exit 1
fi

export PATH="$(dirname "${PYTHON_BIN}"):${PATH}"
unset CONDA_PREFIX PYTHONPATH PROJ_LIB PROJ_DATA GDAL_DATA LD_LIBRARY_PATH 2>/dev/null || true

if command -v module >/dev/null 2>&1; then
  module --force purge 2>/dev/null || true
fi

_env_root="$(cd "$(dirname "${PYTHON_BIN}")/.." && pwd)"
if [[ -d "${_env_root}/share/proj" ]]; then
  export PROJ_LIB="${_env_root}/share/proj"
  export PROJ_DATA="${_env_root}/share/proj"
fi
if [[ -d "${_env_root}/share/gdal" ]]; then
  export GDAL_DATA="${_env_root}/share/gdal"
fi
if [[ -d "${_env_root}/lib" ]]; then
  export LD_LIBRARY_PATH="${_env_root}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export RASTERIO_USE_PROJ_DATA="${RASTERIO_USE_PROJ_DATA:-YES}"
unset _env_root

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-${WORKERS:-4}}"
export MKL_NUM_THREADS="${OMP_NUM_THREADS}"
export OPENBLAS_NUM_THREADS="${OMP_NUM_THREADS}"
