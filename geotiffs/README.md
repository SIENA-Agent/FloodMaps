# GeoTIFF data folder (local only)

Drop Sentinel-1 SIENA RGB flood classification `.tif` files here.

**Not in git** (see `.gitignore`). HPC refreshes this folder, prunes old dates, then runs `./scripts/publish.sh`.

## Naming convention

Filenames should include Sentinel-1 sensing times, e.g.:

`SIENA_2classes_RGB_S1A_IW_GRDH_1SDV_20251214T141324_20251214T141349_..._sigma0_vv_30m.tif`

The build script parses the **first** `YYYYMMDDTHHMMSS` pair for catalog dates.

## Publish

```bash
./scripts/publish.sh
```

Builds tiles locally and deploys to the `gh-pages` branch. No commit to `main`.
