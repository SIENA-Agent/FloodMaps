# Architecture — SIENA Flood Maps

How we display palette GeoTIFFs on GitHub Pages, and how to scale for HPC-driven updates (every ~30 min).

## Target operating model (Model C)

| Parameter | Plan |
|-----------|------|
| New granules | ~100 per sensing day |
| Retention | 3–5 days in local `geotiffs/` |
| **`main` branch** | Scripts + viewer source only (~1 MB) |
| **`gh-pages` branch** | Current built site (~40–450 MB), **one commit**, force-replaced each deploy |
| Update cadence | HPC cron ~30 min: refresh geotiffs → `./scripts/publish.sh` |
| Viewer goal | Smooth pan/zoom on GitHub Pages (no backend) |

At ~195 KB baked tiles per granule: **~2,000 granules ≈ 400 MB** on `gh-pages` (not in `main` history).

## Branch layout

```
main          scripts/, web/, README  —  tiny git history forever
gh-pages      docs/ (tiles + viewer)  —  force-pushed each publish, no history growth
local/HPC     geotiffs/*.tif          —  gitignored
```

## Production path: pre-baked PNG tiles

```
geotiffs/*.tif  →  build_site.py  →  docs/tiles/ + catalog
                                          ↓
                              publish.sh → force-push gh-pages
                                          ↓
                              Leaflet tile layers (visible PNGs only)
```

**Default:** `python scripts/build_site.py` (`--mode tiles`)

### Viewer behavior (tiles mode)

| Technique | Why |
|-----------|-----|
| **Pre-baked PNGs on HPC** | Colors baked once; no browser GeoTIFF decode |
| **All granules per date registered** | Cheap `L.tileLayer` URLs — only visible PNGs fetched |
| **Leaflet tile cache** | Off-screen tiles discarded — low Safari memory |

Status line example: `2026-06-07: 95 granule(s) — pan/zoom to explore`

### GeoTIFF mode (local experiments only)

`python scripts/build_site.py --mode geotiff` — not used for production deploy.

## HPC cron workflow (~30 min)

```bash
# 1. Upstream job drops new .tif into geotiffs/, deletes dates older than N days
# 2. Publish (build + deploy — no main-branch commit)
./scripts/publish.sh
```

`publish.sh` builds `docs/` locally and **force-pushes** to `origin/gh-pages`. The `main` branch is touched only when scripts or viewer source change.

**GitHub Pages (one-time):** Settings → Pages → **Deploy from branch** → `gh-pages` / `/(root)`.

### Pruning old dates

Delete `.tif` files for sensing dates you no longer need before `./scripts/publish.sh`. The next deploy shrinks the live site automatically.

Optional future: `scripts/prune_catalog.py --keep-days 5`.

## Storage comparison

| Model | `main` .git | Remote `main` | Live site |
|-------|-------------|---------------|-----------|
| A (TIFFs in git) | Large | ~250 MB TIFFs | CI bakes |
| B (tiles on main) | ~43 MB+ history | ~43 MB+ | CI deploys |
| **C (gh-pages)** | **~1 MB** | **~1 MB** | **gh-pages ~43–450 MB, 1 commit** |

## Future scaling

| Stage | Approach |
|-------|----------|
| >450 MB on gh-pages | Prune to 3 days of granules before publish |
| 1000+ granules | COG on CDN (S3/R2) + same viewer URLs |
| Sub-minute updates | Tile server (TiTiler) — Pages hosts viewer only |

## Reproducibility checklist

- [x] Source of truth: `geotiffs/*.tif` on HPC/local (gitignored)
- [x] Build: `scripts/build_catalog.py` + `scripts/build_site.py` + `scripts/publish.sh`
- [x] No generated files on `main` (`docs/`, `data/catalog.json` gitignored)
- [x] Class colors in `web/js/viewer.js` (palette classes 1=blue, 3=red)
- [ ] Optional retention prune script (future)
