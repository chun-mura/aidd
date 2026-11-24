import pytest

from app.pagination import get_page, page_count


def test_page_count_rounds_up():
    assert page_count(10, 4) == 3
    assert page_count(8, 4) == 2
    assert page_count(0, 4) == 0


def test_get_page_returns_the_slice():
    items = list(range(10))
    assert get_page(items, 1, 4) == [0, 1, 2, 3]
    assert get_page(items, 3, 4) == [8, 9]
    assert get_page(items, 4, 4) == []


def test_get_page_rejects_page_zero():
    with pytest.raises(ValueError):
        get_page([1], 0, 4)
