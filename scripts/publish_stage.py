#!/usr/bin/env python3
"""Stage docs/ for gh-pages deploy using GIT_DIR + GIT_WORK_TREE (no file copy).

Modes:
  auto        — incremental when last_catalog.json or origin/gh-pages exists, else full
  incremental — git add/rm only changed granule tile dirs + site metadata
  full        — git add -A (Mac bootstrap or recovery)
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SITE_PATHS = (
    ".nojekyll",
    "index.html",
    "css/viewer.css",
    "js/viewer.js",
    "js/catalog.js",
    "data/catalog.json",
)


def git_env(git_dir: Path, work_tree: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["GIT_DIR"] = str(git_dir)
    env["GIT_WORK_TREE"] = str(work_tree)
    return env


def run_git(env: dict[str, str], *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        env=env,
        text=True,
        capture_output=True,
        check=check,
    )


def product_ids(catalog: dict) -> set[str]:
    return {p["id"] for p in catalog["products"]}


def load_catalog(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def remote_has_gh_pages(env: dict[str, str]) -> bool:
    proc = run_git(env, "rev-parse", "origin/gh-pages", check=False)
    return proc.returncode == 0


def bootstrap_from_remote(env: dict[str, str], state_dir: Path) -> Path | None:
    """Seed last_catalog.json and git index/HEAD from origin/gh-pages (no work-tree checkout)."""
    if not remote_has_gh_pages(env):
        return None

    proc = run_git(env, "show", "origin/gh-pages:data/catalog.json", check=False)
    if proc.returncode != 0:
        return None

    last_path = state_dir / "last_catalog.json"
    last_path.write_text(proc.stdout, encoding="utf-8")

    tip = run_git(env, "rev-parse", "origin/gh-pages").stdout.strip()
    run_git(env, "read-tree", tip)
    run_git(env, "update-ref", "refs/heads/gh-pages", tip)
    run_git(env, "symbolic-ref", "HEAD", "refs/heads/gh-pages")
    return last_path


def ensure_repo(env: dict[str, str], state_dir: Path, origin_url: str) -> None:
    git_dir = Path(env["GIT_DIR"])
    if git_dir.exists():
        run_git(env, "fetch", "origin", "gh-pages", check=False)
        return

    state_dir.mkdir(parents=True, exist_ok=True)
    run_git(env, "init", "-b", "gh-pages")
    proc = run_git(env, "remote", "add", "origin", origin_url, check=False)
    if proc.returncode != 0:
        run_git(env, "remote", "set-url", "origin", origin_url, check=False)
    run_git(env, "fetch", "origin", "gh-pages", check=False)


def resolve_mode(
    mode: str,
    state_dir: Path,
    env: dict[str, str],
) -> tuple[str, Path | None]:
    last_path = state_dir / "last_catalog.json"

    if mode == "full":
        return "full", last_path if last_path.exists() else None

    if mode == "incremental":
        if not last_path.exists():
            boot = bootstrap_from_remote(env, state_dir)
            if boot is None:
                print(
                    "ERROR: incremental publish needs last_catalog.json or origin/gh-pages",
                    file=sys.stderr,
                )
                sys.exit(1)
            last_path = boot
        return "incremental", last_path

    # auto
    if last_path.exists():
        return "incremental", last_path
    boot = bootstrap_from_remote(env, state_dir)
    if boot is not None:
        return "incremental", boot
    return "full", None


def stage_full(env: dict[str, str]) -> tuple[list[str], list[str]]:
    run_git(env, "add", "-A")
    return [], []


def stage_incremental(
    env: dict[str, str],
    work_tree: Path,
    catalog: dict,
    last_catalog: dict,
) -> tuple[list[str], list[str]]:
    old_ids = product_ids(last_catalog)
    new_ids = product_ids(catalog)
    added = sorted(new_ids - old_ids)
    removed = sorted(old_ids - new_ids)

    for product_id in removed:
        run_git(env, "rm", "-rf", "--ignore-unmatch", f"tiles/{product_id}", check=False)

    for product_id in added:
        tile_dir = work_tree / "tiles" / product_id
        if not tile_dir.is_dir():
            print(f"WARNING: missing tiles for new granule: {product_id}", file=sys.stderr)
            continue
        run_git(env, "add", f"tiles/{product_id}")

    for rel in SITE_PATHS:
        path = work_tree / rel
        if path.exists():
            run_git(env, "add", rel)

    return added, removed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--catalog",
        type=Path,
        default=ROOT / "data" / "catalog.json",
    )
    parser.add_argument(
        "--state-dir",
        type=Path,
        default=ROOT / ".gh-pages-staging",
    )
    parser.add_argument(
        "--work-tree",
        type=Path,
        default=ROOT / "docs",
    )
    parser.add_argument(
        "--origin-url",
        required=True,
        help="Git remote URL for FloodMaps (from main repo origin)",
    )
    parser.add_argument(
        "--mode",
        choices=("auto", "incremental", "full"),
        default="auto",
    )
    parser.add_argument(
        "--summary-out",
        type=Path,
        default=None,
        help="Write JSON summary (mode, added, removed) for publish.sh",
    )
    args = parser.parse_args()

    if not args.catalog.is_file():
        fallback = args.work_tree / "data" / "catalog.json"
        if fallback.is_file():
            args.catalog = fallback
        else:
            raise SystemExit(f"catalog not found: {args.catalog}")

    git_dir = args.state_dir / ".git"
    env = git_env(git_dir, args.work_tree)

    ensure_repo(env, args.state_dir, args.origin_url)
    resolved_mode, last_path = resolve_mode(args.mode, args.state_dir, env)
    catalog = load_catalog(args.catalog)

    print(f"Publish stage mode: {resolved_mode}")

    if resolved_mode == "full":
        added, removed = stage_full(env)
        print(f"  staged: full tree ({catalog['product_count']} granules)")
    else:
        assert last_path is not None
        last_catalog = load_catalog(last_path)
        added, removed = stage_incremental(env, args.work_tree, catalog, last_catalog)
        print(f"  granules added:   {len(added)}")
        print(f"  granules removed: {len(removed)}")
        if added:
            print(f"    + {added[0]}" + (f" … +{len(added) - 1} more" if len(added) > 1 else ""))
        if removed:
            print(f"    - {removed[0]}" + (f" … -{len(removed) - 1} more" if len(removed) > 1 else ""))

    summary = {
        "mode": resolved_mode,
        "product_count": catalog["product_count"],
        "added": added,
        "removed": removed,
    }
    if args.summary_out is not None:
        args.summary_out.parent.mkdir(parents=True, exist_ok=True)
        args.summary_out.write_text(json.dumps(summary, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
