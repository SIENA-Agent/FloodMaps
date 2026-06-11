#!/usr/bin/env python3
"""Transfer latest SIENA daily ZIPs from Zaratan → Mac, unzip, copy RGB GeoTIFFs to geotiffs/.

Fast alternative to recursive Globus listing of SIENA_result.

Flow:
  1. globus ls ZIP/SIENA/ (one level — fast)
  2. Pick latest N zip files by date in filename (default 2)
  3. globus transfer → geotiffs/.zip-staging/incoming/
  4. globus task wait
  5. unzip → extract RGB tifs → geotiffs/ → cleanup zip + extract tree
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from config_loader import load_globus_config

ROOT = Path(__file__).resolve().parents[2]
ZIP_DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})\.zip$", re.I)
TASK_UUID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
    re.I,
)
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.I,
)

# User production naming; also matches *_RGB_*.tif from Zaratan sync script.
RGB_NAME_MARKERS = ("_2classes_RGB", "_RGB_")


def require_globus() -> None:
    try:
        subprocess.run(["globus", "whoami"], check=True, capture_output=True, text=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise SystemExit(
            "globus CLI not ready — run: pip install 'globus-cli' && globus login"
        ) from exc


def globus_ls(endpoint: str, remote_dir: str) -> list[str]:
    remote_dir = remote_dir.rstrip("/")
    spec = f"{endpoint}:{remote_dir}/"
    proc = subprocess.run(
        ["globus", "ls", spec, "--format", "unix"],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit(f"globus ls failed for {spec}\n{proc.stderr or proc.stdout}")
    names = []
    for raw in proc.stdout.splitlines():
        name = raw.strip().rstrip("/")
        if name and name not in (".", ".."):
            names.append(name)
    return names


def parse_zip_dates(names: list[str]) -> list[tuple[str, str]]:
    """Return [(YYYY-MM-DD, filename), ...] sorted newest first."""
    dated: list[tuple[str, str]] = []
    for name in names:
        match = ZIP_DATE_RE.match(name)
        if match:
            dated.append((match.group(1), name))
    dated.sort(key=lambda x: x[0], reverse=True)
    return dated


def is_rgb_tif(path: Path) -> bool:
    if path.suffix.lower() not in (".tif", ".tiff"):
        return False
    return any(marker in path.name for marker in RGB_NAME_MARKERS)


def submit_batch_transfer(
    pairs: list[tuple[str, str]], label: str
) -> str | None:
    if not pairs:
        return None
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False, encoding="utf-8"
    ) as batch:
        for src, dst in pairs:
            batch.write(f"{src} {dst}\n")
        batch_path = batch.name

    proc = subprocess.run(
        [
            "globus",
            "transfer",
            "--batch",
            batch_path,
            "--label",
            label,
            "--notify",
            "on",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    os.unlink(batch_path)
    out = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0:
        raise SystemExit(f"globus transfer --batch failed:\n{out}")
    match = TASK_UUID_RE.search(out)
    return match.group(0) if match else None


def wait_task(task_id: str, log_path: Path | None) -> None:
    proc = subprocess.run(
        ["globus", "task", "wait", task_id],
        capture_output=True,
        text=True,
        check=False,
    )
    text = (proc.stdout or "") + (proc.stderr or "")
    if log_path:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(text, encoding="utf-8")
    if proc.returncode != 0:
        raise SystemExit(f"globus task wait failed for {task_id}:\n{text}")


def extract_rgb_tifs(zip_path: Path, extract_dir: Path, geotiff_dir: Path) -> int:
    extract_dir.mkdir(parents=True, exist_ok=True)
    copied = 0
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(extract_dir)
    for tif in extract_dir.rglob("*"):
        if not tif.is_file() or not is_rgb_tif(tif):
            continue
        dest = geotiff_dir / tif.name
        shutil.copy2(tif, dest)
        copied += 1
    return copied


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--zip-count",
        type=int,
        default=int(os.environ.get("ZIP_SYNC_COUNT", "2")),
        help="How many latest daily zips to sync (default: 2)",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-transfer", action="store_true", help="Only process zips already in incoming/")
    parser.add_argument("--force", action="store_true", help="Re-process even if .done marker exists")
    args = parser.parse_args()

    load_globus_config()

    floodmaps_root = Path(os.environ.get("FLOODMAPS_ROOT", str(ROOT)))
    geotiff_dir = Path(os.environ.get("MAC_GEOTIFF_DIR", floodmaps_root / "geotiffs"))
    zip_base = os.environ.get(
        "SIENA_ZIP_BASE",
        "/scratch/zt1/project/henryqy-prj/shared/data/routine_production/ZIP/SIENA",
    )
    src_ep = os.environ.get("GLOBUS_SRC_ENDPOINT", "")
    dst_ep = os.environ.get("GLOBUS_DST_ENDPOINT", "")
    log_dir = Path(os.environ.get("GLOBUS_LOG_DIR", floodmaps_root / "logs/globus"))

    staging = geotiff_dir / ".zip-staging"
    incoming = staging / "incoming"
    extract_root = staging / "extract"
    done_dir = staging / "done"

    for name, val in (
        ("GLOBUS_SRC_ENDPOINT", src_ep),
        ("GLOBUS_DST_ENDPOINT", dst_ep),
    ):
        if not val or val.startswith("REPLACE_WITH_") or not UUID_RE.match(val):
            raise SystemExit(f"Set {name} in scripts/globus/env.config.local.sh")

    geotiff_dir.mkdir(parents=True, exist_ok=True)
    incoming.mkdir(parents=True, exist_ok=True)
    extract_root.mkdir(parents=True, exist_ok=True)
    done_dir.mkdir(parents=True, exist_ok=True)

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_path = log_dir / f"sync_zip_{stamp}.log"

    print("=== SIENA ZIP → Mac geotiffs ===")
    print(f"time:       {datetime.now(timezone.utc).isoformat()}")
    print(f"zip remote: {src_ep}:{zip_base}")
    print(f"geotiffs:   {geotiff_dir}")
    print(f"latest:     {args.zip_count} zip file(s)")
    print(f"staging:    {staging}")
    print()

    if not args.skip_transfer:
        require_globus()
        print("Listing remote ZIP folder…")
        remote_names = globus_ls(src_ep, zip_base)
        dated = parse_zip_dates(remote_names)
        if not dated:
            raise SystemExit(f"No YYYY-MM-DD.zip files found under {zip_base}")
        selected = dated[: args.zip_count]
        print(f"  remote zips: {len(dated)} dated archive(s)")
        for day, name in selected:
            print(f"  → {name} ({day})")

        transfer_pairs: list[tuple[str, str]] = []
        for _day, name in selected:
            marker = done_dir / f"{name}.done"
            local_zip = incoming / name
            if marker.is_file() and not args.force:
                print(f"  skip transfer (done): {name}")
                continue
            if local_zip.is_file() and not args.force:
                print(f"  skip transfer (already in incoming): {name}")
                continue
            src = f"{src_ep}:{zip_base.rstrip('/')}/{name}"
            dst = f"{dst_ep}:{local_zip}"
            transfer_pairs.append((src, dst))

        if args.dry_run:
            print()
            print(f"DRY RUN — would transfer {len(transfer_pairs)} zip(s), then unzip/copy")
            return

        if transfer_pairs:
            print()
            print(f"Submitting Globus transfer ({len(transfer_pairs)} zip(s))…")
            task_id = submit_batch_transfer(
                transfer_pairs, label=f"FloodMaps-zip-{stamp}"
            )
            if not task_id:
                raise SystemExit("Could not parse Globus task ID")
            print(f"  task: {task_id}")
            print("  waiting for transfer…")
            wait_task(task_id, log_path)
            print("  transfer complete.")
        else:
            print()
            print("No new zips to transfer.")
    elif args.dry_run:
        print("DRY RUN — skip-transfer mode")
        return

    # Process all zips in incoming/ (selected latest N by date if multiple present)
    local_zips = sorted(
        [p for p in incoming.glob("*.zip") if ZIP_DATE_RE.match(p.name)],
        key=lambda p: p.name,
        reverse=True,
    )[: args.zip_count]

    if not local_zips:
        print("No zip files in incoming/ to process.")
        return

    total_copied = 0
    print()
    print("Processing zips (unzip → copy RGB → cleanup)…")
    for zip_path in local_zips:
        marker = done_dir / f"{zip_path.name}.done"
        if marker.is_file() and not args.force:
            print(f"  skip process (done): {zip_path.name}")
            continue

        day = ZIP_DATE_RE.match(zip_path.name).group(1)  # type: ignore[union-attr]
        extract_dir = extract_root / day
        if extract_dir.exists():
            shutil.rmtree(extract_dir)

        print(f"  unzip: {zip_path.name}")
        try:
            n = extract_rgb_tifs(zip_path, extract_dir, geotiff_dir)
        except zipfile.BadZipFile as exc:
            raise SystemExit(f"Bad zip file: {zip_path}") from exc

        zip_path.unlink(missing_ok=True)
        shutil.rmtree(extract_dir, ignore_errors=True)
        marker.write_text(
            f"processed {datetime.now(timezone.utc).isoformat()} copied={n}\n",
            encoding="utf-8",
        )
        total_copied += n
        print(f"    copied {n} RGB .tif → geotiffs/")

    total_local = len(list(geotiff_dir.glob("*.tif")))
    print()
    print(f"Done. RGB files this run: {total_copied}")
    print(f"geotiffs/ total: {total_local} .tif file(s)")
    print(f"log: {log_path}")
    print(f"Next: cd {floodmaps_root} && ./scripts/build.sh && ./scripts/publish.sh")


if __name__ == "__main__":
    main()
