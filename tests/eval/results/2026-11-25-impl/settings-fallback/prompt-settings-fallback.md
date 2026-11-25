あなたはコードレビューの担当です。作業ディレクトリは、下の差分を当てた後のリポジトリのスナップショットです (Git の履歴はありません)。下の「変更目的」「守る不変条件」「具体的な懸念点」と差分を読み、この差分が持ち込む問題を指摘してください。

- 作業ディレクトリの中のファイルだけを読む。親ディレクトリや作業ディレクトリの外の絶対パスを開かない
- ファイルを変更しない。ユーザーには質問しない (答えは返らない)
- 最終回答は次の JSON オブジェクトだけにする (Markdown のコードフェンスや前後の説明を付けない)。`file` は作業ディレクトリからの相対パス、`line` は変更後のファイルの行番号。問題が無ければ `findings` を空の配列にし、`verdict` を `approved` にする
- `severity` の目安: `blocker` はマージすると壊れる・危険、`major` はマージ前に直すべき欠陥、`minor` は直すとよい点、`nit` は好みの問題

{
  "verdict": "approved" | "changes_requested",
  "findings": [
    {
      "id": "R1",
      "severity": "blocker" | "major" | "minor" | "nit",
      "file": "relative/path",
      "line": 123,
      "title": "短い表題",
      "claim": "何が問題か",
      "evidence": "コード、仕様、テストに基づく根拠",
      "verification": "確認手順"
    }
  ]
}

## 変更目的

設定ファイルを置かずにサービスを起動したときは、既定値で動くようにする (`app/settings.py` の `load_settings`)。

## 守る不変条件

- 設定ファイルが無いときは既定値で起動する
- 設定ファイルがあるのに読めない・壊れているときは、起動を止める (黙って既定値で動かない。誤った設定のまま本番で動くのを防ぐため)
- 既定値の辞書 `DEFAULTS` は呼び出し側に書き換えられない

## 具体的な懸念点

- 例外の扱い

## 差分

```diff
diff --git a/app/settings.py b/app/settings.py
index 690b65d..a7054d9 100644
--- a/app/settings.py
+++ b/app/settings.py
@@ -6,7 +6,13 @@ DEFAULTS = {"retries": 3, "timeout_seconds": 10}
 
 
 def load_settings(path: Path) -> dict:
-    """Return the defaults overridden by the file's values."""
-    with path.open(encoding="utf-8") as f:
-        data = json.load(f)
+    """Return the defaults overridden by the file's values.
+
+    A service started without a settings file runs with the defaults.
+    """
+    try:
+        with path.open(encoding="utf-8") as f:
+            data = json.load(f)
+    except (OSError, ValueError):
+        return dict(DEFAULTS)
     return {**DEFAULTS, **data}
diff --git a/tests/test_settings.py b/tests/test_settings.py
index 4b2fc37..651ed78 100644
--- a/tests/test_settings.py
+++ b/tests/test_settings.py
@@ -7,3 +7,13 @@ def test_file_values_override_defaults(tmp_path):
     path = tmp_path / "settings.json"
     path.write_text(json.dumps({"retries": 5}), encoding="utf-8")
     assert load_settings(path) == {**DEFAULTS, "retries": 5}
+
+
+def test_missing_file_gives_defaults(tmp_path):
+    assert load_settings(tmp_path / "absent.json") == DEFAULTS
+
+
+def test_defaults_are_not_shared(tmp_path):
+    settings = load_settings(tmp_path / "absent.json")
+    settings["retries"] = 0
+    assert DEFAULTS["retries"] == 3
```
