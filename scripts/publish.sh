#!/usr/bin/env bash
# Deploy pre-built docs/ to gh-pages and trigger GitHub Actions deploy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git remote get-url origin &>/dev/null; then
  echo "No git remote 'origin' — add: git remote add origin <url>" >&2
  exit 1
fi

if [[ ! -f docs/index.html ]] || [[ ! -d docs/tiles ]]; then
  echo "docs/ is not built — run ./scripts/build.sh first." >&2
  exit 1
fi

PNG_COUNT="$(find docs/tiles -name '*.png' | wc -l | tr -d ' ')"
if [[ "$PNG_COUNT" -eq 0 ]]; then
  echo "docs/tiles/ has no PNG files — run ./scripts/build.sh first." >&2
  exit 1
fi

CATALOG="${ROOT}/data/catalog.json"
if [[ ! -f "$CATALOG" ]]; then
  CATALOG="${ROOT}/docs/data/catalog.json"
fi
if [[ ! -f "$CATALOG" ]]; then
  echo "catalog.json missing — run ./scripts/build.sh first." >&2
  exit 1
fi

REMOTE="$(git remote get-url origin)"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GRANULES="$(python -c "import json; print(json.load(open('${CATALOG}'))['product_count'])")"

# owner/repo from git@github.com:ORG/REPO.git or https://github.com/ORG/REPO.git
REPO_SLUG="$(
  printf '%s' "$REMOTE" | sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$#\1#'
)"

echo "=== SIENA Flood Maps — publish ==="
echo "Deploying docs/ (${GRANULES} granules, ${PNG_COUNT} PNGs) to gh-pages…"

WORKTREE="$(mktemp -d)"
cleanup() {
  cd "$ROOT"
  git worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"
  git branch -D gh-pages 2>/dev/null || true
}
trap cleanup EXIT

git branch -D gh-pages 2>/dev/null || true
git worktree add --orphan "$WORKTREE" gh-pages

rsync -a --delete "${ROOT}/docs/" "${WORKTREE}/"

cd "$WORKTREE"
git add -A
git -c user.name="${GIT_AUTHOR_NAME:-SIENA Flood Maps}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}" \
    commit -m "Deploy ${STAMP} — ${GRANULES} granules (${PNG_COUNT} PNGs)" --allow-empty

git push -f origin gh-pages

cd "$ROOT"

echo ""
echo "Pushed gh-pages ($(git -C "$WORKTREE" rev-parse --short HEAD 2>/dev/null || echo '?'))."

trigger_deploy_workflow() {
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "Triggering Deploy GitHub Pages workflow (gh)…"
    gh workflow run pages.yml --repo "$REPO_SLUG" --ref main
    return 0
  fi

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "Triggering Deploy GitHub Pages workflow (GITHUB_TOKEN)…"
    curl -sf -X POST \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${REPO_SLUG}/actions/workflows/pages.yml/dispatches" \
      -d '{"ref":"main"}' >/dev/null
    return 0
  fi

  return 1
}

if trigger_deploy_workflow; then
  echo "Deploy workflow started — usually live in 1–2 min."
else
  echo "WARNING: gh-pages pushed but deploy workflow was NOT started." >&2
  echo "  Push events to gh-pages do not reliably trigger Actions." >&2
  echo "  Fix (pick one):" >&2
  echo "    1. gh auth login   then re-run ./scripts/publish.sh" >&2
  echo "    2. export GITHUB_TOKEN=<PAT with Actions:write>" >&2
  echo "    3. GitHub → Actions → Deploy GitHub Pages → Run workflow" >&2
fi

echo "  Actions: https://github.com/${REPO_SLUG}/actions"
echo "  Site:    https://siena-agent.github.io/FloodMaps/"
