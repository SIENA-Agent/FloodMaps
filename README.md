# SIENA Flood Maps

Interactive **SIENA** Sentinel-1 flood classification map viewer on GitHub Pages.

- **Repository:** https://github.com/SIENA-Agent/FloodMaps
- **Live site:** https://siena-agent.github.io/FloodMaps/
- **Basemap:** [OpenStreetMap](https://www.openstreetmap.org/)
- **Overlay:** Pre-baked PNG tiles (blue = permanent water, red = flood)

## Architecture (Model C)

| Branch | Contents | Size |
|--------|----------|------|
| **`main`** | Scripts, folder layout, viewer source | ~1 MB |
| **`gh-pages`** | Built `docs/` (tiles + catalog) | ~40–450 MB, **1 commit** |
| **Local/HPC** | `geotiffs/*.tif` (gitignored) | scratch storage |

PNG tiles are **never** on `main`. Git history stays minimal.

## Repository layout (after `git clone`)

```
geotiffs/           # drop .tif here (README + .gitkeep in git)
data/               # build writes catalog.json here (README in git)
docs/               # build writes full site here (README in git)
scripts/
  build.sh          # compute node — bake PNG tiles → docs/
  publish.sh        # login node — push docs/ → gh-pages
  build_site.py     # called by build.sh
web/                # viewer source templates
```

See `docs/README.md` and `data/README.md` for build output details.

## Deploy workflow (Mac bootstrap → HPC updates)

**Phase 1 — Mac (one-time full site)**  
Globus (or copy) ~30 days of geotiffs + demo dates → build → full publish:

```bash
pip install -r requirements.txt
./scripts/build.sh
PUBLISH_FULL=1 ./scripts/publish.sh    # or: ./scripts/publish.sh --full
```

Confirm https://siena-agent.github.io/FloodMaps/ works.

**Phase 2 — HPC (routine incremental)**  
After `git pull origin main`, sync a few new/removed granules, build, publish:

```bash
./scripts/build.sh
./scripts/publish.sh                   # auto: only changed granule tiles + catalog
# or SSH-safe: bash scripts/Zaratan/publish_background.sh
```

`publish.sh` uses `docs/` directly (no copy to `/tmp`). It compares `catalog.json` to the last deploy and only `git add`s / `git rm`s changed `tiles/<granule_id>/` folders. First HPC run seeds state from `origin/gh-pages` automatically.

## HPC workflow (~30 min)

```bash
git clone git@github.com:SIENA-Agent/FloodMaps.git
cd FloodMaps
pip install -r requirements.txt

# 1. Refresh geotiffs/ (add new .tif, delete old dates)

# 2. Compute node — tile bake
./scripts/build.sh                    # WORKERS=8 optional

# 3. Login node — incremental deploy
./scripts/publish.sh
```

**GitHub Pages (one-time):**
1. Settings → Pages → source = **GitHub Actions**
2. Deploy auth (pick one):
   - **Mac:** `gh auth login` (preferred if `gh` installed)
   - **Mac or HPC:** `~/.config/floodmaps/credentials.env` — copy from `scripts/Zaratan/credentials.env.example` (never in repo)

`publish.sh` tries **gh** first, then **GITHUB_TOKEN** from env or the credentials file.

Each `./scripts/publish.sh` pushes `gh-pages`, then starts the deploy workflow (~1–2 min).

## Preview locally

```bash
./scripts/build.sh
python -m http.server 8080 --directory docs
```

## How it works

```
geotiffs/  →  build.sh  →  docs/ + data/catalog.json  →  publish.sh  →  gh-pages
```

## HPC (Zaratan)

On UMD Zaratan: sync SIENA products → Slurm tile build → login-node publish.

```bash
cd /scratch/zt1/project/henryqy-prj/shared/code/gateway/FloodMaps
# optional overrides: cp scripts/Zaratan/env.config.example.sh scripts/Zaratan/env.config.local.sh
bash scripts/Zaratan/orchestrate_floodmaps.sh
```

See [scripts/Zaratan/README.md](scripts/Zaratan/README.md) for setup, cron, and authorization.

## Classes

| Class | Color | Meaning |
|-------|-------|---------|
| 1 | Blue | Permanent water |
| 3 | Red | Flood water |
| 255 / 0 | Transparent | Background |
