#!/usr/bin/env python3
"""
Build the GitHub Pages site into docs/.

Default mode: tiles — pre-bake PNG map tiles (production, low browser memory).
Optional: --mode geotiff for local experiments with viewport-scoped loading.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.render_tiles import bake_all_products

WEB = ROOT / "web"
DOCS = ROOT / "docs"


def run_build_catalog(tiff_dir: Path, catalog_path: Path) -> dict:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts" / "build_catalog.py"),
            "--tiff-dir",
            str(tiff_dir),
            "--output",
            str(catalog_path),
        ],
        check=True,
    )
    return json.loads(catalog_path.read_text(encoding="utf-8"))


def write_index(docs_dir: Path, mode: str, base_path: str, build_id: str) -> None:
    georaster_scripts = ""
    viewer_config = (
        f'window.FLOOD_VIEWER_CONFIG = {{ mode: "{mode}", dataRoot: "data/geotiffs/", '
        f'tileMinZoom: 3, tileMaxZoom: 10 }};'
    )
    if mode == "geotiff":
        georaster_scripts = """
    <script src="https://unpkg.com/georaster@1.6.0/dist/georaster.browser.bundle.min.js"></script>
    <script src="https://unpkg.com/georaster-layer-for-leaflet@3.10.0/dist/georaster-layer-for-leaflet.min.js"></script>"""

    html = f"""<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <base href="{base_path}" />
    <title>SIENA Flood Maps</title>
    <link
      rel="stylesheet"
      href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
      crossorigin=""
    />
    <link rel="stylesheet" href="css/viewer.css" />
  </head>
  <body>
    <div id="map"></div>

    <aside class="control-panel">
      <h1>SIENA Flood Maps</h1>
      <p class="demo-note">
        Interactive Sentinel-1 flood classification over <strong>OpenStreetMap</strong>.
        Select a sensing date; click a granule for metadata.
      </p>

      <div class="field">
        <label for="date-select">Sensing date</label>
        <select id="date-select"></select>
      </div>

      <div class="field">
        <label for="opacity">Overlay opacity</label>
        <input id="opacity" type="range" min="0.3" max="1" step="0.05" value="0.9" />
      </div>

      <p id="status" class="status-line">Starting…</p>

      <div id="granule-info" class="info-panel">
        <p class="info-hint">Click on a granule on the map for details.</p>
      </div>
    </aside>

    <section class="legend" aria-label="Class legend">
      <h2>Classes</h2>
      <div class="legend-item">
        <span class="swatch permanent-water"></span>
        <span>Permanent water (class 1)</span>
      </div>
      <div class="legend-item">
        <span class="swatch flood-water"></span>
        <span>Flood water (class 3)</span>
      </div>
      <p class="legend-note">Other pixels are transparent so the map base shows through.</p>
    </section>

    <section class="map-tools" aria-label="Map scale and zoom">
      <div class="scale-block">
        <span class="tools-label">Map scale</span>
        <div id="scale-bar" class="scale-bar" aria-hidden="true">
          <div id="scale-bar-line" class="scale-bar-line"></div>
          <span id="scale-bar-label" class="scale-bar-label">—</span>
        </div>
      </div>
      <div class="zoom-block">
        <label class="tools-label" for="zoom-slider">Zoom level <span id="zoom-value">4</span></label>
        <input id="zoom-slider" type="range" min="3" max="12" step="1" value="4" />
      </div>
      <p id="zoom-hint" class="tools-hint">Blue outlines show coverage when zoomed out.</p>
    </section>

    <script>{viewer_config}</script>
    <script
      src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
      integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
      crossorigin=""
    ></script>{georaster_scripts}
    <script src="js/catalog.js?v={build_id}"></script>
    <script src="js/viewer.js?v={build_id}"></script>
  </body>
</html>
"""
    (docs_dir / "index.html").write_text(html, encoding="utf-8")


def write_catalog_json(catalog: dict, output: Path) -> None:
    output.write_text(json.dumps(catalog, indent=2), encoding="utf-8")


def write_catalog_js(catalog: dict, output: Path) -> None:
    payload = json.dumps(catalog, separators=(",", ":"))
    output.write_text(f"window.FLOOD_CATALOG = {payload};\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tiff-dir", type=Path, default=ROOT / "geotiffs")
    parser.add_argument("--output", type=Path, default=DOCS)
    parser.add_argument(
        "--mode",
        choices=("tiles", "geotiff"),
        default="tiles",
        help="tiles (default): bake PNG tiles. geotiff: copy raw TIFFs for browser experiments.",
    )
    parser.add_argument("--workers", type=int, default=4, help="Parallel workers for tile baking")
    parser.add_argument(
        "--base-path",
        default="/FloodMaps/",
        help="GitHub Pages project base path (trailing slash required)",
    )
    args = parser.parse_args()

    catalog_path = ROOT / "data" / "catalog.json"
    catalog = run_build_catalog(args.tiff_dir, catalog_path)

    out = args.output
    if out.exists():
        shutil.rmtree(out)
    (out / "css").mkdir(parents=True)
    (out / "js").mkdir(parents=True)

    (out / "data").mkdir(parents=True)
    shutil.copy2(WEB / "css" / "viewer.css", out / "css" / "viewer.css")
    shutil.copy2(WEB / "js" / "viewer.js", out / "js" / "viewer.js")
    write_catalog_json(catalog, out / "data" / "catalog.json")
    write_catalog_js(catalog, out / "js" / "catalog.js")
    build_id = str(catalog["product_count"])
    write_index(out, args.mode, args.base_path, build_id)
    (out / ".nojekyll").write_text("", encoding="utf-8")

    tile_count = 0
    tile_bytes = 0
    tiff_bytes = 0

    if args.mode == "tiles":
        (out / "tiles").mkdir(parents=True)
        print(f"Baking tiles for {catalog['product_count']} granules…")
        tile_count = bake_all_products(
            catalog["products"],
            args.tiff_dir,
            out / "tiles",
            workers=args.workers,
        )
        for path in (out / "tiles").rglob("*.png"):
            tile_bytes += path.stat().st_size
    else:
        (out / "data" / "geotiffs").mkdir(parents=True)
        for tiff in sorted(args.tiff_dir.glob("*.tif")):
            dest = out / "data" / "geotiffs" / tiff.name
            shutil.copy2(tiff, dest)
            tiff_bytes += dest.stat().st_size

    print(f"Built {out}/  [mode={args.mode}]")
    print(f"  {catalog['product_count']} granules, {len(catalog['available_dates'])} date(s)")
    if args.mode == "tiles":
        print(f"  Tiles: {tile_count} PNGs ({tile_bytes / 1024 / 1024:.2f} MB)")
    else:
        print(f"  GeoTIFFs: {tiff_bytes / 1024 / 1024:.2f} MB")
    print(f"  Preview: python -m http.server 8080 --directory {out}")


if __name__ == "__main__":
    main()
