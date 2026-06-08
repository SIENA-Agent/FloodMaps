#!/usr/bin/env python3
"""Scan geotiffs/ and write data/catalog.json."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import rasterio
from rasterio.warp import transform_bounds

ROOT = Path(__file__).resolve().parents[1]
SENTINEL_TIME = re.compile(r"(\d{8}T\d{6})_(\d{8}T\d{6})")


def parse_sentinel_times(filename: str) -> tuple[str | None, str | None]:
    match = SENTINEL_TIME.search(filename)
    if not match:
        return None, None
    return match.group(1), match.group(2)


def to_iso(sentinel_ts: str) -> str:
    dt = datetime.strptime(sentinel_ts, "%Y%m%dT%H%M%S").replace(tzinfo=timezone.utc)
    return dt.isoformat().replace("+00:00", "Z")


def build_catalog(tiff_dir: Path) -> dict:
    products = []
    for path in sorted(tiff_dir.glob("*.tif")):
        sensing_start, sensing_end = parse_sentinel_times(path.name)
        with rasterio.open(path) as dataset:
            west, south, east, north = transform_bounds(
                dataset.crs, "EPSG:4326", *dataset.bounds
            )
            center_lon = (west + east) / 2
            center_lat = (south + north) / 2

        products.append(
            {
                "id": path.stem,
                "filename": path.name,
                "sensing_start": to_iso(sensing_start) if sensing_start else None,
                "sensing_end": to_iso(sensing_end) if sensing_end else None,
                "sensing_date": sensing_start[:8] if sensing_start else None,
                "bounds": [west, south, east, north],
                "center": [center_lon, center_lat],
            }
        )

    dates = sorted({p["sensing_date"] for p in products if p["sensing_date"]})
    return {
        "version": 1,
        "description": "SIENA Sentinel-1 RGB flood classification GeoTIFF granules",
        "product_count": len(products),
        "available_dates": dates,
        "products": products,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--tiff-dir",
        type=Path,
        default=ROOT / "geotiffs",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "data" / "catalog.json",
    )
    args = parser.parse_args()

    if not any(args.tiff_dir.glob("*.tif")):
        raise SystemExit(f"No .tif files found in {args.tiff_dir}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    catalog = build_catalog(args.tiff_dir)
    args.output.write_text(json.dumps(catalog, indent=2), encoding="utf-8")
    print(
        f"Wrote {args.output} "
        f"({catalog['product_count']} products, {len(catalog['available_dates'])} dates)"
    )


if __name__ == "__main__":
    main()
