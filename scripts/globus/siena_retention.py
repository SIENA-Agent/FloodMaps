"""Retention rules for SIENA granules (same logic as scripts/Zaratan/sync_geotiffs.sh)."""

from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone

SENTINEL_DATE = re.compile(r"(20\d{6})T\d{6}")

DEFAULT_KEEP_DAYS = 30
DEFAULT_DEMO_DATES = ("20251214", "20251217", "20251219")


def sensing_date_from_name(name: str) -> str | None:
    match = SENTINEL_DATE.search(name)
    return match.group(1) if match else None


def cutoff_yyyymmdd(keep_days: int, *, now: datetime | None = None) -> str:
    ref = now or datetime.now(timezone.utc)
    return (ref - timedelta(days=keep_days)).strftime("%Y%m%d")


def is_demo_date(sdate: str, demo_dates: tuple[str, ...]) -> bool:
    return sdate in demo_dates


def should_keep_sensing_date(
    sdate: str,
    *,
    keep_days: int = DEFAULT_KEEP_DAYS,
    demo_dates: tuple[str, ...] = DEFAULT_DEMO_DATES,
    now: datetime | None = None,
) -> bool:
    if is_demo_date(sdate, demo_dates):
        return True
    return sdate >= cutoff_yyyymmdd(keep_days, now=now)


def is_rgb_geotiff(path: str) -> bool:
    name = path.rsplit("/", 1)[-1]
    return name.endswith(".tif") and "_RGB_" in name
