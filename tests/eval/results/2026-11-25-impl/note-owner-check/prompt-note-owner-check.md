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

3つのハンドラ (`get_note`・`update_note`・`delete_note`) に重複していたメモの取得と確認を `_owned_note` にまとめるリファクタ。挙動は変えない。

## 守る不変条件

- 所有者以外は、どのハンドラでも他人のメモを読めず、変えられず、消せない
- 存在しないメモは `Forbidden` にする (存在するかどうかを他人に知らせない)

## 具体的な懸念点

- リファクタで挙動が変わっていないこと

## 差分

```diff
diff --git a/app/notes.py b/app/notes.py
index 727b967..f28aa9d 100644
--- a/app/notes.py
+++ b/app/notes.py
@@ -5,23 +5,23 @@ class Forbidden(Exception):
     pass
 
 
-def get_note(store: dict, user_id: str, note_id: str) -> dict:
+def _owned_note(store: dict, user_id: str, note_id: str) -> dict:
     note = store.get(note_id)
     if note is None or note["owner_id"] != user_id:
         raise Forbidden(note_id)
     return note
 
 
+def get_note(store: dict, user_id: str, note_id: str) -> dict:
+    return _owned_note(store, user_id, note_id)
+
+
 def update_note(store: dict, user_id: str, note_id: str, text: str) -> dict:
-    note = store.get(note_id)
-    if note is None or note["owner_id"] != user_id:
-        raise Forbidden(note_id)
+    note = _owned_note(store, user_id, note_id)
     note["text"] = text
     return note
 
 
 def delete_note(store: dict, user_id: str, note_id: str) -> None:
-    note = store.get(note_id)
-    if note is None or note["owner_id"] != user_id:
+    if store.pop(note_id, None) is None:
         raise Forbidden(note_id)
-    del store[note_id]
diff --git a/tests/test_notes.py b/tests/test_notes.py
index 5f8bfa7..89ff79e 100644
--- a/tests/test_notes.py
+++ b/tests/test_notes.py
@@ -18,3 +18,13 @@ def test_owner_can_read_update_and_delete():
 def test_other_user_cannot_read():
     with pytest.raises(Forbidden):
         get_note(make_store(), "bob", "n1")
+
+
+def test_other_user_cannot_update():
+    with pytest.raises(Forbidden):
+        update_note(make_store(), "bob", "n1", "x")
+
+
+def test_missing_note_is_forbidden():
+    with pytest.raises(Forbidden):
+        delete_note(make_store(), "alice", "n2")
```
