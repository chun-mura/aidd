---
name: parallel-investigation
description: Use when investigating an unfamiliar codebase, mapping the impact of a change, or answering multiple independent questions that require reading many files.
---

# 並列調査フォーメーション

複雑な調査を複数の独立した問いに分解し、scout エージェント群 (haiku, 読み取り専用) を単一メッセージで並列起動して結論だけ受け取る。

## いつ使わないか

- 問いが1つだけ → scout は過剰。メイン側で Read 1-2回
- 問い同士に依存関係がある → 順序立てが必要。依存グラフを先に描く

## 構成

**メイン** (判断役) が問いを分解 → **scout ×N** が各問を調査 → 1メッセージで並列起動 → 結論のみ回収 → メインが検証・統合。

## 分解の仕方

- **場所で割る**: `src/api/` と `src/ui/` を別 scout に。結果を突き合わせて interface 破損を判定
- **観点で割る**: 「パフォーマンス」「セキュリティ」「互換性」を各 scout で並列調査
- **仮説で割る**: 「バグは X」「実は Y」を仮説ごとに scout へ。各仮説の証拠を file:line で収集し、最も強い仮説を確定

## プロンプトの型

scout への依頼に必ず含める:

- **対象パス**: 調査範囲 (e.g. `src/hooks/`)
- **問い**: 1文で明確に
- **出力形式**: file:line 参照を要求
- **行数上限**: 30行以内

例: 「`src/api/client.ts` を読み取り専用で調査し、Promise チェーンと async/await の使い分けパターンを file:line つきで3つ列挙。30行以内」

## 落とし穴

- 依存のある問いを並列化 → 前提が不完全で結論が破綻
- scout の報告を検証せず設計判断に使う → 重要判断の前に spot-check
- 2-3ファイルで済む調査を委譲 → 並列化のコストが見合わない

## 関連

- `superpowers:dispatching-parallel-agents` — 複数タスク並列実行の一般則
- `agents/scout.md` — scout の役割定義
- aidd の model-selection skill — scout 以外のモデル選定
