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

## HPC workflow (~30 min)

```bash
git clone git@github.com:SIENA-Agent/FloodMaps.git
cd FloodMaps
pip install -r requirements.txt

# 1. Refresh geotiffs/ (add new .tif, delete old dates)

# 2. Compute node — tile bake
./scripts/build.sh                    # WORKERS=8 optional

# 3. Login node — deploy (rsync docs/ here if build was remote)
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
