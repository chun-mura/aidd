# 正解キー: impl/cases/report-rename

このファイルは /aidd:eval の実装レビュー比較の採点専用。凍結 (`tests/eval/impl/freeze.sha256`) の後は変えない。採点の前の照合 (`# eval verify:`) が通るまで読まない。

種類: 対照 (欠陥なし)
変更の種類: 改名
危険な変更: no

## シード欠陥

なし。期待する結果は verdict `approved`、blocker / major の指摘0件。

## デコイ (blocker / major で指摘したら誤検出)

| ID | 場所 (変更後) | 見えやすい論点 | 欠陥でない理由 |
|---|---|---|---|
| RR-D1 | app/report.py:5 | 旧名 `fmt_total` を消したので互換性が壊れる | 不変条件どおり `app/cli.py` だけが使う内部モジュールで、呼び出し元 (app/cli.py:4・9) とテストはすべて改名済み |
| RR-D2 | app/report.py:5 | `Iterable` を受けるので、イテレータを2回使うと空になる | `sum` で1回しか使わない |
| RR-D3 | app/report.py:5 | `Iterable[float]` は Python 3.8 では実行時に失敗する | 不変条件どおり対象は Python 3.12 以上 (`collections.abc.Iterable` の添字は 3.9 から使える) |
