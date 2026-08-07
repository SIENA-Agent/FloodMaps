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

ensure_publish_env() {
  if [[ -n "${PYTHON:-}" ]] && command -v "$PYTHON" >/dev/null 2>&1; then
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
    return
  fi
  if command -v python >/dev/null 2>&1; then
    PYTHON=python
    return
  fi
  local mac_env="${ROOT}/scripts/mac/load_mac_env.sh"
  if [[ -f "$mac_env" ]]; then
    # shellcheck disable=SC1091
    source "$mac_env"
  fi
  if command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
  elif command -v python >/dev/null 2>&1; then
    PYTHON=python
  else
    echo "ERROR: python3 not found — run via scripts/mac/orchestrate_build_publish.sh or set PATH." >&2
    exit 1
  fi
}

ensure_publish_env

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
GRANULES="$("$PYTHON" -c "import json; print(json.load(open('${CATALOG}'))['product_count'])")"

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

# Large incremental publishes: disable rename detection on all git ops in gh-pages.
GIT_CFG=(
  -c diff.renames=false
  -c diff.renameLimit=0
  -c status.renames=false
)

gitw() {
  git "${GIT_CFG[@]}" "$@"
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
"$PYTHON" "${ROOT}/scripts/publish_stage.py" \
  --catalog "$CATALOG" \
  --state-dir "$STATE_DIR" \
  --work-tree "${GIT_WORK_TREE}" \
  --origin-url "$REMOTE" \
  --mode "$PUBLISH_MODE" \
  --summary-out "$STAGE_SUMMARY"
log_phase "stage done ($(( $(date +%s) - t0 ))s)"

STAGED_MODE="$("$PYTHON" -c "import json; print(json.load(open('${STAGE_SUMMARY}'))['mode'])")"
ADDED_COUNT="$("$PYTHON" -c "import json; print(len(json.load(open('${STAGE_SUMMARY}'))['added']))")"
REMOVED_COUNT="$("$PYTHON" -c "import json; print(len(json.load(open('${STAGE_SUMMARY}'))['removed']))")"

COMMIT_MSG="Deploy ${STAMP} — ${GRANULES} granules (${PNG_COUNT} PNGs)"
if [[ "$STAGED_MODE" == "incremental" ]]; then
  COMMIT_MSG="Deploy ${STAMP} — +${ADDED_COUNT} -${REMOVED_COUNT} granules (${GRANULES} total)"
fi

# Large incremental publishes: skip rename detection (saves hours on ~10k+ file diffs).
GIT_COMMIT_CFG=(
  "${GIT_CFG[@]}"
  -c user.name="${GIT_AUTHOR_NAME:-SIENA Flood Maps}"
  -c user.email="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}"
)

log_phase "git commit …"
t0="$(date +%s)"
if gitw diff --cached --quiet && ! gitw rev-parse --verify HEAD >/dev/null 2>&1; then
  gitw "${GIT_COMMIT_CFG[@]}" commit -m "$COMMIT_MSG"
elif gitw diff --cached --quiet; then
  gitw "${GIT_COMMIT_CFG[@]}" commit --allow-empty -m "$COMMIT_MSG (unchanged)"
else
  gitw "${GIT_COMMIT_CFG[@]}" commit -m "$COMMIT_MSG"
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

# No catalog/tile changes — skip stamp + Actions (avoids flaky no-op Pages deploys).
SITE_UNCHANGED=0
if [[ "$STAGED_MODE" == "incremental" && "$ADDED_COUNT" == "0" && "$REMOVED_COUNT" == "0" ]]; then
  SITE_UNCHANGED=1
fi

# deploy-pages uses GITHUB_SHA from the workflow ref (main). If main never moves,
# GitHub Pages can report success while keeping the previous live artifact.
# Bump a stamp on main so each deploy gets a unique pages_build_version.
bump_pages_deploy_stamp() {
  local stamp_file="${ROOT}/.github/pages-deploy-stamp"
  local full_sha
  full_sha="$(gitw rev-parse HEAD)"
  mkdir -p "${ROOT}/.github"
  printf '%s %s\n' "$full_sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$stamp_file"

  # publish.sh sets GIT_DIR to the gh-pages worktree — use main repo explicitly.
  if ! (
    unset GIT_DIR GIT_WORK_TREE
    cd "$ROOT"
    git add .github/pages-deploy-stamp .github/workflows/pages.yml 2>/dev/null || git add .github/pages-deploy-stamp
    if git diff --cached --quiet; then
      return 0
    fi
    git -c user.name="${GIT_AUTHOR_NAME:-SIENA Flood Maps}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-siena-floodmaps@users.noreply.github.com}" \
      commit -m "chore: pages deploy stamp ${DEPLOY_SHA}"
    # Prefer SSH (matches origin); HTTPS token can print harmless "failed to store: -61".
    export GIT_TERMINAL_PROMPT=0
    if git remote get-url origin 2>/dev/null | grep -qE '^git@|^ssh://'; then
      git push origin HEAD:main
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
      git -c credential.helper= push \
        "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_SLUG}.git" HEAD:main
    else
      git push origin HEAD:main
    fi
  ); then
    echo "WARNING: could not bump pages-deploy-stamp on main (live site may stay stale)." >&2
    return 1
  fi
  echo "Bumped pages-deploy-stamp on main (unique deploy version)."
  return 0
}

gh_auth_env() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    GH_TOKEN="$GITHUB_TOKEN"
    export GH_TOKEN
  fi
}

cancel_stale_pages_runs() {
  # Cancel waiting/queued Pages runs so a new dispatch is not blocked for hours.
  if ! command -v gh >/dev/null 2>&1; then
    return 0
  fi
  gh_auth_env
  local ids
  ids="$(
    gh run list --workflow=pages.yml --repo "$REPO_SLUG" --limit 10 \
      --json databaseId,status \
      -q '.[] | select(.status=="queued" or .status=="pending" or .status=="waiting") | .databaseId' \
      2>/dev/null || true
  )"
  if [[ -z "$ids" ]]; then
    return 0
  fi
  local id
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "Cancelling stale Pages run ${id} (status queued/pending/waiting)…"
    gh run cancel "$id" --repo "$REPO_SLUG" >/dev/null 2>&1 || true
  done <<<"$ids"
}

wait_for_run() {
  # Portable gh run watch (macOS has no GNU timeout by default).
  local run_id="$1"
  local max_sec="$2"
  local deadline=$(( $(date +%s) + max_sec ))
  local status conclusion
  local waiting_since=0

  while [[ $(date +%s) -lt $deadline ]]; do
    read -r status conclusion < <(
      gh run view "$run_id" --repo "$REPO_SLUG" \
        --json status,conclusion -q '[.status, (.conclusion // "")] | @tsv' 2>/dev/null || echo $'\t'
    )
    if [[ "$status" == "completed" ]]; then
      if [[ "$conclusion" == "success" ]]; then
        return 0
      fi
      echo "Pages deploy run ${run_id} finished: ${conclusion:-unknown}" >&2
      return 1
    fi
    # Environment "waiting" / concurrency queue — fail early so we can re-dispatch.
    if [[ "$status" == "waiting" || "$status" == "pending" || "$status" == "queued" ]]; then
      waiting_since=$((waiting_since + 15))
      if [[ "$waiting_since" -ge 300 ]]; then
        echo "Pages deploy run ${run_id} stuck in ${status} for ${waiting_since}s — treating as failed." >&2
        gh run cancel "$run_id" --repo "$REPO_SLUG" >/dev/null 2>&1 || true
        return 1
      fi
    else
      waiting_since=0
    fi
    sleep 15
  done
  echo "Timed out waiting for Pages deploy run ${run_id} (${max_sec}s)." >&2
  return 124
}

find_pages_run_after() {
  local not_before="$1"
  "$PYTHON" - "$not_before" "$REPO_SLUG" <<'PY'
import json, subprocess, sys
from datetime import datetime, timezone

not_before = int(sys.argv[1])
repo = sys.argv[2]
out = subprocess.run(
    ["gh", "run", "list", "--workflow=pages.yml", "--repo", repo, "--limit", "8", "--json", "databaseId,createdAt,event"],
    capture_output=True, text=True, check=False,
)
if out.returncode != 0:
    sys.exit(0)
for row in json.loads(out.stdout or "[]"):
    if row.get("event") != "workflow_dispatch":
        continue
    created = datetime.fromisoformat(row["createdAt"].replace("Z", "+00:00"))
    if created.timestamp() >= not_before - 30:
        print(row["databaseId"])
        break
PY
}

wait_for_pages_deploy() {
  # Poll the workflow triggered by publish.sh; on real failure bump stamp + re-dispatch once.
  if ! command -v gh >/dev/null 2>&1; then
    return 0
  fi
  gh_auth_env
  if ! gh auth status >/dev/null 2>&1 && [[ -z "${GITHUB_TOKEN:-}" ]]; then
    return 0
  fi

  local rounds="${PAGES_DEPLOY_RETRY_ROUNDS:-1}"
  local wait_sec="${PAGES_DEPLOY_WAIT_SEC:-900}"
  local round run_id dispatch_at

  dispatch_at="${PAGES_DEPLOY_DISPATCH_AT:-$(date +%s)}"
  for ((round = 1; round <= rounds + 1; round++)); do
    sleep 12
    run_id="$(find_pages_run_after "$((dispatch_at - 30))" | head -1)"
    if [[ -z "$run_id" ]]; then
      echo "WARNING: could not find Pages workflow run to watch." >&2
      return 0
    fi
    echo "Watching Pages deploy run ${run_id} (round ${round}/$((rounds + 1)), timeout ${wait_sec}s)…"
    if wait_for_run "$run_id" "$wait_sec"; then
      echo "Pages deploy succeeded."
      return 0
    fi
    if (( round > rounds )); then
      echo "WARNING: Pages deploy failed after $((rounds + 1)) workflow attempt(s)." >&2
      echo "  gh-pages is updated; re-run: gh workflow run pages.yml --repo ${REPO_SLUG}" >&2
      return 1
    fi
    echo "Pages deploy failed — bumping stamp and re-dispatching (round $((round + 1)))…"
    bump_pages_deploy_stamp || true
    dispatch_at="$(date +%s)"
    PAGES_DEPLOY_DISPATCH_AT="$dispatch_at"
    trigger_deploy_workflow || return 1
  done
  return 1
}

trigger_deploy_workflow() {
  # Non-interactive (cron): GITHUB_TOKEN from ~/.config/floodmaps/credentials.env
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    if command -v gh >/dev/null 2>&1; then
      echo "Triggering Deploy GitHub Pages workflow (GITHUB_TOKEN + gh)…"
      if GH_TOKEN="$GITHUB_TOKEN" gh workflow run pages.yml --repo "$REPO_SLUG" --ref main; then
        return 0
      fi
      echo "gh workflow trigger failed — trying GitHub API…" >&2
    fi
    echo "Triggering Deploy GitHub Pages workflow (GITHUB_TOKEN)…"
    if curl -sf -X POST \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${REPO_SLUG}/actions/workflows/pages.yml/dispatches" \
      -d '{"ref":"main"}' >/dev/null; then
      return 0
    fi
    echo "ERROR: GITHUB_TOKEN rejected (check PAT scopes: Contents + Actions on ${REPO_SLUG})." >&2
    return 1
  fi

  # Interactive Mac: gh auth login (Keychain — not available to cron)
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "Triggering Deploy GitHub Pages workflow (gh)…"
    if gh workflow run pages.yml --repo "$REPO_SLUG" --ref main; then
      return 0
    fi
    echo "ERROR: gh workflow trigger failed." >&2
    return 1
  fi

  return 1
}

if [[ "$SITE_UNCHANGED" -eq 1 ]]; then
  echo "No granule changes — skipping Pages deploy (live site already current)."
else
  bump_pages_deploy_stamp || true

  cancel_stale_pages_runs || true
  if trigger_deploy_workflow; then
    PAGES_DEPLOY_DISPATCH_AT="$(date +%s)"
    echo "Deploy workflow started — usually live in 3–5 min for ~300MB sites."
    wait_for_pages_deploy || true
  else
    echo "WARNING: gh-pages pushed but deploy workflow was NOT started." >&2
    echo "  Mac:  gh auth login" >&2
    echo "  HPC:  ~/.config/floodmaps/credentials.env" >&2
    echo "  Or:   export GITHUB_TOKEN=<PAT>" >&2
    echo "  Or:   Actions → Deploy GitHub Pages → Run workflow" >&2
  fi
fi

echo "  Actions: https://github.com/${REPO_SLUG}/actions"
echo "  Site:    https://siena-agent.github.io/FloodMaps/"
