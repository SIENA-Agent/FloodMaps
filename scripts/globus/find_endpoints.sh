#!/usr/bin/env bash
# List Globus endpoints/collections to fill env.config.local.sh UUIDs.
set -euo pipefail

GLOBUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v globus >/dev/null 2>&1; then
  echo "globus CLI not found. Install:" >&2
  echo "  brew install globus-cli   # or: pip install 'globus-cli'" >&2
  exit 1
fi

if ! globus whoami >/dev/null 2>&1; then
  echo "Not logged in. Run:" >&2
  echo "  globus login" >&2
  exit 1
fi

echo "=== Globus identity ==="
globus whoami

echo ""
echo "=== Your endpoints (Mac GCP often listed here) ==="
WHOAMI="$(globus whoami 2>/dev/null || true)"
if [[ -n "$WHOAMI" ]]; then
  globus endpoint search "$WHOAMI" 2>/dev/null | head -15 || true
fi
echo "(Or: Globus web app → Endpoints → your Mac GCP name)"

echo ""
echo "=== Search UMD / Zaratan (source collections) ==="
globus endpoint search "UMD" --filter-scope advertised 2>/dev/null | head -20 || true
globus endpoint search "Zaratan" 2>/dev/null | head -20 || true

echo ""
echo "=== Globus Connect Personal on this Mac ==="
if command -v globus-connect-personal >/dev/null 2>&1; then
  globus-connect-personal -status 2>/dev/null || true
else
  echo "Globus Connect Personal not in PATH."
  echo "Install: https://docs.globus.org/globus-connect-personal/install/"
fi

echo ""
echo "Copy UUIDs into scripts/globus/env.config.local.sh:"
echo "  GLOBUS_SRC_ENDPOINT  — Zaratan scratch (source)"
echo "  GLOBUS_DST_ENDPOINT  — your Mac GCP endpoint (destination)"
echo ""
echo "In the Globus web app: File Manager → select collection → UUID is in the URL:"
echo "  https://app.globus.org/file-manager?origin_id=<UUID>"
