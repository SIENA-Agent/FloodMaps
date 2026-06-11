#!/usr/bin/env bash
# Mac Globus settings — copy to env.config.local.sh and edit (not committed).
#
#   cp scripts/globus/env.config.example.sh scripts/globus/env.config.local.sh
#
# Endpoint UUIDs: bash scripts/globus/find_endpoints.sh
#   Source:  "University of Maryland Zaratan DTN" (scratch / SIENA_result)
#   Dest:    your Mac Globus Connect Personal endpoint

# ---- Mac repo ----
export FLOODMAPS_ROOT="${FLOODMAPS_ROOT:-$HOME/Downloads/Web_Geodata_Visualization}"
export MAC_GEOTIFF_DIR="${MAC_GEOTIFF_DIR:-${FLOODMAPS_ROOT}/geotiffs}"

# ---- HPC SIENA routine production (granule subfolders with *_RGB_*.tif) ----
export SIENA_OUTPUT_BASE="${SIENA_OUTPUT_BASE:-/scratch/zt1/project/zt-PROJECT/shared/data/routine_production/SIENA_result}"

# ---- Retention (same as scripts/Zaratan/sync_geotiffs.sh) ----
export KEEP_DAYS="${KEEP_DAYS:-30}"
export KEEP_DEMO_DATES="${KEEP_DEMO_DATES:-20251214 20251217 20251219}"

# ---- Globus collection UUIDs ----
export GLOBUS_SRC_ENDPOINT="${GLOBUS_SRC_ENDPOINT:-REPLACE_WITH_ZARATAN_DTN_UUID}"
export GLOBUS_DST_ENDPOINT="${GLOBUS_DST_ENDPOINT:-REPLACE_WITH_MAC_GCP_UUID}"

# ---- Logs ----
export GLOBUS_LOG_DIR="${GLOBUS_LOG_DIR:-${FLOODMAPS_ROOT}/logs/globus}"

# ---- Legacy: bulk transfer flat HPC geotiffs/ (optional) ----
# export HPC_GEOTIFF_PATH="${FLOODMAPS_ROOT}/geotiffs on HPC scratch path"
# export GLOBUS_SYNC_LEVEL="${GLOBUS_SYNC_LEVEL:-checksum}"
