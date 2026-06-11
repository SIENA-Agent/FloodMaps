#!/usr/bin/env python3
"""Sync SIENA *_RGB_*.tif from Zaratan SIENA_result to Mac geotiffs/ via Globus.

1. List remote RGB GeoTIFFs (recursive Globus ls on SIENA_result).
2. Keep last KEEP_DAYS by sensing date + demo dates (Dec 2025).
3. Transfer only files missing locally (flat geotiffs/<basename>.tif).
4. Prune local .tif outside the retention window (demo dates protected).

Requires: globus login, Globus Connect Personal running on Mac, env.config.local.sh
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

GLOBUS_PKG = Path(__file__).resolve().parent
if str(GLOBUS_PKG) not in sys.path:
    sys.path.insert(0, str(GLOBUS_PKG))

from siena_retention import (
    DEFAULT_DEMO_DATES,
    DEFAULT_KEEP_DAYS,
    cutoff_yyyymmdd,
    is_rgb_geotiff,
    sensing_date_from_name,
    should_keep_sensing_date,
)

ROOT = Path(__file__).resolve().parents[2]
GLOBUS_DIR = GLOBUS_PKG

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.I,
)


def load_shell_config() -> None:
    example = GLOBUS_DIR / "env.config.example.sh"
    local = GLOBUS_DIR / "env.config.local.sh"
    merged: dict[str, str] = {}
    for path in (example, local):
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export ") :]
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip().strip("'").strip('"')
            if key:
                merged[key] = val
    for key, val in merged.items():
        os.environ.setdefault(key, val)


def require_globus() -> None:
    try:
        subprocess.run(
            ["globus", "whoami"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise SystemExit(
            "globus CLI not ready — run: pip install 'globus-cli' && globus login"
        ) from exc


def globus_ls_recursive(endpoint: str, remote_dir: str) -> list[str]:
    """Return remote paths relative to remote_dir (no leading slash)."""
    remote_dir = remote_dir.rstrip("/")
    spec = f"{endpoint}:{remote_dir}/"
    proc = subprocess.run(
        ["globus", "ls", spec, "--recursive", "--format", "unix"],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit(
            f"globus ls failed for {spec}\n{proc.stderr or proc.stdout}"
        )
    lines = []
    for raw in proc.stdout.splitlines():
        line = raw.strip()
        if not line or line in (".", ".."):
            continue
        # globus may return paths with or without leading remote_dir prefix
        if line.startswith(remote_dir.lstrip("/")):
            rel = line[len(remote_dir.lstrip("/")) :].lstrip("/")
        else:
            rel = line.lstrip("/")
        lines.append(rel)
    return lines


def local_basenames(geotiff_dir: Path) -> set[str]:
    if not geotiff_dir.is_dir():
        return set()
    return {p.name for p in geotiff_dir.glob("*.tif")}


def remote_rgb_in_window(
    rel_paths: list[str],
    *,
    keep_days: int,
    demo_dates: tuple[str, ...],
) -> dict[str, str]:
    """Map basename -> remote relative path (folder/file.tif)."""
    selected: dict[str, str] = {}
    for rel in rel_paths:
        if not is_rgb_geotiff(rel):
            continue
        basename = rel.rsplit("/", 1)[-1]
        sdate = sensing_date_from_name(rel) or sensing_date_from_name(basename)
        if not sdate or not should_keep_sensing_date(
            sdate, keep_days=keep_days, demo_dates=demo_dates
        ):
            continue
        selected[basename] = rel
    return selected


def prune_local(
    geotiff_dir: Path,
    *,
    keep_days: int,
    demo_dates: tuple[str, ...],
    dry_run: bool,
) -> int:
    cutoff = cutoff_yyyymmdd(keep_days)
    pruned = 0
    for path in sorted(geotiff_dir.glob("*.tif")):
        sdate = sensing_date_from_name(path.name)
        if not sdate or sdate in demo_dates:
            continue
        if sdate < cutoff:
            pruned += 1
            print(f"  prune local: {path.name} (sensing {sdate} < {cutoff})")
            if not dry_run:
                path.unlink(missing_ok=True)
    return pruned


def submit_batch_transfer(
    pairs: list[tuple[str, str]],
    *,
    label: str,
    wait: bool,
    log_path: Path | None,
) -> str | None:
    if not pairs:
        return None

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False, encoding="utf-8"
    ) as batch:
        for src, dst in pairs:
            batch.write(f"{src} {dst}\n")
        batch_path = batch.name

    cmd = [
        "globus",
        "transfer",
        "--batch",
        batch_path,
        "--label",
        label,
        "--notify",
        "on",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    os.unlink(batch_path)

    out = (proc.stdout or "") + (proc.stderr or "")
    if log_path:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(out, encoding="utf-8")

    if proc.returncode != 0:
        raise SystemExit(f"globus transfer --batch failed:\n{out}")

    match = re.search(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        out,
        re.I,
    )
    task_id = match.group(0) if match else None
    if task_id and wait:
        subprocess.run(
            ["globus", "task", "wait", task_id],
            check=False,
        )
    return task_id


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="List actions only")
    parser.add_argument("--no-prune", action="store_true", help="Skip local prune")
    parser.add_argument("--wait", action="store_true", help="Wait for Globus task")
    parser.add_argument(
        "--keep-days",
        type=int,
        default=int(os.environ.get("KEEP_DAYS", DEFAULT_KEEP_DAYS)),
    )
    parser.add_argument(
        "--demo-dates",
        nargs="*",
        default=list(
            os.environ.get("KEEP_DEMO_DATES", " ".join(DEFAULT_DEMO_DATES)).split()
        ),
    )
    args = parser.parse_args()
    demo_dates = tuple(args.demo_dates)

    load_shell_config()

    floodmaps_root = Path(
        os.environ.get(
            "FLOODMAPS_ROOT",
            str(ROOT),
        )
    )
    geotiff_dir = Path(
        os.environ.get("MAC_GEOTIFF_DIR", floodmaps_root / "geotiffs")
    )
    siena_base = os.environ.get(
        "SIENA_OUTPUT_BASE",
        "/scratch/zt1/project/henryqy-prj/shared/data/routine_production/SIENA_result",
    )
    src_ep = os.environ.get("GLOBUS_SRC_ENDPOINT", "")
    dst_ep = os.environ.get("GLOBUS_DST_ENDPOINT", "")
    log_dir = Path(os.environ.get("GLOBUS_LOG_DIR", floodmaps_root / "logs/globus"))

    for name, val in (
        ("GLOBUS_SRC_ENDPOINT", src_ep),
        ("GLOBUS_DST_ENDPOINT", dst_ep),
    ):
        if not val or val.startswith("REPLACE_WITH_") or not UUID_RE.match(val):
            raise SystemExit(
                f"Set {name} in scripts/globus/env.config.local.sh "
                f"(run: bash scripts/globus/find_endpoints.sh)"
            )

    require_globus()
    geotiff_dir.mkdir(parents=True, exist_ok=True)

    cutoff = cutoff_yyyymmdd(args.keep_days)
    print("=== SIENA → Mac geotiffs (Globus) ===")
    print(f"time:        {datetime.now(timezone.utc).isoformat()}")
    print(f"remote:      {src_ep}:{siena_base}")
    print(f"local:       {geotiff_dir}")
    print(f"window:      sensing >= {cutoff} ({args.keep_days} days)")
    print(f"demo dates:  {' '.join(demo_dates)}")
    print()

    print("Listing remote SIENA_result (recursive Globus ls)…")
    rel_paths = globus_ls_recursive(src_ep, siena_base)
    print(f"  remote paths listed: {len(rel_paths)}")

    remote_map = remote_rgb_in_window(
        rel_paths, keep_days=args.keep_days, demo_dates=demo_dates
    )
    print(f"  RGB in retention window: {len(remote_map)}")

    local = local_basenames(geotiff_dir)
    missing = sorted(set(remote_map) - local)
    print(f"  local .tif count: {len(local)}")
    print(f"  missing on Mac:   {len(missing)}")

    if not args.no_prune:
        print()
        print("Pruning local files outside retention window…")
        pruned = prune_local(
            geotiff_dir,
            keep_days=args.keep_days,
            demo_dates=demo_dates,
            dry_run=args.dry_run,
        )
        print(f"  pruned: {pruned}")

    if not missing:
        print()
        print("Nothing to transfer — Mac geotiffs/ is up to date.")
        total = len(list(geotiff_dir.glob("*.tif")))
        print(f"geotiffs/ total: {total} .tif file(s)")
        return

    print()
    if len(missing) <= 5:
        for name in missing:
            print(f"  + {name}")
    else:
        for name in missing[:3]:
            print(f"  + {name}")
        print(f"  … +{len(missing) - 3} more")

    siena_base_clean = siena_base.rstrip("/")
    pairs: list[tuple[str, str]] = []
    for basename in missing:
        rel = remote_map[basename]
        src = f"{src_ep}:{siena_base_clean}/{rel}"
        dst = f"{dst_ep}:{geotiff_dir / basename}"
        pairs.append((src, dst))

    label = f"FloodMaps-sync-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
    log_path = log_dir / f"sync_{label}.log"

    if args.dry_run:
        print()
        print(f"DRY RUN — would transfer {len(pairs)} file(s)")
        print(f"  batch log would be: {log_path}")
        return

    print()
    print(f"Submitting Globus batch transfer ({len(pairs)} file(s))…")
    task_id = submit_batch_transfer(pairs, label=label, wait=args.wait, log_path=log_path)
    print(f"  log: {log_path}")
    if task_id:
        print(f"  task: {task_id}")
        print(f"  monitor: globus task wait {task_id}")
        print("           https://app.globus.org/activity")
    if args.wait:
        total = len(list(geotiff_dir.glob("*.tif")))
        print(f"geotiffs/ total: {total} .tif file(s)")
        print(f"Next: cd {floodmaps_root} && ./scripts/build.sh && ./scripts/publish.sh")


if __name__ == "__main__":
    main()
