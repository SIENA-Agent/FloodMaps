# Zaratan HPC — FloodMaps build & publish

Automates the Mac workflow on UMD Zaratan:

1. **Sync** new `*_RGB_*.tif` from SIENA routine production → `geotiffs/`
2. **Build** PNG tiles on a **compute node** (Slurm)
3. **Publish** `docs/` to GitHub from the **login node** (internet required)

## One-time setup (login node)

```bash
# 1. Clone repo (if not already)
git clone git@github.com:SIENA-Agent/FloodMaps.git ~/FloodMaps
cd ~/FloodMaps
pip install -r requirements.txt   # into PYTHON_BIN env, or python -m venv .venv && .venv/bin/pip install -r requirements.txt

# 2. Site config
cp scripts/Zaratan/env.config.example.sh scripts/Zaratan/env.config.local.sh
# Edit FLOODMAPS_ROOT, PYTHON_BIN if needed

# 3. GitHub auth (publish needs outbound network — login node only)
gh auth login
# OR: export GITHUB_TOKEN=ghp_...   # fine-grained PAT, Actions: Read+Write

# 4. Git remote (SSH recommended on HPC)
git remote -v   # should point at SIENA-Agent/FloodMaps
```

## Run (login node)

```bash
cd ~/FloodMaps
bash scripts/Zaratan/orchestrate_floodmaps.sh
```

Options:

| Flag | Effect |
|------|--------|
| `--sync-only` | Copy/prune geotiffs only |
| `--build-only` | Skip sync; use existing `geotiffs/` |
| `--no-publish` | Build only; run `./scripts/publish.sh` yourself later |

## Cron (~every 30 min)

```cron
*/30 * * * * cd $HOME/FloodMaps && bash scripts/Zaratan/orchestrate_floodmaps.sh >> logs/zaratan/cron.log 2>&1
```

## Scripts

| File | Node | Role |
|------|------|------|
| `env.config.example.sh` | — | Default paths (copy → `env.config.local.sh`) |
| `sync_geotiffs.sh` | login | SIENA_result → `geotiffs/` |
| `slurm_build_floodmaps.template.sh` | compute | Runs `scripts/build.sh` |
| `orchestrate_floodmaps.sh` | login | sync → sbatch → wait → publish |
| `runtime_env.sh` | compute | `PYTHON_BIN` + PROJ/GDAL (no conda activate) |

## Authorization checklist

| What | Where | How |
|------|-------|-----|
| **Git push** | login | SSH key added to SIENA-Agent GitHub account, or HTTPS + credential |
| **Actions deploy** | login | `gh auth login` or `GITHUB_TOKEN` in `env.config.local.sh` |
| **Slurm** | login | Valid Zaratan account + allocation on `standard` (or your partition) |
| **SIENA data** | login/compute | Read access to `/scratch/zt1/project/henryqy-prj/.../SIENA_result` |
| **Python deps** | login once | `pip install -r requirements.txt` for `PYTHON_BIN` |

Compute nodes have **no internet** — only `build.sh` runs there. `publish.sh` always runs on the login node.

## Repo layout after clone

```
geotiffs/          ← sync_geotiffs.sh writes here (.tif gitignored)
data/              ← build writes catalog.json (gitignored)
docs/              ← build writes tiles + viewer (gitignored)
scripts/
  build.sh
  publish.sh
  Zaratan/         ← this folder
logs/zaratan/      ← orchestrator logs (gitignored)
```

## Troubleshooting

- **Build job fails immediately:** check `floodmaps_build_<jobid>.out`; often missing `pip install -r requirements.txt`.
- **Publish fails:** run on login node; verify `gh auth status` or `GITHUB_TOKEN`.
- **No new tifs synced:** confirm `SIENA_OUTPUT_BASE` and `*_RGB_*.tif` files exist under that tree.
- **macOS vs Linux date:** `sync_geotiffs.sh` prune uses `date -d` (GNU). On Mac, prune manually or run sync on Zaratan only.
