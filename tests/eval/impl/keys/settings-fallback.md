# 正解キー: impl/cases/settings-fallback

このファイルは /aidd:eval の実装レビュー比較の採点専用。凍結 (`tests/eval/impl/freeze.sha256`) の後は変えない。採点の前の照合 (`# eval verify:`) が通るまで読まない。

種類: 欠陥あり
変更の種類: 例外の扱い
危険な変更: no

## シード欠陥

| ID | 場所 (変更後) | 欠陥 | 期待する深刻度 | 一致判定基準 |
|---|---|---|---|---|
| SF-S1 | app/settings.py:16 | `except (OSError, ValueError)` で、ファイルが無い場合 (`FileNotFoundError`) だけでなく、読めない場合 (権限・ディレクトリ) と JSON が壊れている場合 (`ValueError`) も黙って既定値を返す。不変条件「あるのに読めない・壊れているときは起動を止める」に反し、誤った設定のまま気づかれずに動く | major 以上 | 捕捉する例外が広すぎる (ファイルが無い場合に限っていない、壊れた設定・読めない設定を握り潰して既定値で動く) ことを指摘していれば検出。場所は app/settings.py の 13〜17 行 (`try`/`except`) の前後 |

## デコイ (blocker / major で指摘したら誤検出)

| ID | 場所 (変更後) | 見えやすい論点 | 欠陥でない理由 |
|---|---|---|---|
| SF-D1 | app/settings.py:17 | `dict(DEFAULTS)` の浅いコピー | 値はすべて int で入れ子が無いので、浅いコピーで `DEFAULTS` は書き換えられない (追加したテストも確かめている) |
