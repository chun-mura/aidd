# #119 adapter 子プロセス終了の観測

- 起点: origin/main a73d1c0 (#118 マージ済み)。専用 branch/worktree のみ編集する。
- 原因: call_script が subprocess.returncode を参照せず、exit 42 を成功扱いする。
- 既存 adapter 内に集約し、汎用 runtime・新規依存は追加しない。関連 ADR 0001 は対象外。
- 起動前の不存在・実行権なしは既存 missing_script、OS の起動例外は既存 script_failed。
- returncode > 0 は script_nonzero_exit、< 0 は script_signaled として既存 record_skip に一度計数する。終了番号・シグナル番号・本文は保存しない。
- ユーザー確定: 異常終了時は有効な拒否 JSON のみ採用し、通知 JSON・通常テキスト・不正出力は破棄する。adapter 自体は exit 0。
- 有効な拒否は hookSpecificOutput が object、permissionDecision が deny、任意の reason/context が未指定/null/文字列であるもの。理由省略の拒否も保持する。
- 正常終了時の通知・テキストを維持する。利用するフィールドが不正な JSON は bad_output とし、他ファイルで得た拒否を消さない。
- apply_patch はファイルごとに処理を続け、部分失敗の前後で得た拒否を集約する。空パスの不正入力も既存拒否を消さない。
- 子入力の UTF-8 変換失敗はファイル単位の bad_output として隔離し、既存結果の集約を続ける。
- JSON 出力は ASCII エスケープを使い、reason/context 内の孤立サロゲートでも出力段階で拒否を失わない。JSON 解析後の値は維持する。
- 状態形式・集計キー・doctor の汎用読取処理は変更しない。stderr は DEVNULL のまま。
- 手順: テスト観点 → 設計確認 → 実経路の失敗テスト → 最小実装 → Mac 全9契約テストと Linux/Python3.12 の追加ケース → 静的検査 → 新しい文脈の独立レビュー → 明示ステージ・commit・push・日本語 PR。
- README、CHANGELOG、3 manifest は 0.74.0 に同期。生成物は --check で検証し、入力が変わらなければ変更しない。評価対象プロンプトは変更しない。
- テストは所有する一時ルートと子プロセスのみを使う。HOME/config/state/tmp を隔離し、本物の設定や他セッションに書かない。

## main追従

PR #146・#147・#148のマージ後、origin/main `4cd67e0` (0.73.0) を統合。既存のREADME・CHANGELOG・manifestの変更を保持し、本件の資産版を0.74.0へ変更する。#119のadapterと契約テストの実装は、追加独立レビュー済みコミット `8773dfb` から変更しない。統合後の全9契約テストとCIを再検証する。
