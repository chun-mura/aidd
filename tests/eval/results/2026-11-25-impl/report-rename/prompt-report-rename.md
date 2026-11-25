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

`app/report.py` の `fmt_total` を `format_total` に改名し、型注釈と docstring を付ける。

## 守る不変条件

- `app/report.py` は `app/cli.py` だけが使う内部モジュールで、外部に公開していない (旧名を残す必要はない)
- 出力の書式 (3桁区切り・小数2桁) は変えない
- 対象の Python は 3.12 以上

## 具体的な懸念点

- 呼び出し元とテストの改名漏れ

## 差分

```diff
diff --git a/app/cli.py b/app/cli.py
index d56af1a..f6b8d1c 100644
--- a/app/cli.py
+++ b/app/cli.py
@@ -1,12 +1,12 @@
 """Print the total of the amounts given on the command line."""
 import sys
 
-from app.report import fmt_total
+from app.report import format_total
 
 
 def main(argv: list) -> int:
     amounts = [float(a) for a in argv]
-    print(fmt_total(amounts))
+    print(format_total(amounts))
     return 0
 
 
diff --git a/app/report.py b/app/report.py
index 330454c..56211a7 100644
--- a/app/report.py
+++ b/app/report.py
@@ -1,6 +1,8 @@
 """Formatting helpers used only by app/cli.py (not part of any public API)."""
+from collections.abc import Iterable
 
 
-def fmt_total(values):
+def format_total(values: Iterable[float]) -> str:
+    """Return the sum with thousands separators and two decimals."""
     total = sum(values)
     return f"{total:,.2f}"
diff --git a/tests/test_report.py b/tests/test_report.py
index b08a4ad..c0b7125 100644
--- a/tests/test_report.py
+++ b/tests/test_report.py
@@ -1,9 +1,9 @@
-from app.report import fmt_total
+from app.report import format_total
 
 
-def test_fmt_total_groups_thousands():
-    assert fmt_total([1000, 234.5]) == "1,234.50"
+def test_format_total_groups_thousands():
+    assert format_total([1000, 234.5]) == "1,234.50"
 
 
-def test_fmt_total_of_nothing_is_zero():
-    assert fmt_total([]) == "0.00"
+def test_format_total_of_nothing_is_zero():
+    assert format_total([]) == "0.00"
```
