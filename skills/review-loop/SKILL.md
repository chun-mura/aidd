---
name: review-loop
description: Use when running repeated review-fix rounds (design review, PR review, or subagent findings) and deciding when to stop, or when findings arrive in mixed severity vocabularies.
---

# レビュー反復の終了条件

開始時に終了条件を宣言する。既定は「high が0件、かつ blocking mid が0件のラウンドが2回連続」。初回を含めて最大3ラウンドとし、上限までに満たせなければ自動反復を止め、未解決の high / blocking mid、棄却理由、次の選択肢を示してユーザー判断へエスカレーションする。high は実害、mid は正しさ・保守性への影響、low は実害のない改善案とする。low は終了を妨げない。

mid は原則 blocking とする。ただしユーザーが受容し、担当者・理由・追跡先を明記したものだけを `deferred mid` として非ブロッキングにできる。`deferred mid` は完了扱いにせず、最終報告に残す。

追跡先として認めるのは、確定した Issue / ADR の番号、または `.aidd/review-dismissed.md` への理由つき追記 (ユーザー承認後) のどちらかとする。「レポートに書いた」は追跡先ではない。追跡先が確定しない指摘は `deferred mid` にできず、blocking のまま扱ってユーザー判断へエスカレーションする。

2ラウンド目以降は、前ラウンドの指摘への修正差分と必要な周辺文脈をレビュー対象にする。前回の high / blocking mid が解消されたことと、該当する静的検査・テスト結果は必ず確認する。責務境界・公開インターフェース・データフローを変更した場合、変更範囲を確定できない場合、または指摘間に矛盾がある場合は全体再レビューへ戻す。

開始前に対象が大きい (目安: 5ファイル超、合計3000行超、または独立してマージ可能な単位が2つ以上) 場合は、反復を始める前に `/aidd:issue-split` を提案する。横断的変更など分割できない理由がある場合だけ、理由を記録してレビューを続ける。

`.aidd/review-dismissed.md` があれば読み、ユーザー承認済みの棄却済み指摘を対象と理由付きで次ラウンドへ渡す。同一指摘は再報告・終了判定の対象にしない。棄却を追加するのはユーザー承認後だけとする。

静的検査は `superpowers:verification-before-completion`、指摘への対応は `superpowers:receiving-code-review`、現物確認と反証は `aidd:refuter` に従う。
