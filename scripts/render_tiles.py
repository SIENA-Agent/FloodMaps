"""Bake Web Mercator PNG tiles from palette GeoTIFFs for static hosting."""

from __future__ import annotations

import io
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import mercantile
import numpy as np
import rasterio
from PIL import Image
from rasterio.crs import CRS
from rasterio.enums import Resampling
from rasterio.transform import from_bounds
from rasterio.warp import reproject, transform_bounds

WEB_MERCATOR = CRS.from_epsg(3857)
TILE_SIZE = 256
MIN_ZOOM = 3
MAX_ZOOM = 10


def _intersects(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return not (a[2] <= b[0] or a[0] >= b[2] or a[3] <= b[1] or a[1] >= b[3])


def _apply_colormap(
    values: np.ndarray,
    colormap: dict[int, tuple[int, int, int, int]],
    transparent_values: tuple[int, ...] = (0, 255),
) -> np.ndarray:
    height, width = values.shape
    rgba = np.zeros((height, width, 4), dtype=np.uint8)
    for value, color in colormap.items():
        if value in transparent_values:
            continue
        mask = values == value
        if not np.any(mask):
            continue
        alpha = color[3] if len(color) > 3 else 255
        if alpha == 0:
            continue
        rgba[mask, 0] = color[0]
        rgba[mask, 1] = color[1]
        rgba[mask, 2] = color[2]
        rgba[mask, 3] = alpha
    for transparent in transparent_values:
        rgba[values == transparent, 3] = 0
    return rgba


def tiles_for_bounds(bounds_wgs84: list[float], min_zoom: int, max_zoom: int) -> list[mercantile.Tile]:
    west, south, east, north = bounds_wgs84
    seen: set[tuple[int, int, int]] = set()
    tiles: list[mercantile.Tile] = []
    for z in range(min_zoom, max_zoom + 1):
        for tile in mercantile.tiles(west, south, east, north, zooms=z):
            key = (tile.z, tile.x, tile.y)
            if key not in seen:
                seen.add(key)
                tiles.append(tile)
    return tiles


def _render_tile_from_source(
    source,
    colormap: dict,
    source_bounds_3857: tuple[float, float, float, float],
    z: int,
    x: int,
    y: int,
) -> bytes | None:
    tile = mercantile.Tile(x=x, y=y, z=z)
    tile_bounds = mercantile.xy_bounds(tile)
    if not _intersects(source_bounds_3857, tile_bounds):
        return None

    destination = np.full((TILE_SIZE, TILE_SIZE), 255, dtype=np.uint8)
    destination_transform = from_bounds(
        tile_bounds.left,
        tile_bounds.bottom,
        tile_bounds.right,
        tile_bounds.top,
        TILE_SIZE,
        TILE_SIZE,
    )

    reproject(
        source=rasterio.band(source, 1),
        destination=destination,
        src_transform=source.transform,
        src_crs=source.crs,
        dst_transform=destination_transform,
        dst_crs=WEB_MERCATOR,
        resampling=Resampling.nearest,
        src_nodata=255,
        dst_nodata=255,
    )

    if not np.any(destination != 255):
        return None

    rgba = _apply_colormap(destination, colormap)
    if not np.any(rgba[:, :, 3]):
        return None

    buffer = io.BytesIO()
    Image.fromarray(rgba, mode="RGBA").save(buffer, format="PNG")
    return buffer.getvalue()


def bake_product_tiles(geotiff_path: Path, product_id: str, bounds_wgs84: list[float], output_dir: Path) -> int:
    count = 0
    product_dir = output_dir / product_id
    with rasterio.open(geotiff_path) as source:
        colormap = source.colormap(1) or {1: (0, 92, 230, 255), 3: (219, 0, 0, 255)}
        source_bounds_3857 = transform_bounds(source.crs, WEB_MERCATOR, *source.bounds)
        for tile in tiles_for_bounds(bounds_wgs84, MIN_ZOOM, MAX_ZOOM):
            png = _render_tile_from_source(
                source, colormap, source_bounds_3857, tile.z, tile.x, tile.y
            )
            if not png:
                continue
            tile_path = product_dir / str(tile.z) / str(tile.x) / f"{tile.y}.png"
            tile_path.parent.mkdir(parents=True, exist_ok=True)
            tile_path.write_bytes(png)
            count += 1
    return count


def _bake_product_task(args: tuple[str, str, list[float], str]) -> tuple[str, int]:
    geotiff_path, product_id, bounds_wgs84, output_dir = args
    count = bake_product_tiles(
        Path(geotiff_path),
        product_id,
        bounds_wgs84,
        Path(output_dir),
    )
    return product_id, count


def bake_all_products(
    products: list[dict],
    tiff_dir: Path,
    output_dir: Path,
    workers: int = 4,
) -> int:
    tasks = [
        (
            str(tiff_dir / product["filename"]),
            product["id"],
            product["bounds"],
            str(output_dir),
        )
        for product in products
    ]
    total = 0
    with ProcessPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(_bake_product_task, task) for task in tasks]
        for future in as_completed(futures):
            product_id, count = future.result()
            total += count
            print(f"  …{product_id[-20:]} -> {count} tiles")
    return total
