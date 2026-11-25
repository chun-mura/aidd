import json

from app.settings import DEFAULTS, load_settings


def test_file_values_override_defaults(tmp_path):
    path = tmp_path / "settings.json"
    path.write_text(json.dumps({"retries": 5}), encoding="utf-8")
    assert load_settings(path) == {**DEFAULTS, "retries": 5}
