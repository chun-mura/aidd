"""Formatting helpers used only by app/cli.py (not part of any public API)."""


def fmt_total(values):
    total = sum(values)
    return f"{total:,.2f}"
