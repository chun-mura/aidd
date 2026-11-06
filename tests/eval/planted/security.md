# 偽指摘: cases/security.md

/aidd:eval が refuter の弁別力を測るために、reviewer の指摘へ混ぜる偽の指摘。いずれも設計書の別の箇所で反証できる。反証の根拠は keys 側にだけ書く。refuter へは表の行の内容だけを、中立な ID に振り直して渡す (このファイルの見出し・説明・ID は渡さない)。

| ID | 深刻度 | 引用箇所 | 指摘 | 代案 |
|---|---|---|---|---|
| PL-SEC1 | high | cases/security.md:22 (構成と責務) | `POST /api/files` がファイル種別を検証せずに S3 へ保存するため、PDF 以外の任意ファイル (実行ファイル等) を取引先に配布できる | Content-Type とマジックバイトで PDF を検証し、サイズ上限を設ける |
| PL-SEC2 | mid | cases/security.md:33 (データフロー) | 発行した署名付きURLを `contract_files` テーブルに保存しており、DB が漏えいすると有効なダウンロードURLが流出する | 署名付きURLは保存せず都度発行する |
| PL-SEC3 | mid | cases/security.md:37 (エラー処理) | 存在しない `file_id` への応答に S3 のキーやバケット名が含まれ得て、内部構成が露出する | 404 には存在有無以外の情報を含めない |
