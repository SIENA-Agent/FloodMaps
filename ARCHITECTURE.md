# Architecture — SIENA Flood Maps

How we display palette GeoTIFFs on GitHub Pages, and how to scale for HPC-driven updates (every ~30 min).

## Target operating model (Model C)

| Parameter | Plan |
|-----------|------|
| New granules | ~100 per sensing day |
| Retention | 30 days in local `geotiffs/` + demo dates 20251214/17/19 always kept |
| **`main` branch** | Scripts + viewer source only (~1 MB) |
| **`gh-pages` branch** | Current built site (~40–450 MB), **one commit**, force-replaced each deploy |
| Update cadence | HPC cron ~30 min: refresh geotiffs → `build.sh` → `publish.sh` |
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
geotiffs/*.tif  →  build.sh  →  docs/tiles/ + catalog
                                    ↓
                        publish.sh → force-push gh-pages
                                    ↓
                        Leaflet tile layers (visible PNGs only)
```

**Build:** `./scripts/build.sh` (compute node) — wraps `build_site.py --mode tiles`
**Publish:** `./scripts/publish.sh` (login node) — catalog-diff incremental staging via `publish_stage.py`; Mac bootstrap uses `--full`

### Viewer behavior (tiles mode)

| Technique | Why |
|-----------|-----|
| **Pre-baked PNGs on HPC** | Colors baked once; no browser GeoTIFF decode |
| **All granules per date registered** | Cheap `L.tileLayer` URLs — only visible PNGs fetched |
| **Leaflet tile cache** | Off-screen tiles discarded — low Safari memory |

Status line example: `2026-06-07: 95 granule(s) — pan/zoom to explore`

### GeoTIFF mode (local experiments only)

`python scripts/build_site.py --mode geotiff` — not used for production deploy.

## HPC two-step workflow (~30 min)

```bash
# 1. Upstream job drops new .tif into geotiffs/, deletes dates older than N days

# 2. Compute node — tile bake (can run on batch node with geotiffs/)
./scripts/build.sh              # optional: WORKERS=8

# 3. Login node — deploy only (rsync docs/ from compute if needed)
./scripts/publish.sh
```

`build.sh` writes `docs/` and `data/catalog.json`. `publish.sh` commits from `docs/` (git work-tree) into `.gh-pages-staging/.git` and pushes `gh-pages`. Routine runs stage only added/removed `tiles/<granule_id>/` plus catalog/viewer files. Neither touches `main` unless scripts change.

**Bootstrap:** Mac — Globus geotiffs → `build.sh` → `PUBLISH_FULL=1 publish.sh`. **Routine:** HPC — sync → `build.sh` → `publish.sh` (auto incremental).

### Compute-node minimal copy

If not cloning the full repo on the compute node, copy at least:

```
scripts/build.sh build_site.py build_catalog.py render_tiles.py
web/ requirements.txt geotiffs/*.tif
```

Restore the same paths so output lands in `docs/` at repo root.

**GitHub Pages (one-time):** Settings → Pages → **GitHub Actions**. Push to `gh-pages` via `publish.sh` triggers `.github/workflows/pages.yml`.

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
- [x] Build: `scripts/build.sh` → `build_site.py`; publish: `scripts/publish.sh`
- [x] No generated files on `main` (`docs/`, `data/catalog.json` gitignored)
- [x] Class colors in `web/js/viewer.js` (palette classes 1=blue, 3=red)
- [ ] Optional retention prune script (future)
