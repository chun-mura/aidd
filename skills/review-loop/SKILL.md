---
name: review-loop
description: Use when running repeated review-fix rounds (design review, PR review, or subagent review findings), when findings keep appearing round after round and it is unclear when to stop, or when review findings arrive in mixed severity vocabularies.
---

# レビュー反復の運用

レビュー→修正のラウンドを回すとき、終了条件を先に決めてから始める。決めずに回すとレビューは無限ループする。

## 前提: レビューはサンプリング

何ラウンド回しても新しい指摘が出るのは異常ではない。レビューは観点を変えるたびに新しい層が見えるサンプリングであり、指摘ゼロには収束しない。「指摘がまだ出る」こと自体を続行の理由にしない。

## 重要度の語彙

aidd の正典は **high / mid / low** (design-review command・design-arbiter agent と同一)。他ツールの指摘は仕分け・終了判定の前にこの語彙へ読み替える:

| 外部語彙 | 読み替え |
|---|---|
| Critical | high |
| Important | mid |
| Suggestion / Nit | low |
| blocking (Google 流) | high または mid |
| `Nit:` 接頭辞 (Google 流) | low |

深刻度の判定はエージェントの裁量に委ねず、以下のルーブリックに照合する (正典はこのスキル。design-review command の dispatch 指示に同文を埋め込んでいるため、変更時は両方を同期する):

- **high**: リリースすると実害が出る。データ破壊・欠損、セキュリティ (認証・認可の破壊を含む)、本番障害に直結する指摘
- **mid**: 正しさ・保守性に影響するが、回避策があるか影響範囲が限定的な指摘
- **low**: スタイル・好み・改善アイデア。放置しても実害がない指摘

high/mid = 修正するまでラウンドを終了しない指摘、low = 終了を阻まない指摘、と定義する。

## 手順

1. **開始前に終了条件を決めて宣言する**。推奨デフォルト: 「high/mid の指摘 0件が2ラウンド連続」。low はゼロにならない前提で重要度で切る
2. ラウンドごとに、dispatch 前にプロジェクトの静的検査 (lint・typecheck・テスト。存在するもののみ) を実行し、結果を dispatch に含める。機械が検出できる問題は静的検査に任せ、レビュー指摘としては扱わない
3. ラウンドごとに指摘を正典語彙で仕分けし、終了条件の判定結果を明示する
4. 棄却した指摘 (反証成立・現物不一致) は理由付きで一覧に保持し、次ラウンドの dispatch に「棄却済み・再報告禁止」として対象と併せて渡す (design-review を再実行する場合も一覧を渡す)。棄却済みと同一内容の指摘が再報告されても終了判定にカウントしない
5. 終了条件に達したら止める。残った low 指摘は対応せず一覧として報告し、対応要否はユーザーに委ねる

high/mid が毎ラウンド多発する場合は、ラウンドを重ねる前にレビュー単位 (diff・設計書) の分割を検討する。レビュー単位が小さいほど指摘の精度は上がる ([Google Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html))。

## 読了担保 (コード diff のラウンド)

設計書のレビューは design-review command が読了プロトコルを内蔵している。コード diff のラウンドを他ツール (pr-review-toolkit、built-in /code-review など) や自前 dispatch で回すときは、同じ担保を自分で掛ける:

**dispatch 時** — レビュー agent への依頼に含める:

- 対象 diff の全 hunk と、変更ファイルの関連コンテキスト (呼び出し元・オーバーライド元の基底クラス) を読む。部分読みのまま指摘を出さない
- 指摘には file:line を必須とする
- 結果の冒頭に読了状況 (読了したファイル / 読み切れなかったファイル) を報告させる。読み切れなかった範囲の指摘は採用しない

**適用前** — high/mid の指摘は、修正に着手する前に Read で現物確認する。agent の行番号・関数名は幻覚することがあるため、指摘の file:line が実在し、指摘内容が現物と一致することを確認してから直す。一致しない指摘は棄却し、理由を記録する。

現物と一致した指摘も、直す前に反証を試みる (**aidd:refuter agent** に対象と指摘を渡すか、自分で前提条件の成立・経路の到達可能性・別の場所での処理有無を検証する)。指摘の確認ではなく反証を仕事とする視点を経ることで、もっともらしい誤指摘を落とす。反証が成立した指摘は棄却し、理由を手順4の持ち越し一覧に記録する。

## 指摘対応時の落とし穴

- 指摘1件ごとの対応プロトコル (pushback・1件ずつテスト) は `superpowers:receiving-code-review` に従う。エージェント由来の指摘も External Reviewer として扱い、鵜呑みにしない
- **フレームワークの基底クラス・暗黙経路に触る修正提案は、フレームワークの実装を読んでから適用する**。「不変条件を `__init__` で強制しろ」のような一般則として正しい提案が、フレームワークの内部ロード経路を破壊することがある。「良さそうな提案」と「検証済みの提案」は別物
- 修正後は毎ラウンド、テスト実行と exit code 確認を回す (`superpowers:verification-before-completion`)

## 関連

- `commands/design-review.md` — 設計レビューの1ラウンド分 (並列 dispatch → arbiter 裁定、読了プロトコル内蔵)
- `superpowers:receiving-code-review` — 指摘1件への対応プロトコル
- `superpowers:verification-before-completion` — 完了主張前の検証
- [Google Code Review Developer Guide](https://google.github.io/eng-practices/review/) — 本スキルの参照元。終了条件は [The Standard of Code Review](https://google.github.io/eng-practices/review/reviewer/standard.html) の「完璧ではなく改善を承認する」原則、severity 対応表の blocking / `Nit:` は同ガイドの語彙に基づく
