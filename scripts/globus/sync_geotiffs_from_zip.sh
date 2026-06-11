#!/usr/bin/env bash
# Sync latest N daily ZIPs (filename date YYYY-MM-DD.zip, default 3) → geotiffs/*.tif
#
#   bash scripts/globus/sync_geotiffs_from_zip.sh
#   bash scripts/globus/sync_geotiffs_from_zip.sh --dry-run
#   bash scripts/globus/sync_geotiffs_from_zip.sh --wait   # (transfer always waits)
#
set -euo pipefail

GLOBUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${GLOBUS_DIR}/sync_geotiffs_from_zip.py" "$@"
