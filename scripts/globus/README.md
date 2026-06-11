# Globus — Zaratan SIENA_result → Mac geotiffs

Sync `*_RGB_*.tif` from HPC routine production into local `geotiffs/` for Mac **build** and **publish**.

## Prerequisites

| Item | Notes |
|------|--------|
| Globus CLI | `pip install 'globus-cli'` then `globus login` |
| Globus Connect Personal | Mac app running; repo folder writable in GCP preferences |
| `env.config.local.sh` | Copy from `env.config.example.sh`; set endpoint UUIDs + paths |
| Zaratan access | Same scratch path you use over SSH |

Find UUIDs:

```bash
bash scripts/globus/find_endpoints.sh
```

Typical UMD collections: **Zaratan DTN** (scratch / `SIENA_result`) → Mac **GCP endpoint**.

## Config

```bash
cp scripts/globus/env.config.example.sh scripts/globus/env.config.local.sh
```

Edit `env.config.local.sh`:

- `FLOODMAPS_ROOT` — your Mac clone path
- `SIENA_OUTPUT_BASE` — `.../routine_production/SIENA_result` on scratch
- `GLOBUS_SRC_ENDPOINT` — Zaratan DTN UUID
- `GLOBUS_DST_ENDPOINT` — Mac GCP UUID

## Routine sync (recommended)

```bash
cd $FLOODMAPS_ROOT
bash scripts/globus/sync_geotiffs.sh
```

What it does:

1. Recursive Globus listing of `SIENA_result` (granule folders)
2. Keeps **last 30 days** by Sentinel-1 **sensing date** + demo dates `20251214`, `20251217`, `20251219`
3. Transfers only `*_RGB_*.tif` **missing** from local `geotiffs/` (flat filenames)
4. Prunes local `.tif` outside the window (demos kept)

Options:

```bash
bash scripts/globus/sync_geotiffs.sh --dry-run   # plan only
bash scripts/globus/sync_geotiffs.sh --wait      # wait for Globus task
bash scripts/globus/sync_geotiffs.sh --no-prune  # skip local cleanup
```

Logs: `logs/globus/sync_*.log`

## Build & publish on Mac

```bash
./scripts/build.sh
./scripts/publish.sh
# bootstrap / full restore: PUBLISH_FULL=1 ./scripts/publish.sh
```

## Scripts

| File | Role |
|------|------|
| `sync_geotiffs.sh` | **Main** — incremental SIENA → Mac via Globus |
| `sync_geotiffs_globus.py` | Listing, retention filter, batch transfer |
| `siena_retention.py` | 30-day + demo date rules (shared with Zaratan logic) |
| `find_endpoints.sh` | Discover collection UUIDs |
| `transfer_geotiffs.sh` | Bulk copy of flat HPC `geotiffs/` (optional legacy) |
| `env.config.local.sh` | Your paths/UUIDs (gitignored) |

## Monitor transfers

https://app.globus.org/activity

```bash
globus task list
globus task wait <TASK_ID>
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `globus ls failed` | Check `SIENA_OUTPUT_BASE` and Zaratan DTN UUID |
| Destination not active | Start Globus Connect Personal |
| Consent / 403 | Approve transfer in Globus activity or email |
| First sync slow | Many missing files (~1–1.5 GB for 30 days); later runs are small |
| `REPLACE_WITH_*` | Fill `env.config.local.sh` |

## Web UI

Same logic manually: source = Zaratan DTN → `SIENA_result/<granule>/*_RGB_*.tif`, dest = Mac GCP → `geotiffs/`. The script automates retention + missing-only transfers.
