# superpowers 運用ガイド (aidd との棲み分け)

## いつ使うか

新しいスキル / コマンドを aidd (本リポジトリ) に追加しようとしたとき、すでに superpowers に同じ機能がないか確認。superpowers のどのスキルをいつ使うか迷ったとき。

## 棲み分け原則

**どう進めるか (process) = superpowers、何をさせるか (task/domain) = aidd**

判断基準：「どの開発フェーズ・プロジェクトでも同じ動きをするか」。

- **Yes なら superpowers**: 計画立て、デバッグ手順、コード検証、テスト戦略など普遍的なプロセス
- **No、プロジェクト固有**: ADR雛形、DB設計チェックリスト、パフォーマンス計測スクリプト → aidd へ

## superpowers 主要スキル使いどころ

| スキル | 使いどころ | 非例 |
|--------|-----------|------|
| `brainstorming` | 新機能企画、要件の掘り下げ | 既知の手法をまとめる |
| `writing-plans` | 2ステップ以上の実装計画 | 定型の手順書 |
| `subagent-driven-development` | 複数の独立タスク並列実行 | 順序依存のあるコマンド |
| `test-driven-development` | テスト優先で実装方針を決める | テスト後追い生成 |
| `systematic-debugging` | バグの根本原因調査 | 既知の手順のチェック |
| `verification-before-completion` | 完了報告前の動作確認 | テストの記述 |

## aidd に追加してよいもの・悪いもの

**追加してよい** (プロジェクト固有, 繰り返し使う):
- ADR生成・記入ガイド
- DB設計チェックリスト (テーブル命名、インデックス判定)
- 本リポジトリのパフォーマンス計測スクリプト
- ドメイン知識に基づく品質基準 (例: API応答時間の目安)

**追加してはいけない** (汎用, superpowers が対応):
- 計画の立て方、セッション分割のタイミング
- 一般的なバグ調査ステップ
- コード品質ガイドライン (CLAUDE.md で十分)
- テスト駆動開発の進め方

## 形態の選び方 (aidd に置くと決めた後)

README 運用ルール5「受動ドキュメント禁止」に従い、セッション中に効かせたい知見を docs に置かない。

| 性質 | 形態 |
|------|------|
| 判断時に自動で参照させたい知識 | `skills/` (description で自動トリガ) |
| 忘れても強制したい運用 | `hooks/` (ハーネスが実行、モデル非依存) |
| ユーザーが明示的に起動するタスク | `commands/` |
| リポジトリ自体のメタ情報 (本ファイルなど) | `docs/` |

## superpowers と隣接する場合の判断

「重複禁止」の基準は**被りの有無**であり、汎用性そのものではない。

- 完全に被る → 作らない。ポインタのみ
- superpowers に存在しない知見 → 汎用寄りでも aidd に置いてよい (実例: `skills/model-selection/` — process 寄りだが superpowers に該当スキルなし)
- superpowers の一般則を aidd の agents/運用に特化した具体化 → 作ってよい。ただし superpowers 側へのポインタを必ず入れる (実例: `skills/parallel-investigation/` — `superpowers:dispatching-parallel-agents` の scout 特化形で、関連節から参照)

## 判断に迷ったら

「このスキルなしでもプロジェクトは動くが、あると便利か」→ aidd。
「このスキルなしだと手順が不完全か」→ superpowers。
