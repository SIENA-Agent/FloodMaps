#!/usr/bin/env bash
# Deploy pre-built docs/ to gh-pages and trigger GitHub Actions deploy.
set -euo pipefail

cleanup_pidfile() {
  if [[ -n "${FLOODMAPS_PUBLISH_PIDFILE:-}" && -f "${FLOODMAPS_PUBLISH_PIDFILE}" ]]; then
    rm -f "${FLOODMAPS_PUBLISH_PIDFILE}"
  fi
}
trap cleanup_pidfile EXIT

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

REPO_SLUG="$(
  printf '%s' "$REMOTE" | sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$#\1#'
)"

# Staging on scratch (same FS as docs/) — avoids copying 300k+ PNGs to login-node /tmp.
GH_PAGES_STAGING="${GH_PAGES_STAGING_DIR:-${ROOT}/.gh-pages-staging}"

# Load token before git push (HPC: ~/.config/floodmaps/credentials.env)
# shellcheck disable=SC1091
source "${ROOT}/scripts/load_github_credentials.sh"

log_phase() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

git_push_gh_pages() {
  local remote="$1"
  # SSH remote — use as-is (HPC: add SSH key to SIENA-Agent account)
  if [[ "$remote" =~ ^git@github\.com: ]] || [[ "$remote" =~ ^ssh:// ]]; then
    git push -f "$remote" HEAD:gh-pages
    return
  fi
  # HTTPS + PAT — non-interactive push for HPC login nodes
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    export GIT_TERMINAL_PROMPT=0
    git push -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_SLUG}.git" HEAD:gh-pages
    return
  fi
  echo "ERROR: HTTPS git push needs GITHUB_TOKEN or an SSH remote." >&2
  echo "  Token: ~/.config/floodmaps/credentials.env" >&2
  echo "  Or:    git remote set-url origin git@github.com:${REPO_SLUG}.git" >&2
  exit 1
}

sync_docs_to_staging() {
  local src="${ROOT}/docs"
  local dst="${GH_PAGES_STAGING}"
  local t0 t1

  mkdir -p "$dst"
  log_phase "Staging docs/ → ${dst} …"

  if [[ -d "${dst}/.git" ]]; then
    find "$dst" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
  else
    rm -rf "${dst:?}"/*
  fi

  t0="$(date +%s)"
  # Hardlink copy on the same filesystem — near-instant vs a full data copy to /tmp.
  if cp -al "${src}/." "${dst}/" 2>/dev/null; then
    t1="$(date +%s)"
    log_phase "Staged via hardlinks ($((t1 - t0))s)"
    return
  fi

  log_phase "Hardlink copy unavailable — rsync fallback …"
  rsync -a --delete "${src}/" "${dst}/"
  t1="$(date +%s)"
  log_phase "Staged via rsync ($((t1 - t0))s)"
}

echo "=== SIENA Flood Maps — publish ==="
echo "Deploying docs/ (${GRANULES} granules, ${PNG_COUNT} PNGs) to gh-pages…"
echo "Staging dir: ${GH_PAGES_STAGING}"

sync_docs_to_staging

cd "$GH_PAGES_STAGING"

if [[ ! -d .git ]]; then
  log_phase "git init in staging dir …"
  git init -q
  git checkout -b gh-pages
elif [[ "$(git branch --show-current 2>/dev/null || true)" != "gh-pages" ]]; then
  git checkout -b gh-pages 2>/dev/null || git checkout gh-pages
fi

log_phase "git add …"
t0="$(date +%s)"
GIT_OPTIONAL_LOCKS=0 git add -A
log_phase "git add done ($(( $(date +%s) - t0 ))s)"

COMMIT_MSG="Deploy ${STAMP} — ${GRANULES} granules (${PNG_COUNT} PNGs)"
log_phase "git commit …"
t0="$(date +%s)"
if git diff --cached --quiet && ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  git -c user.name="${GIT_AUTHOR_NAME:-SIENA Flood Maps}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}" \
      commit -m "$COMMIT_MSG"
elif git diff --cached --quiet; then
  git -c user.name="${GIT_AUTHOR_NAME:-SIENA Flood Maps}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}" \
      commit --allow-empty -m "$COMMIT_MSG (unchanged)"
else
  git -c user.name="${GIT_AUTHOR_NAME:-SIENA Flood Maps}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}" \
      commit -m "$COMMIT_MSG"
fi
log_phase "git commit done ($(( $(date +%s) - t0 ))s)"

DEPLOY_SHA="$(git rev-parse --short HEAD)"
log_phase "git push …"
t0="$(date +%s)"
git_push_gh_pages "$REMOTE"
log_phase "git push done ($(( $(date +%s) - t0 ))s)"

cd "$ROOT"

echo ""
echo "Pushed gh-pages (${DEPLOY_SHA})."

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
  echo "  Mac:  gh auth login" >&2
  echo "  HPC:  ~/.config/floodmaps/credentials.env  (see scripts/Zaratan/credentials.env.example)" >&2
  echo "  Or:   export GITHUB_TOKEN=<PAT>" >&2
  echo "  Or:   Actions → Deploy GitHub Pages → Run workflow" >&2
fi

echo "  Actions: https://github.com/${REPO_SLUG}/actions"
echo "  Site:    https://siena-agent.github.io/FloodMaps/"
