# geotiffs/ — source GeoTIFF input

Drop Sentinel-1 SIENA RGB flood classification `.tif` files here.

**`.tif` files are gitignored.** Only this README and `.gitkeep` are in git so clones show the expected layout.

## Naming convention

Filenames should include Sentinel-1 sensing times, e.g.:

`SIENA_2classes_RGB_S1A_IW_GRDH_1SDV_20251214T141324_20251214T141349_..._sigma0_vv_30m.tif`

The build script parses the **first** `YYYYMMDDTHHMMSS` pair for catalog dates.

## Build (compute node)

```bash
./scripts/build.sh
```

Reads `geotiffs/*.tif`, writes PNG tiles and catalog to `docs/` and `data/`.

Prune granules older than your retention window before building.

## Publish (login node)

```bash
./scripts/publish.sh
```

Deploys `docs/` to GitHub — run after build (rsync `docs/` from compute if needed).
