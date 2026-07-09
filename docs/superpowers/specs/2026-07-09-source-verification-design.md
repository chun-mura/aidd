# design-review 外部情報源検証 設計

規模: agent 1追加 + command 1改修。小規模のため要点のみ。

## 背景と目的

design-review の既存観点 (構造・データとエラー・実用性・プロジェクト固有) はすべて設計書の内部整合性を見る。設計書に含まれる「外部で検証可能な主張」— 技術選定の根拠、API/仕様の正確性、バージョン互換性、セキュリティ推奨 — が誤っていても検出できない。信頼できる情報源 (公式ドキュメント・仕様書・リリースノート) と突き合わせる検証者を追加する。

## スコープ / やらないこと

対象:
1. `agents/source-verifier.md` — Web 検索・取得ができる検証 agent (新規)
2. `commands/design-review.md` — opt-in で source-verifier を並列 dispatch に追加 (改修)

やらない:
- 常時実行 (Web 検証はコスト高。opt-in のみ)
- 検証結果のキャッシュ・永続化 (YAGNI)
- プロジェクト固有の設計判断の検証 (外部情報源では検証不能。既存観点の管轄)

## 構成と責務

| コンポーネント | 責務 |
|---|---|
| `agents/source-verifier.md` | 設計書から外部検証可能な主張を抽出し、信頼できる情報源と突き合わせて verdict を返す。model: sonnet。tools: WebSearch, WebFetch, Read |
| `commands/design-review.md` | `$ARGUMENTS` に `--verify-sources` がある場合のみ **Agent 5 — 外部情報源検証** を同一メッセージの並列 dispatch に追加。フラグ指定時は小規模対象の直接レビューショートカットを適用しない (Agent 5 の起動を保証) |

## インターフェース

- `/aidd:design-review <対象> --verify-sources` — フラグなしなら現行動作と完全に同一
- source-verifier への入力: 対象 (ファイルパス or 要約) のみ。主張の抽出は verifier 自身が行う (他 reviewer と同じ「対象+観点」パターンを維持)
- 出力形式: 主張ごとに「確認済み (出典 URL) / 反証あり (出典 URL + 正しい情報) / 未確認 (理由)」

## データフロー

- source-verifier の結果は他 reviewer と同様に arbiter へ渡す。統合経路は1本のまま増やさない
- 検証対象の優先順: 技術選定の根拠 > API/仕様の主張 > バージョン互換性 > セキュリティ推奨。プロジェクト内部の判断は対象外と明示

## エラー処理

- Web 到達不可・検索結果なし: 該当主張を「未確認 (理由)」として返し、レビュー全体は止めない
- arbiter への指示: 「未確認」は指摘 (high/mid/low) に含めず情報として併記。「反証あり」のみ深刻度付き指摘に昇格

## 運用

- ロールバック: design-review.md の Agent 5 節と agents/source-verifier.md を削除するだけ。外部依存なし
- README・CHANGELOG (0.9.0)・plugin.json version を更新
