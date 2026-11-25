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

状態ページの取得 (`app/fetch.py` の `fetch`) で、接続が切れたときだけ待ち時間を倍にしながら再試行する。

## 守る不変条件

- `fetch` は読み取りだけの GET で、何度呼んでも副作用は無い
- 注入する `opener` は、接続が切れたときに `ConnectionError` を投げる
- 再試行は `ConnectionError` だけ。それ以外の例外はすぐに呼び出し側へ返す
- 最後の試行でも失敗したら、その例外をそのまま呼び出し側へ返す

## 具体的な懸念点

- 再試行の回数と待ち時間、最後の失敗の扱い

## 差分

```diff
diff --git a/app/fetch.py b/app/fetch.py
index c347fba..efec932 100644
--- a/app/fetch.py
+++ b/app/fetch.py
@@ -1,5 +1,16 @@
 """Read-only GET of a status page through an injected opener."""
+import time
 
 
-def fetch(url: str, opener) -> bytes:
-    return opener(url)
+def fetch(url: str, opener, attempts: int = 3, sleep=time.sleep) -> bytes:
+    """Retry a dropped connection with a doubling wait; other errors are raised at once."""
+    if attempts < 1:
+        raise ValueError("attempts must be 1 or more")
+    for attempt in range(1, attempts + 1):
+        try:
+            return opener(url)
+        except ConnectionError:
+            if attempt == attempts:
+                raise
+            sleep(2 ** (attempt - 1))
+    raise AssertionError("unreachable: the last attempt returns or raises")
diff --git a/tests/test_fetch.py b/tests/test_fetch.py
index 2d89f48..128c72e 100644
--- a/tests/test_fetch.py
+++ b/tests/test_fetch.py
@@ -3,3 +3,52 @@ from app.fetch import fetch
 
 def test_fetch_returns_the_body():
     assert fetch("http://status.example/", lambda url: b"ok") == b"ok"
+
+
+def flaky(failures):
+    calls = []
+
+    def opener(url):
+        calls.append(url)
+        if len(calls) <= failures:
+            raise ConnectionError("dropped")
+        return b"ok"
+
+    return opener, calls
+
+
+def test_retries_a_dropped_connection():
+    opener, calls = flaky(2)
+    waits = []
+    assert fetch("u", opener, sleep=waits.append) == b"ok"
+    assert len(calls) == 3
+    assert waits == [1, 2]
+
+
+def test_gives_up_after_the_last_attempt():
+    opener, calls = flaky(5)
+    waits = []
+    try:
+        fetch("u", opener, sleep=waits.append)
+    except ConnectionError:
+        pass
+    else:
+        raise AssertionError("expected ConnectionError")
+    assert len(calls) == 3
+    assert waits == [1, 2]
+
+
+def test_other_errors_are_not_retried():
+    calls = []
+
+    def opener(url):
+        calls.append(url)
+        raise ValueError("bad body")
+
+    try:
+        fetch("u", opener, sleep=lambda s: None)
+    except ValueError:
+        pass
+    else:
+        raise AssertionError("expected ValueError")
+    assert len(calls) == 1
```
