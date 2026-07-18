---
name: review-loop
description: Use when running repeated review-fix rounds (design review, PR review, or subagent findings) and deciding when to stop, or when findings arrive in mixed severity vocabularies.
---

# レビュー反復の終了条件

開始時に終了条件を宣言する。既定は「high/mid が0件のラウンドが2回連続」。high は実害、mid は正しさ・保守性への影響、low は実害のない改善案とする。low は終了を妨げない。

`.aidd/review-dismissed.md` があれば読み、ユーザー承認済みの棄却済み指摘を対象と理由付きで次ラウンドへ渡す。同一指摘は再報告・終了判定の対象にしない。棄却を追加するのはユーザー承認後だけとする。

静的検査は `superpowers:verification-before-completion`、指摘への対応は `superpowers:receiving-code-review`、現物確認と反証は `aidd:refuter` に従う。
