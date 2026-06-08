# GitHub Pages notes

See [README.md](README.md) for setup and update instructions.

## Deploy model (Model C)

| Branch | Role |
|--------|------|
| `main` | Scripts and viewer source only |
| `gh-pages` | Built site (tiles + catalog), force-replaced each `./scripts/publish.sh` |

**Pages source:** Settings → Pages → **Deploy from branch** → `gh-pages` / `/(root)`.

No GitHub Actions workflow required. No PNG tiles in `main` history.

## Automatic updates (~30 min)

HPC cron runs `./scripts/publish.sh` after refreshing `geotiffs/`. Only `gh-pages` is updated; `main` stays unchanged.

## Limits

- Repo `main` size: ~1 MB (scripts)
- `gh-pages` branch: ~40–450 MB depending on granule retention
- Max file size: 100 MB per file (granules are ~0.5–0.7 MB each)
