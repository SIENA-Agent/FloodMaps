#!/usr/bin/env bash
# Sync SIENA *_RGB_*.tif (30-day + demo dates) from Zaratan → Mac geotiffs/ via Globus.
#
#   globus login
#   cp scripts/globus/env.config.example.sh scripts/globus/env.config.local.sh
#   bash scripts/globus/sync_geotiffs.sh
#   bash scripts/globus/sync_geotiffs.sh --wait
#
set -euo pipefail

GLOBUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${GLOBUS_DIR}/../.." && pwd)"

exec python3 "${GLOBUS_DIR}/sync_geotiffs_globus.py" "$@"
