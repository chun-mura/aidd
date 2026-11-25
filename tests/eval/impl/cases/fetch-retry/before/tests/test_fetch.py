from app.fetch import fetch


def test_fetch_returns_the_body():
    assert fetch("http://status.example/", lambda url: b"ok") == b"ok"
