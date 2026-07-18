# aidd トークン最適化設計

## 目的

レビュー品質を落とさず、通常の設計レビュー、hook、常時注入で消費するトークンと実行負荷を減らす。

## 方針

1. `design-review` は、high/mid 指摘、agent 間の矛盾、明示的な `--depth=deep`、または外部情報源検証が必要な場合だけ追加の反証・裁定を行う。
2. 指摘なしの reviewer 出力は読了状況を含む1行に固定する。
3. refuter は指摘、引用箇所、必要最小限の関連パスだけを入力として受け、対象全体を再読しない。
4. Bash hook の JSON 解析を1本の dispatcher に集約し、対象外コマンドは即時終了する。
5. usage log は `/aidd:*` の集計のみを既定とし、全プロンプト履歴は `AIDD_PROMPT_LOG=1` のときだけ保存する。
6. SessionStart の常時注入を短文化する。
7. severity ルーブリックと読了プロトコルの詳細は agent 定義を正典とし、command 側は参照に留める。

## design-review の実行モード

`--depth=standard` を既定、`--depth=deep` を明示的な完全経路とする。従来の `--verify-sources`、`--security`、`--no-security` と併用できる。

standard では reviewer 群を並列実行する。high/mid がなければ low をそのまま報告する。high/mid がある場合だけ refuter を起動する。refuter 後に生存する high/mid、reviewer 間の矛盾、または `--verify-sources` がある場合だけ arbiter を起動する。deep は従来どおり、high/mid があれば refuter、裁定対象があれば arbiter を起動する。

## hook と利用ログ

PreToolUse / PostToolUse は共通 dispatcher を1回だけ起動する。dispatcher はイベント種別と command を解析し、`git commit`、`gh pr|issue create|edit`、`git push` 以外では出力なしで終了する。既存の注意文と docs-only 判定は維持する。

usage log は command count と last seen を常に更新する。prompt log は `AIDD_PROMPT_LOG=1` の場合だけ最大200件保存する。retro は prompt log がない場合、繰り返し依頼の分析をスキップして集計・陳腐化確認を続行する。

## 品質と互換性

- `--depth=deep` は既存の品質重視経路として残す。
- セキュリティ reviewer の条件起動と `--security` / `--no-security` の意味は変えない。
- source verifier は opt-in のまま残す。
- 既存の `tests/eval` を全ケースで実行し、コア検出率・反証誤棄却・深刻度一致・デコイ誤検出を変更前後で比較する。
- shellcheck と plugin manifest validation を通す。

## 非対象

- レビュー観点そのものの削減
- agent のモデル階層の引き下げ
- 利用ログの外部送信
