#!/usr/bin/env bash
# Zaratan site settings for FloodMaps build/publish.
# Copy to env.config.local.sh and edit paths, or export variables before running.
#
# Usage:
#   source scripts/Zaratan/env.config.example.sh
#   source scripts/Zaratan/env.config.local.sh   # optional overrides

# ---- FloodMaps repo on Zaratan (git clone) ----
export FLOODMAPS_ROOT="${FLOODMAPS_ROOT:-$HOME/FloodMaps}"

# ---- SIENA routine production RGB GeoTIFFs ----
export SIENA_OUTPUT_BASE="${SIENA_OUTPUT_BASE:-/scratch/zt1/project/henryqy-prj/shared/data/routine_production/SIENA_result}"

# ---- Python (direct path — no conda activate) ----
export CONDA_BASE="${CONDA_BASE:-/scratch/zt1/project/henryqy-prj/shared/env/miniconda3}"
export FLOODMAPS_PYTHON_ENV="${FLOODMAPS_PYTHON_ENV:-SIENA}"
export PYTHON_BIN="${PYTHON_BIN:-${CONDA_BASE}/envs/${FLOODMAPS_PYTHON_ENV}/bin/python}"
# Or use a repo venv after: python -m venv .venv && .venv/bin/pip install -r requirements.txt
# export PYTHON_BIN="${FLOODMAPS_ROOT}/.venv/bin/python"

# ---- Build ----
export WORKERS="${WORKERS:-8}"
export BASE_PATH="${BASE_PATH:-/FloodMaps/}"
export KEEP_DAYS="${KEEP_DAYS:-5}"

# ---- Slurm (compute node — tile bake) ----
export SLURM_PARTITION="${SLURM_PARTITION:-standard}"
export SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK:-8}"
export SLURM_MEM="${SLURM_MEM:-32G}"
export SLURM_TIMELIMIT="${SLURM_TIMELIMIT:-4:00:00}"
export SLURM_JOB_NAME="${SLURM_JOB_NAME:-floodmaps_build}"

# ---- Logs ----
export FLOODMAPS_LOG_DIR="${FLOODMAPS_LOG_DIR:-${FLOODMAPS_ROOT}/logs/zaratan}"

# ---- Publish (login node only — needs outbound git/github) ----
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-SIENA Flood Maps}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}"
