from app.report import fmt_total


def test_fmt_total_groups_thousands():
    assert fmt_total([1000, 234.5]) == "1,234.50"


def test_fmt_total_of_nothing_is_zero():
    assert fmt_total([]) == "0.00"
