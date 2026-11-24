## 変更目的

`app/report.py` の `fmt_total` を `format_total` に改名し、型注釈と docstring を付ける。

## 守る不変条件

- `app/report.py` は `app/cli.py` だけが使う内部モジュールで、外部に公開していない (旧名を残す必要はない)
- 出力の書式 (3桁区切り・小数2桁) は変えない

## 具体的な懸念点

- 呼び出し元とテストの改名漏れ
