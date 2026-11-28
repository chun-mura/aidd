"""Text helpers for building page URLs."""
import re


def slugify(title):
    """Turn a page title into a URL slug."""
    lowered = title.lower()
    return re.sub(r"[^a-z0-9]", "-", lowered)
