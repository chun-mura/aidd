# aidd 重複機能整理設計

## 目的

superpowers と重複する自動スキル、低品質な利用履歴分析、二重のセキュリティ観点を削減し、aidd の常時コンテキストと不要な reviewer 起動を減らす。

## 変更

1. `skills/parallel-investigation/` を削除する。並列調査の一般手順は `superpowers:dispatching-parallel-agents`、読み取り専用の出力契約は `agents/scout.md` が担う。
2. `/aidd:retro` は command count と `last_seen` による資産棚卸しだけを行う。`prompt_log` の分析、`AIDD_PROMPT_LOG`、20セッションごとの retro nudge は削除する。`usage-log.sh` は `/aidd:*` の count と last seen のみを保存する。
3. `skills/review-loop/` は severity、終了条件、棄却済み指摘の持ち越しだけを保持する。静的検査、読了、反証、修正後検証の手順は既存の superpowers skills と各 agent 定義への参照に置き換える。
4. `design-perspectives` テンプレートは可観測性などプロジェクト固有観点だけにする。信頼境界を跨ぐ設計のセキュリティは Agent 6 (STRIDE) が唯一の担当となる。`design-review` は Agent 4 にセキュリティ観点を含めないよう明記する。

## 互換性

- `scout` agent、`design-sync`、security-reviewer、`--security` / `--no-security` は維持する。
- 既存の `usage.json` にある `prompt_log` は読み書きせず、残存しても無害とする。
- 既存プロジェクトの `.aidd/design-perspectives.md` は自動編集しない。利用者はテンプレートから可観測性・固有観点だけを移行する。

## 検証

- usage log が command count と last seen だけを保存すること。
- session-start が retro nudge を出さないこと。
- README・コマンド・テンプレートから削除済み資産への能動的参照がないこと。
- shellcheck と plugin manifest validation を通す。
