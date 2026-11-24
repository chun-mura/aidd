"""Split a list into fixed-size, 1-based pages."""


def page_count(total: int, size: int) -> int:
    if size <= 0:
        raise ValueError("size must be positive")
    return (total + size - 1) // size


def get_page(items: list, page: int, size: int) -> list:
    """Return the items on a 1-based page; an empty list past the last page."""
    if page < 1:
        raise ValueError("page must be 1 or more")
    start = (page - 1) * size
    return items[start:start + size]
