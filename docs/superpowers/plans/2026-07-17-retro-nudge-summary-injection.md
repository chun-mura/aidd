# Retro Nudge Summary Injection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 20セッションごとの retro nudge に、ローカル usage.json の縮小サマリを注入する。

**Architecture:** `session-start.sh` の既存 nudge 分岐内だけで `usage.json` を `jq` により集計する。集計できない場合は既存の提案文へフォールバックし、収集側・retro 本体は変更しない。

**Tech Stack:** Bash、jq、Claude Code plugin hooks、Markdown ADR。

## Global Constraints

- `hooks/scripts/usage-log.sh` は変更しない。
- `commands/retro.md` の提示のみ・手動承認による昇格フローは変更しない。
- 出力は10行以内とし、cron・schedule・ダッシュボード・フルレポートを導入しない。
- `jq` 不在・usage.json 不在・JSON解析失敗時は既存の nudge 文だけを出力する。

---

### Task 1: Retro nudge の集計注入

**Files:**
- Modify: `hooks/scripts/session-start.sh:17-36`
- Test: 一時 `state.json` と `usage.json` を用いた hook 実行

**Interfaces:**
- Consumes: `$HOME/.claude/aidd/state.json` の `session_count`
- Consumes: `$HOME/.claude/aidd/usage.json` の `command_counts` と `prompt_log`
- Produces: 20セッションごとの `additionalContext`（10行以内）

- [x] **Step 1: 期待する集計出力を定義する**

`command_counts` は `/aidd:<command>: <count>` を上位5件まで、`prompt_log[].text` は先頭120字が同じ値を数えて繰り返し件数として表示する。最後に `/aidd:retro で棚卸し推奨` を出力する。

- [x] **Step 2: nudge 分岐へ jq 集計を実装する**

`command -v jq` と usage.json の存在を確認してから jq を実行する。jq の失敗時は既存の単一行メッセージを出力し、hook は常に終了コード0を維持する。

- [x] **Step 3: 20回目の state.json で実行する**

テスト用に `session_count: 19` を含む state.json と複数コマンド・重複プロンプトを含む usage.json を配置し、hook 実行後に上位5件、繰り返し件数、推奨文、10行以内を確認する。jq を隠した環境でも既存文だけが出ることを確認する。

### Task 2: ADR とリリース記録

**Files:**
- Create: `docs/adr/0001-retro-nudge-summary-injection.md`
- Modify: `.claude-plugin/plugin.json:3`
- Modify: `CHANGELOG.md:3`

**Interfaces:**
- Consumes: `docs/superpowers/specs/2026-07-09-six-asset-additions-design.md` の自動レポート化 scope 外決定
- Produces: 縮小サマリだけを採る理由と、フル自動化を採らない理由を記録したADR

- [x] **Step 1: ADR を作成する**

ステータスを accepted とし、nudge時のみの集計注入を決定として記録する。代替案として既存の提案文維持と、cron・ダッシュボードによるフル自動化を比較し、不採用理由を明記する。

- [x] **Step 2: マイナー版とCHANGELOGを更新する**

プラグインバージョンを `0.19.0` に更新し、縮小サマリ、jqフォールバック、ADRをCHANGELOGへ記録する。

- [x] **Step 3: 静的検証を実行する**

Run: `shellcheck hooks/scripts/session-start.sh && claude plugin validate . --strict && git diff --check`

Expected: すべて終了コード0。

### Task 3: 全体確認

**Files:**
- Test: `hooks/scripts/session-start.sh`

- [x] **Step 1: 変更範囲を確認する**

Run: `git diff --name-only HEAD`

Expected: hook、ADR、plugin.json、CHANGELOG、およびこの計画書だけが今回の変更として含まれる。`usage-log.sh` と `commands/retro.md` は変更されない。

- [x] **Step 2: 完了条件を再確認する**

20回目のテスト実行結果、ADR保存先、`0.19.0`、検証コマンドの成功を確認する。
