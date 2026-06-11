# Globus — HPC (Zaratan) → Mac geotiffs

Transfer `geotiffs/*.tif` from Zaratan to your Mac for local **build** and **publish** (fast SSD, no NFS git pain).

**Recommended source on HPC:** `FloodMaps/geotiffs/` after `sync_geotiffs.sh` (30-day window + demo dates), not the full `SIENA_result` tree.

## Authorization checklist

| Step | What | Where |
|------|------|--------|
| 1 | **Globus account** | https://app.globus.org — use UMD institutional login if offered |
| 2 | **Zaratan / scratch access** | Same as your SSH project (`zt1/project/henryqy-prj/...`) — PI must have granted you scratch |
| 3 | **Globus read on scratch** | UMD HPC Globus collection must expose `/scratch/zt1/...` — see [UMD HPCC Globus help](https://hpcc.umd.edu/hpcc/help/globus.html) |
| 4 | **Globus Connect Personal (Mac)** | Install + sign in with same Globus identity — [install guide](https://docs.globus.org/globus-connect-personal/install/) |
| 5 | **Writable Mac folder** | In GCP preferences, allow writes to your FloodMaps repo (e.g. `~/Downloads/Web_Geodata_Visualization`) |
| 6 | **First transfer consent** | Globus may email you to approve HPC → Mac transfer — click **Allow** |

You do **not** need a separate API key for basic CLI transfers after `globus login`.

## One-time Mac setup

### 1. Install tools

```bash
# Globus CLI (pick one)
brew install globus-cli
# or: pip install 'globus-cli'

# Globus Connect Personal (Mac app)
# https://docs.globus.org/globus-connect-personal/install/
```

### 2. Log in

```bash
globus login
globus whoami
```

### 3. Start Globus Connect Personal

- Open the **Globus Connect Personal** app on your Mac
- Sign in with the **same** Globus account
- **Preferences → Accessible Directories** → add your repo parent folder, e.g.  
  `/Users/qyang/Downloads/Web_Geodata_Visualization`

### 4. Find collection UUIDs

```bash
cd /Users/qyang/Downloads/Web_Geodata_Visualization
bash scripts/globus/find_endpoints.sh
```

Or in the **Globus web app** (File Manager):

1. Search collections for **UMD** / **Zaratan** / **scratch** → open → copy UUID from URL (`origin_id=...`)
2. Your Mac endpoint appears under **Endpoints** → your GCP name → copy UUID

### 5. Local config (not committed)

```bash
cp scripts/globus/env.config.example.sh scripts/globus/env.config.local.sh
vim scripts/globus/env.config.local.sh
```

Set at minimum:

```bash
export GLOBUS_SRC_ENDPOINT='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'  # Zaratan scratch
export GLOBUS_DST_ENDPOINT='yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'  # Mac GCP
```

Paths default to:

| Variable | Default |
|----------|---------|
| `HPC_GEOTIFF_PATH` | `.../FloodMaps/geotiffs` on Zaratan |
| `MAC_GEOTIFF_DIR` | `$FLOODMAPS_ROOT/geotiffs` on Mac |

## Routine workflow

### On Zaratan (login node) — refresh HPC geotiffs

```bash
cd /scratch/zt1/project/henryqy-prj/shared/code/gateway/FloodMaps
bash scripts/Zaratan/sync_geotiffs.sh
```

This copies/prunes `*_RGB_*.tif` into `geotiffs/` (30 days + demo dates).

### On Mac — Globus transfer

```bash
cd /Users/qyang/Downloads/Web_Geodata_Visualization

# GCP app running
bash scripts/globus/transfer_geotiffs.sh --verify
```

- First run: transfers all `.tif` (can take a while — GB scale)
- Later runs: `--sync-level checksum` (default) skips unchanged files

Logs: `logs/globus/transfer_*.log`

### On Mac — build & publish

```bash
pip install -r requirements.txt   # once
./scripts/build.sh
./scripts/publish.sh                # incremental if site already live
# or bootstrap / restore: PUBLISH_FULL=1 ./scripts/publish.sh
```

## Scripts

| File | Role |
|------|------|
| `env.config.example.sh` | Template paths + endpoint UUID placeholders |
| `env.config.local.sh` | Your UUIDs (gitignored — create from example) |
| `find_endpoints.sh` | List/search endpoints after `globus login` |
| `transfer_geotiffs.sh` | Submit HPC → Mac recursive transfer |

### Options

```bash
bash scripts/globus/transfer_geotiffs.sh --dry-run   # print command only
bash scripts/globus/transfer_geotiffs.sh --verify    # wait until complete
```

Monitor in browser: https://app.globus.org/activity

```bash
globus task list
globus task show <TASK_ID>
```

## Web app alternative

If you already use https://app.globus.org/file-manager:

| Panel | Path |
|-------|------|
| **Source** | Zaratan collection → `/scratch/zt1/project/henryqy-prj/shared/code/gateway/FloodMaps/geotiffs` |
| **Destination** | Your Mac GCP → `/Users/qyang/Downloads/Web_Geodata_Visualization/geotiffs` |

Select all `*.tif` → **Transfer or sync to…** → enable sync if updating.

CLI scripts use the same paths and are easier to repeat.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Permission denied` on HPC path | Confirm SSH can read path; ask PI for scratch + Globus mapping |
| Destination not activated | Start Globus Connect Personal on Mac |
| `403` / consent required | Approve transfer in email or https://app.globus.org/activity |
| `REPLACE_WITH_*` error | Fill `env.config.local.sh` |
| Transfer slow | Expected for first full 30-day set; later sync is incremental |
| Wrong files on Mac | Source should be `geotiffs/` not full `SIENA_result` |

## Size expectations

~2000 granules × ~0.5–0.7 MB ≈ **1–1.5 GB** of GeoTIFFs for 30 days. Globus handles this well; first transfer may take tens of minutes depending on network.
