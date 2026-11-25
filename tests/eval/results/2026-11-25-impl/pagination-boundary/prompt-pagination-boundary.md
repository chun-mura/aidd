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

一覧 API がページ送りに使う値 (そのページの項目・総ページ数・次のページの有無) を1回で返す `paginate` を `app/pagination.py` に足す。

## 守る不変条件

- ページは1始まり。最後のページより後のページは空のリストになる
- 既存の `get_page` と `page_count` の挙動は変えない
- クライアントは `has_next` が偽になるまで次のページを取りに来る

## 具体的な懸念点

- 項目が0件のときと、項目数がページサイズで割り切れないときの扱い

## 差分

```diff
diff --git a/app/pagination.py b/app/pagination.py
index a984429..1ebba1f 100644
--- a/app/pagination.py
+++ b/app/pagination.py
@@ -13,3 +13,14 @@ def get_page(items: list, page: int, size: int) -> list:
         raise ValueError("page must be 1 or more")
     start = (page - 1) * size
     return items[start:start + size]
+
+
+def paginate(items: list, page: int, size: int) -> dict:
+    """Return one 1-based page with the navigation fields the list API sends."""
+    total_pages = page_count(len(items), size)
+    return {
+        "items": get_page(items, page, size),
+        "page": page,
+        "total_pages": total_pages,
+        "has_next": page < total_pages - 1,
+    }
diff --git a/tests/test_pagination.py b/tests/test_pagination.py
index 30ef7b0..0234d62 100644
--- a/tests/test_pagination.py
+++ b/tests/test_pagination.py
@@ -1,6 +1,6 @@
 import pytest
 
-from app.pagination import get_page, page_count
+from app.pagination import get_page, page_count, paginate
 
 
 def test_page_count_rounds_up():
@@ -19,3 +19,14 @@ def test_get_page_returns_the_slice():
 def test_get_page_rejects_page_zero():
     with pytest.raises(ValueError):
         get_page([1], 0, 4)
+
+
+def test_paginate_first_and_last_page():
+    items = list(range(10))
+    first = paginate(items, 1, 4)
+    assert first["items"] == [0, 1, 2, 3]
+    assert first["total_pages"] == 3
+    assert first["has_next"] is True
+    last = paginate(items, 3, 4)
+    assert last["items"] == [8, 9]
+    assert last["has_next"] is False
```
