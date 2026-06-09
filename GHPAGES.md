# GitHub Pages notes

See [README.md](README.md) for setup and update instructions.

## Deploy model (Model C)

| Branch | Role |
|--------|------|
| `main` | Scripts and viewer source only |
| `gh-pages` | Built site (tiles + catalog), force-replaced each `./scripts/publish.sh` |

**Pages source (one-time):** Settings → Pages → **GitHub Actions** (not “Deploy from branch”).

`.github/workflows/pages.yml` is started by `./scripts/publish.sh` via **workflow_dispatch** (after pushing `gh-pages`). Requires `gh auth login` or `GITHUB_TOKEN` on the machine running publish.

Pushing `gh-pages` alone does **not** reliably trigger Actions — publish always calls the workflow explicitly.

## Automatic updates (~30 min)

HPC runs `./scripts/build.sh` on a compute node, then `./scripts/publish.sh` on the login node. Only `gh-pages` is updated; `main` stays unchanged.

## Limits

- Repo `main` size: ~1 MB (scripts)
- `gh-pages` branch: ~40–450 MB depending on granule retention
- Max file size: 100 MB per file (granules are ~0.5–0.7 MB each)
