# aidd 6機能追加 設計

規模: 複数コンポーネント (skill/command/hook 各種) の追加のため、フル記述。

## 背景と目的

aidd の既存資産 (ADR, retro, design-doc, test-perspectives, design-review) は「書く・提示する」ところで止まり、運用ルール5「受動ドキュメント禁止」に反する部分が残っている。過去の決定・設計との整合を能動的に検知し、蓄積した使用実績をデータとして扱えるようにする。

## スコープ / やらないこと

対象:
1. adr-recall skill — ADR を能動的に参照させる
2. retro 計測基盤 — 使用実績のログ化
3. design-sync command — 設計と実装のドリフト検知
4. test-perspectives 永続化 — 出力を保存し commit-reminder と連携
5. design-review 観点カスタム — プロジェクト固有観点の追加
6. doctor command — 導入状態の診断

やらない:
- test-perspectives / design-doc のテンプレート化 (YAGNI。現行の自由記述で足りる)
- usage.json の可視化 UI やダッシュボード (retro が読むだけで十分)
- 観点カスタムファイルの自動生成・雛形提供 (プロジェクト側が手で書く)

## 構成と責務

| コンポーネント | 責務 |
|---|---|
| `skills/adr-recall/SKILL.md` | アーキ変更時に既存 ADR を検索し矛盾を提示する |
| `hooks/scripts/usage-log.sh` | UserPromptSubmit で aidd コマンド使用数とプロンプト先頭120字を `~/.claude/aidd/usage.json` に記録 |
| `commands/design-sync.md` | `docs/design/` の各設計書とコード実態を突き合わせ、乖離レポートを出す |
| `commands/design-doc.md` (改修) | 生成物に frontmatter `status` を追加 |
| `commands/test-perspectives.md` (改修) | 出力を `docs/test-perspectives/` に保存する |
| `hooks/scripts/commit-reminder.sh` (改修) | 保存済み test-perspectives の鮮度をチェックしてから注入するか判断 |
| `commands/design-review.md` (改修) | `.aidd/design-perspectives.md` があれば4番目の reviewer agent として並列追加 |
| `commands/doctor.md` | 導入状態・バージョン整合・hooks 実行可否を診断する |
| `commands/retro.md` (改修) | usage.json の実データを使って昇格候補・未使用資産を判定する |

各コンポーネントは既存の agent/hook/command の枠組みに乗るだけで、新しい依存や外部通信は発生しない。

## インターフェース

- `adr-recall`: 自動トリガ skill。ユーザー操作不要
- `/aidd:design-sync [対象パス]`: 未指定なら `docs/design/` 全体
- `/aidd:doctor`: 引数なし
- `usage-log.sh` / `commit-reminder.sh`: 既存 hook イベントに乗るのみで CLI 面は増えない
- `design-review.md`: 既存の `argument-hint` 不変。プロジェクトに `.aidd/design-perspectives.md` があるかどうかで内部分岐

## データフロー

- `usage.json` (`~/.claude/aidd/usage.json`, プラグイン外) が唯一の実績データストア。書き込み元は `usage-log.sh` のみ。読み取りは `/aidd:retro` (実績分析) と `doctor` (JSON 妥当性チェックのみ) の2箇所。既存 `state.json` (session_count) とはファイルを分けて責務を分離 — 一方の破損が他方に伝播しない
- `docs/design/*.md` の `status` frontmatter が設計書のライフサイクル状態の唯一の持ち主。design-sync はここを読んで判定し、更新も同フィールドのみに書き込む (本文は書き換えない)
- `docs/test-perspectives/*.md` が唯一の永続先。commit-reminder はここのファイルの mtime のみを見る (二重管理なし)

## エラー処理

- `usage-log.sh`: JSON パース失敗時は握り潰して exit 0 (非ブロック hook の既存方針を継承)。壊れた usage.json は次回書き込みで作り直す (読み取り失敗時は空扱いで上書き)
- `design-sync`: 判定結果は提示のみ、ファイル変更はユーザー承認後 (retro と同じ AskUserQuestion ゲート)。scout agent が失敗した設計書は「調査失敗」として明示し、全体を止めない
- `commit-reminder.sh`: test-perspectives ディレクトリが存在しない/読めない場合は現行通りリマインダを出す (fail-safe 側に倒す)
- `doctor`: 各チェックは独立。1項目の失敗が他項目の診断を止めない

## 運用

- ロールバック: 各 hook は非ブロックなので、不要になれば `hooks/hooks.json` からエントリを削除するだけ
- 監視: `usage.json` / `state.json` はローカルファイルのみ、外部送信なし
- 変更反映には既存運用同様 push + `/plugin update aidd` が必要
- README・CHANGELOG (0.8.0)・plugin.json version を更新
