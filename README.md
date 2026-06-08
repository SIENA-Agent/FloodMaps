# SIENA Flood Maps

Interactive **SIENA** Sentinel-1 flood classification map viewer on GitHub Pages.

- **Repository:** https://github.com/SIENA-Agent/FloodMaps
- **Live site:** https://siena-agent.github.io/FloodMaps/
- **Basemap:** [OpenStreetMap](https://www.openstreetmap.org/)
- **Overlay:** Pre-baked PNG tiles (blue = permanent water, red = flood)

## Architecture (Model C)

| Branch | Contents | Size |
|--------|----------|------|
| **`main`** | Scripts, viewer source, docs only | ~1 MB |
| **`gh-pages`** | Built `docs/` (tiles + catalog) | ~40–450 MB, **1 commit** (force-replaced each deploy) |
| **Local** | `geotiffs/*.tif` (gitignored) | HPC scratch |

PNG tiles are **never** on `main`. Git history stays minimal.

## Publish workflow (HPC, e.g. every 30 min)

```bash
# 1. Update geotiffs/ (add new .tif, delete old dates)
pip install -r requirements.txt

# 2. Build + deploy to gh-pages
./scripts/publish.sh
```

`publish.sh` bakes tiles locally and **force-pushes** the site to the `gh-pages` branch. No commit to `main` unless you change scripts.

**GitHub Pages setting (one-time):** Repo → **Settings → Pages** → Source: **Deploy from branch** → Branch: **`gh-pages`** / **/(root)**.

## Preview locally

```bash
python scripts/build_site.py
python -m http.server 8080 --directory docs
```

## How it works

```
geotiffs/ (local)  →  build_site.py  →  docs/  →  force-push gh-pages  →  GitHub Pages
```

See [ARCHITECTURE.md](ARCHITECTURE.md).

## Classes

| Class | Color | Meaning |
|-------|-------|---------|
| 1 | Blue | Permanent water |
| 3 | Red | Flood water |
| 255 / 0 | Transparent | Background |

## Project layout

```
geotiffs/           # local GeoTIFFs (gitignored)
data/catalog.json   # generated at build (gitignored)
docs/               # generated site (gitignored; lives on gh-pages)
scripts/            # build_catalog.py, build_site.py, publish.sh
web/                # viewer source (on main)
```
