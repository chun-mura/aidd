"""Load the service settings from a JSON file."""
import json
from pathlib import Path

DEFAULTS = {"retries": 3, "timeout_seconds": 10}


def load_settings(path: Path) -> dict:
    """Return the defaults overridden by the file's values."""
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    return {**DEFAULTS, **data}
