"""Load scripts/globus/env.config.*.sh into os.environ."""

from __future__ import annotations

import os
from pathlib import Path

GLOBUS_DIR = Path(__file__).resolve().parent


def load_globus_config() -> None:
    merged: dict[str, str] = {}
    for name in ("env.config.example.sh", "env.config.local.sh"):
        path = GLOBUS_DIR / name
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
