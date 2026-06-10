#!/usr/bin/env bash
# Deploy pre-built docs/ to gh-pages and trigger GitHub Actions deploy.
#
# Uses docs/ as git work-tree (no copy to staging). Incremental by default:
# only added/removed granule tile dirs + site metadata are staged.
#
# Mac bootstrap (first full site):
#   PUBLISH_FULL=1 ./scripts/publish.sh
#   # or: ./scripts/publish.sh --full
#
# HPC routine update (after git pull + build):
#   ./scripts/publish.sh
#
set -euo pipefail

cleanup_pidfile() {
  if [[ -n "${FLOODMAPS_PUBLISH_PIDFILE:-}" && -f "${FLOODMAPS_PUBLISH_PIDFILE}" ]]; then
    rm -f "${FLOODMAPS_PUBLISH_PIDFILE}"
  fi
}
trap cleanup_pidfile EXIT

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PUBLISH_MODE="${PUBLISH_MODE:-auto}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) PUBLISH_MODE=full; shift ;;
    --incremental) PUBLISH_MODE=incremental; shift ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done
[[ "${PUBLISH_FULL:-}" == 1 ]] && PUBLISH_MODE=full

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

STATE_DIR="${GH_PAGES_STATE_DIR:-${ROOT}/.gh-pages-staging}"
GIT_DIR="${GH_PAGES_GIT_DIR:-${STATE_DIR}/.git}"
export GIT_DIR
export GIT_WORK_TREE="${ROOT}/docs"

# Load token before git push (HPC: ~/.config/floodmaps/credentials.env)
# shellcheck disable=SC1091
source "${ROOT}/scripts/load_github_credentials.sh"

log_phase() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

gitw() {
  git "$@"
}

git_push_gh_pages() {
  local remote="$1"
  if [[ "$remote" =~ ^git@github\.com: ]] || [[ "$remote" =~ ^ssh:// ]]; then
    gitw push -f "$remote" HEAD:gh-pages
    return
  fi
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    export GIT_TERMINAL_PROMPT=0
    gitw push -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_SLUG}.git" HEAD:gh-pages
    return
  fi
  echo "ERROR: HTTPS git push needs GITHUB_TOKEN or an SSH remote." >&2
  echo "  Token: ~/.config/floodmaps/credentials.env" >&2
  echo "  Or:    git remote set-url origin git@github.com:${REPO_SLUG}.git" >&2
  exit 1
}

echo "=== SIENA Flood Maps — publish ==="
echo "Deploying docs/ (${GRANULES} granules, ${PNG_COUNT} PNGs) to gh-pages…"
echo "Work-tree: ${GIT_WORK_TREE}"
echo "Git dir:   ${GIT_DIR}"
echo "Mode:      ${PUBLISH_MODE}"

STAGE_SUMMARY="${STATE_DIR}/stage_summary.json"

log_phase "stage (catalog diff) …"
t0="$(date +%s)"
python "${ROOT}/scripts/publish_stage.py" \
  --catalog "$CATALOG" \
  --state-dir "$STATE_DIR" \
  --work-tree "${GIT_WORK_TREE}" \
  --origin-url "$REMOTE" \
  --mode "$PUBLISH_MODE" \
  --summary-out "$STAGE_SUMMARY"
log_phase "stage done ($(( $(date +%s) - t0 ))s)"

STAGED_MODE="$(python -c "import json; print(json.load(open('${STAGE_SUMMARY}'))['mode'])")"
ADDED_COUNT="$(python -c "import json; print(len(json.load(open('${STAGE_SUMMARY}'))['added']))")"
REMOVED_COUNT="$(python -c "import json; print(len(json.load(open('${STAGE_SUMMARY}'))['removed']))")"

COMMIT_MSG="Deploy ${STAMP} — ${GRANULES} granules (${PNG_COUNT} PNGs)"
if [[ "$STAGED_MODE" == "incremental" ]]; then
  COMMIT_MSG="Deploy ${STAMP} — +${ADDED_COUNT} -${REMOVED_COUNT} granules (${GRANULES} total)"
fi

log_phase "git commit …"
t0="$(date +%s)"
if gitw diff --cached --quiet && ! gitw rev-parse --verify HEAD >/dev/null 2>&1; then
  gitw -c user.name="${GIT_AUTHOR_NAME:-SIENA Flood Maps}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}" \
      commit -m "$COMMIT_MSG"
elif gitw diff --cached --quiet; then
  gitw -c user.name="${GIT_AUTHOR_NAME:-SIENA Flood Maps}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}" \
      commit --allow-empty -m "$COMMIT_MSG (unchanged)"
else
  gitw -c user.name="${GIT_AUTHOR_NAME:-SIENA Flood Maps}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}" \
      commit -m "$COMMIT_MSG"
fi
log_phase "git commit done ($(( $(date +%s) - t0 ))s)"

DEPLOY_SHA="$(gitw rev-parse --short HEAD)"
log_phase "git push …"
t0="$(date +%s)"
git_push_gh_pages "$REMOTE"
log_phase "git push done ($(( $(date +%s) - t0 ))s)"

mkdir -p "$STATE_DIR"
cp "$CATALOG" "${STATE_DIR}/last_catalog.json"

echo ""
echo "Pushed gh-pages (${DEPLOY_SHA}, mode=${STAGED_MODE})."

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
  echo "  HPC:  ~/.config/floodmaps/credentials.env" >&2
  echo "  Or:   export GITHUB_TOKEN=<PAT>" >&2
  echo "  Or:   Actions → Deploy GitHub Pages → Run workflow" >&2
fi

echo "  Actions: https://github.com/${REPO_SLUG}/actions"
echo "  Site:    https://siena-agent.github.io/FloodMaps/"
