# Zaratan HPC — FloodMaps build & publish

Automates the Mac workflow on UMD Zaratan:

1. **Sync** new `*_RGB_*.tif` from SIENA routine production → `geotiffs/`
2. **Build** PNG tiles on a **compute node** (Slurm)
3. **Publish** `docs/` to GitHub from the **login node** (internet required)

## One-time setup (login node)

```bash
# 1. Clone repo
git clone git@github.com:SIENA-Agent/FloodMaps.git ~/FloodMaps
cd ~/FloodMaps

# 2. Python deps for tile bake (once)
/scratch/zt1/project/henryqy-prj/shared/env/miniconda3/envs/SIENA/bin/python -m pip install -r requirements.txt

# 3. Site paths (optional overrides)
cp scripts/Zaratan/env.config.example.sh scripts/Zaratan/env.config.local.sh
# edit FLOODMAPS_ROOT if not ~/FloodMaps

# 4. GitHub token — OUTSIDE the repo (see below)
# 5. SSH key on SIENA-Agent account for git push
ssh -T git@github.com
```

## GitHub token (HPC — safe, outside repo)

Zaratan has no `gh` CLI. Store a fine-grained PAT in your **home directory**, not in the public repo.

```bash
mkdir -p ~/.config/floodmaps
chmod 700 ~/.config/floodmaps

cp ~/FloodMaps/scripts/Zaratan/credentials.env.example ~/.config/floodmaps/credentials.env
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

Credentials file is loaded automatically (cron does not need `~/.bashrc`):

```cron
*/30 * * * * cd $HOME/FloodMaps && bash scripts/Zaratan/orchestrate_floodmaps.sh >> $HOME/FloodMaps/logs/zaratan/cron.log 2>&1
```

## Scripts

| File | Node | Role |
|------|------|------|
| `env.config.example.sh` | — | Default paths (copy → `env.config.local.sh`) |
| `credentials.env.example` | — | Template → `~/.config/floodmaps/credentials.env` |
| `sync_geotiffs.sh` | login | SIENA_result → `geotiffs/` |
| `slurm_build_floodmaps.template.sh` | compute | Runs `scripts/build.sh` |
| `orchestrate_floodmaps.sh` | login | sync → sbatch → wait → publish |
| `runtime_env.sh` | compute | `PYTHON_BIN` + PROJ/GDAL (no conda activate) |
| `../load_github_credentials.sh` | login | Loads token from home dir |

## Authorization checklist

| What | Where | How |
|------|-------|-----|
| **Git push** | login | SSH key on SIENA-Agent GitHub account |
| **Actions deploy** | login | `~/.config/floodmaps/credentials.env` (auto-loaded) |
| **Slurm** | login | Zaratan account on `standard` partition |
| **SIENA data** | login/compute | Read `.../routine_production/SIENA_result` |
| **Python deps** | login once | `pip install -r requirements.txt` for `PYTHON_BIN` |

Compute nodes have **no internet** — only `build.sh` runs there. `publish.sh` always runs on the login node.

## Troubleshooting

- **`gh: command not found`:** expected on Zaratan — use `~/.config/floodmaps/credentials.env`.
- **Deploy not triggered:** `source ~/.config/floodmaps/credentials.env` then re-run publish; check token permissions.
- **Build job fails:** see `floodmaps_build_<jobid>.out`; often missing `pip install -r requirements.txt`.
- **No new tifs:** confirm `SIENA_OUTPUT_BASE` and `*_RGB_*.tif` under that tree.
