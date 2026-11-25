# 正解キー: impl/cases/fetch-retry

このファイルは /aidd:eval の実装レビュー比較の採点専用。凍結 (`tests/eval/impl/freeze.sha256`) の後は変えない。採点の前の照合 (`# eval verify:`) が通るまで読まない。

種類: 対照 (欠陥なし)
変更の種類: 例外の扱い
危険な変更: no

## シード欠陥

なし。期待する結果は verdict `approved`、blocker / major の指摘0件。

## デコイ (blocker / major で指摘したら誤検出)

| ID | 場所 (変更後) | 見えやすい論点 | 欠陥でない理由 |
|---|---|---|---|
| FR-D1 | app/fetch.py:14 | 最後の失敗で例外を失う・戻り値が None になる | 最後の試行では `raise` で同じ例外を送り直す。`attempts` が1以上なので、ループは値を返すか例外を送るかで必ず終わり、ループの後 (16行) には届かない (テストも確かめている) |
| FR-D2 | app/fetch.py:11 | 再試行すると副作用が重なる | 不変条件どおり読み取りだけの GET で、副作用は無い |
| FR-D3 | app/fetch.py:15 | 最後の試行の後にも待つ | 最後の試行では `sleep` の前に `raise` する (テストの待ち時間 `[1, 2]` が確かめている) |
| FR-D4 | app/fetch.py:12 | `ConnectionError` 以外 (タイムアウトなど) も再試行すべき | 不変条件どおり `ConnectionError` だけを再試行する仕様で、それ以外をすぐ返すのは意図どおり |
