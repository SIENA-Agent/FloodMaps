# Zaratan HPC — FloodMaps build & publish

Automates the Mac workflow on UMD Zaratan:

1. **Sync** new `*_RGB_*.tif` from SIENA routine production → `geotiffs/`
2. **Build** PNG tiles on a **compute node** (Slurm)
3. **Publish** `docs/` to GitHub from the **login node** (internet required)

## One-time setup (login node)

```bash
# 1. Clone repo (Zaratan shared gateway path)
git clone git@github.com:SIENA-Agent/FloodMaps.git /scratch/zt1/project/henryqy-prj/shared/code/gateway/FloodMaps
cd /scratch/zt1/project/henryqy-prj/shared/code/gateway/FloodMaps

# 2. Python deps for tile bake (once)
/scratch/zt1/project/henryqy-prj/shared/env/miniconda3/envs/SIENA/bin/python -m pip install -r requirements.txt

# 3. Site paths (optional overrides)
cp scripts/Zaratan/env.config.example.sh scripts/Zaratan/env.config.local.sh
# optional: edit FLOODMAPS_ROOT or other paths

# 4. GitHub token — OUTSIDE the repo (see below)
# 5. Git push auth (pick one)
#    A) HTTPS clone + credentials.env (GITHUB_TOKEN used automatically by publish.sh)
#    B) SSH remote: git remote set-url origin git@github.com:SIENA-Agent/FloodMaps.git
#       ssh -T git@github.com
```

## GitHub token (HPC — safe, outside repo)

Zaratan has no `gh` CLI. Store a fine-grained PAT in your **home directory**, not in the public repo.

```bash
mkdir -p ~/.config/floodmaps
chmod 700 ~/.config/floodmaps

cp /scratch/zt1/project/henryqy-prj/shared/code/gateway/FloodMaps/scripts/Zaratan/credentials.env.example ~/.config/floodmaps/credentials.env
chmod 600 ~/.config/floodmaps/credentials.env

vim ~/.config/floodmaps/credentials.env
# Replace github_pat_REPLACE_ME with your real token
```

The file should contain one line:

```bash
export GITHUB_TOKEN='github_pat_...'
```

**PAT permissions** (SIENA-Agent → FloodMaps only):

- Contents: Read and write
- Actions: Read and write

**Verify:**

```bash
source ~/.config/floodmaps/credentials.env
echo "token loaded: ${GITHUB_TOKEN:+yes}"
curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user | head -3
```

Scripts auto-load this file when `GITHUB_TOKEN` is not already set:

- `scripts/load_github_credentials.sh` (used by `publish.sh` and `orchestrate_floodmaps.sh`)
- Default path: `~/.config/floodmaps/credentials.env`
- Override: `export FLOODMAPS_CREDENTIALS_FILE=/other/path`

**Do not** put the token in `env.config.local.sh` or any tracked file.

### Optional: same file on your Mac

Mac can use **either**:

| Method | When |
|--------|------|
| `gh auth login` | Preferred on Mac if `gh` is installed |
| `~/.config/floodmaps/credentials.env` | Fallback; also works in cron |

`publish.sh` tries **gh first**, then **GITHUB_TOKEN** (from env or credentials file).

## Mac bootstrap → HPC incremental (recommended)

1. **Mac (once):** Globus ~30 days + demo geotiffs → `./scripts/build.sh` → `PUBLISH_FULL=1 ./scripts/publish.sh` → verify live site.
2. **HPC:** `git pull origin main` (scripts only — `.gh-pages-staging/` is local/gitignored).
3. **HPC routine:** `sync_geotiffs.sh` → Slurm `build.sh` → `./scripts/publish.sh` (auto incremental: few granules add/remove per run).

First HPC publish after Mac bootstrap seeds deploy state from `origin/gh-pages` (no Mac copy of `.gh-pages-staging/` needed).

Kill any old foreground publish still running `cp -al` from a previous script version before re-testing.

## Run (login node)

```bash
cd /scratch/zt1/project/henryqy-prj/shared/code/gateway/FloodMaps
bash scripts/Zaratan/orchestrate_floodmaps.sh
```

Options:

| Flag | Effect |
|------|--------|
| `--sync-only` | Copy/prune geotiffs only (30-day **sensing-date** window from granule folder names; demo 2025-12-14/17/19 always kept) |
| `--build-only` | Skip sync; use existing `geotiffs/` |
| `--no-publish` | Build only; publish yourself later |
| `--wait-publish` | Block until `publish.sh` finishes (default: background publish) |

### Publish only (background)

Large deploys (300k+ PNGs) can take a long time. Run in the background so SSH disconnects do not kill the job:

```bash
bash scripts/Zaratan/publish_background.sh
tail -f logs/zaratan/publish_*.log
```

`publish.sh` uses `docs/` as the git work-tree (no file copy). Incremental runs only stage changed `tiles/<granule_id>/` folders.

### Quick test (incremental on HPC)

After Mac bootstrap, test HPC with a small delta:

```bash
git pull origin main
KEEP_DAYS=1 bash scripts/Zaratan/sync_geotiffs.sh   # small geotiff set
bash scripts/Zaratan/orchestrate_floodmaps.sh --build-only --no-publish
bash scripts/publish.sh                              # should report +N -M granules
```

Or publish only after a routine sync/build:

```bash
bash scripts/Zaratan/publish_background.sh
tail -f logs/zaratan/publish_*.log
```

Force full re-publish (recovery): `PUBLISH_FULL=1 ./scripts/publish.sh`

## Cron (~every 30 min)

Credentials file is loaded automatically (cron does not need `~/.bashrc`):

```cron
*/30 * * * * cd /scratch/zt1/project/henryqy-prj/shared/code/gateway/FloodMaps && bash scripts/Zaratan/orchestrate_floodmaps.sh --wait-publish
```

Use `--wait-publish` in cron so the job does not overlap with a still-running background publish.

Background (orchestrator writes its own log under `logs/zaratan/`):

```bash
nohup bash scripts/Zaratan/orchestrate_floodmaps.sh &
tail -f logs/zaratan/orchestrate_*.log
```

Do **not** redirect nohup output to the same log file — that duplicates lines.

## Scripts

| File | Node | Role |
|------|------|------|
| `env.config.example.sh` | — | Default paths (copy → `env.config.local.sh`) |
| `credentials.env.example` | — | Template → `~/.config/floodmaps/credentials.env` |
| `sync_geotiffs.sh` | login | SIENA_result → `geotiffs/` |
| `slurm_build_floodmaps.template.sh` | compute | Runs `scripts/build.sh` |
| `orchestrate_floodmaps.sh` | login | sync → sbatch → wait → background publish |
| `publish_background.sh` | login | `nohup publish.sh` + log under `logs/zaratan/` |
| `runtime_env.sh` | compute | `PYTHON_BIN` + PROJ/GDAL (no conda activate) |
| `../load_github_credentials.sh` | login | Loads token from home dir |
| `../publish_stage.py` | login | Catalog-diff staging (called by `publish.sh`) |

## Authorization checklist

| What | Where | How |
|------|-------|-----|
| **Git push** | login | `GITHUB_TOKEN` in credentials.env (HTTPS) **or** SSH key on SIENA-Agent |
| **Actions deploy** | login | `~/.config/floodmaps/credentials.env` (auto-loaded) |
| **Slurm** | login | Zaratan account on `standard` partition |
| **SIENA data** | login/compute | Read `.../routine_production/SIENA_result` |
| **Python deps** | login once | `pip install -r requirements.txt` for `PYTHON_BIN` |

Compute nodes have **no internet** — only `build.sh` runs there. `publish.sh` always runs on the login node.

## Troubleshooting

- **`gh: command not found`:** expected on Zaratan — use `~/.config/floodmaps/credentials.env`.
- **Deploy not triggered:** re-run `publish_background.sh`; check token permissions.
- **Publish killed by SSH disconnect:** use `publish_background.sh`, not foreground `publish.sh`.
- **Publish very slow (old script):** kill stale `cp -al` jobs; `git pull` and use incremental `publish.sh`.
- **Incremental shows 0 add / 0 remove:** geotiff set matches last deploy; change `KEEP_DAYS` or wait for new SIENA granules.
- **Build job fails:** see `floodmaps_build_<jobid>.out`; often missing `pip install -r requirements.txt`.
- **No new tifs:** confirm `SIENA_OUTPUT_BASE` and `*_RGB_*.tif` under that tree.
