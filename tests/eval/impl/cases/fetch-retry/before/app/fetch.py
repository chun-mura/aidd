"""Read-only GET of a status page through an injected opener."""


def fetch(url: str, opener) -> bytes:
    return opener(url)
