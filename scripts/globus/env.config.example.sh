#!/usr/bin/env bash
# Mac Globus transfer settings for FloodMaps geotiffs (HPC → Mac).
#
#   cp scripts/globus/env.config.example.sh scripts/globus/env.config.local.sh
#   vim scripts/globus/env.config.local.sh
#
# Usage:
#   source scripts/globus/env.config.local.sh
#   bash scripts/globus/transfer_geotiffs.sh

# ---- Mac FloodMaps repo (destination) ----
export FLOODMAPS_ROOT="${FLOODMAPS_ROOT:-/Users/qyang/Downloads/Web_Geodata_Visualization}"
export MAC_GEOTIFF_DIR="${MAC_GEOTIFF_DIR:-${FLOODMAPS_ROOT}/geotiffs}"

# ---- HPC source (Zaratan scratch — after sync_geotiffs.sh on login node) ----
export HPC_GEOTIFF_PATH="${HPC_GEOTIFF_PATH:-/scratch/zt1/project/henryqy-prj/shared/code/gateway/FloodMaps/geotiffs}"

# Alternative source: SIENA routine production (very large — prefer HPC geotiffs/ above)
# export HPC_GEOTIFF_PATH="/scratch/zt1/project/henryqy-prj/shared/data/routine_production/SIENA_result"

# ---- Globus collection UUIDs (find with: bash scripts/globus/find_endpoints.sh) ----
# Source: UMD Zaratan / scratch collection (read access to your project path)
export GLOBUS_SRC_ENDPOINT="${GLOBUS_SRC_ENDPOINT:-REPLACE_WITH_ZARATAN_COLLECTION_UUID}"

# Destination: your Mac Globus Connect Personal endpoint
export GLOBUS_DST_ENDPOINT="${GLOBUS_DST_ENDPOINT:-REPLACE_WITH_MAC_GCP_ENDPOINT_UUID}"

# ---- Transfer behaviour ----
# sync_level: checksum | size | mtime | mtime_size | none
#   checksum — safest; re-transfer only changed files (good for updates)
#   size     — faster; skip files with same size
export GLOBUS_SYNC_LEVEL="${GLOBUS_SYNC_LEVEL:-checksum}"
export GLOBUS_LABEL_PREFIX="${GLOBUS_LABEL_PREFIX:-FloodMaps-geotiffs}"

# ---- Logs ----
export GLOBUS_LOG_DIR="${GLOBUS_LOG_DIR:-${FLOODMAPS_ROOT}/logs/globus}"
