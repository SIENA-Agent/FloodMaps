# Globus — Zaratan → Mac geotiffs

## Recommended: daily ZIP sync (fast)

Production SIENA results are zipped daily on Zaratan. Transfer the latest ZIPs, unzip, copy `*_2classes_RGB*` / `*_RGB_*` `.tif` into flat `geotiffs/`.

```bash
pip install 'globus-cli' && globus login
cp scripts/globus/env.config.example.sh scripts/globus/env.config.local.sh
# edit paths + GLOBUS_SRC_ENDPOINT / GLOBUS_DST_ENDPOINT

bash scripts/globus/sync_geotiffs_from_zip.sh
```

What it does:

1. `globus ls` on `ZIP/SIENA/` (one level — seconds, not minutes)
2. Transfer latest **2** daily zips (configurable) → `geotiffs/.zip-staging/incoming/`
3. **`globus task wait`** until transfer finishes
4. Unzip → copy RGB GeoTIFFs → `geotiffs/` → delete zip + extract tree

Options:

```bash
bash scripts/globus/sync_geotiffs_from_zip.sh --dry-run
bash scripts/globus/sync_geotiffs_from_zip.sh --zip-count 3
bash scripts/globus/sync_geotiffs_from_zip.sh --skip-transfer   # process zips already in incoming/
bash scripts/globus/sync_geotiffs_from_zip.sh --force             # re-download / re-process
```

Logs: `logs/globus/sync_zip_*.log`

Then build & publish:

```bash
./scripts/build.sh
./scripts/publish.sh
```

### Config (`env.config.local.sh`)

| Variable | Purpose |
|----------|---------|
| `FLOODMAPS_ROOT` | Mac repo path |
| `SIENA_ZIP_BASE` | HPC path to daily zips |
| `ZIP_SYNC_COUNT` | Latest N zip files (default `2`) |
| `GLOBUS_SRC_ENDPOINT` | Zaratan DTN UUID |
| `GLOBUS_DST_ENDPOINT` | Mac GCP UUID |

Find UUIDs: `bash scripts/globus/find_endpoints.sh`

---

## Legacy: SIENA_result recursive sync (slow)

`sync_geotiffs.sh` lists all granule folders recursively — can take 15+ minutes. Prefer ZIP sync above.

---

## Prerequisites

| Item | Notes |
|------|--------|
| Globus CLI | `pip install 'globus-cli'` |
| Globus Connect Personal | Running; repo path writable in GCP preferences |
| Zaratan access | Same scratch paths as SSH |

## Scripts

| File | Role |
|------|------|
| `sync_geotiffs_from_zip.sh` | **Main** — ZIP transfer + unzip + copy |
| `sync_geotiffs_from_zip.py` | Implementation |
| `sync_geotiffs.sh` | Legacy SIENA_result listing (slow) |
| `find_endpoints.sh` | Discover collection UUIDs |
| `transfer_geotiffs.sh` | Bulk flat `geotiffs/` copy |
| `env.config.local.sh` | Your paths/UUIDs (gitignored) |

Monitor: https://app.globus.org/activity
