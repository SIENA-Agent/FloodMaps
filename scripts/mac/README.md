# Mac — sync, build, publish

One command runs the full Mac workflow in the **background**:

```bash
bash scripts/mac/orchestrate_build_publish.sh
```

Steps: `sync_geotiffs_from_zip.sh` → `build.sh` → `publish.sh`

## Local config (not in git)

```bash
cp scripts/globus/env.config.example.sh scripts/globus/env.config.local.sh
# set FLOODMAPS_ROOT, SIENA_ZIP_BASE, GLOBUS_* endpoints

# optional:
cp scripts/mac/env.config.example.sh scripts/mac/env.config.local.sh
```

## Monitor

```bash
tail -f logs/mac/pipeline_*.log
```

## Options

| Flag | Effect |
|------|--------|
| (default) | Background via `nohup` |
| `--foreground` | Run in current shell (used internally) |

Prerequisites: `pip install 'globus-cli'`, `globus login`, Globus Connect Personal running, `pip install -r requirements.txt`.
