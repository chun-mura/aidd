# #118 共有状態の失敗隔離 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 共有通知・記録の破損やロック待ちで、計算済みの拒否出力を失わないようにする。

**Architecture:** 既存dispatcherの `update_state` をbest-effort境界とし、トップレベルを辞書へ正規化し、ロックは非ブロッキング取得＋単調時計による100ms上限で待つ。main-treeの既存trees/warned形式は変更せず、不正な下位型・時刻を除去する。時刻の検証を既存issue-searchにも適用する。

**Tech Stack:** Bash、Python標準ライブラリ（fcntl/time/json）、Git。新しいruntime・依存は追加しない。

**Spec:** Issue #118、既存harness改善設計のT02、`docs/test-perspectives/2026-11-23-state-safety.md`。既存ADRに反する決定はない。

## Global Constraints

- 専用ブランチ `fix/issue-118-state-safety`、専用worktree、#117マージ後のmain `e5046c6` を使用する。他worktreeや共有設定は変更しない。
- 主な配置は `hooks/scripts/tool-reminder.sh` と `tests/hook-contract-test.sh`。README・CHANGELOG・3種類のmanifestを0.70.0へ揃える。生成物はcheckし、入力が変わる場合だけ再生成する。
- 永続化フィールド、既存の拒否条件、dispatcher統合、通常のfail-open方針を変更しない。ロックを取得できなければ状態を更新せずNoneを返す。
- 既存検索ゲートは状態確認不能なら従来どおり検索を要求する。best-effort失敗を検索済みとは扱わない。
- マージ・リリース・再インストールは行わず、検証・独立レビュー・コミット・push・日本語PRまでとする。

## Review Focus

- 状態更新callbackの例外が最終JSONまで伝播しないこと。
- bool/NaN/Infinity/巨大整数や不正な下位mapで型エラー・算術エラーを起こさないこと。
- 有効なpeerと警告済み記録を保ち、相手の占有が続く限り警告を繰り返さないこと。
- ロック取得失敗で他のwriterの状態・一時ファイルを触らず、取得したロックをcloseで解放すること。
- 共通helperの全呼出元（main-tree、issue-search、commit-why）を確認し、拒否・通知の意味を変えないこと。

## Task 1: 回帰テストと最小修正

- [x] 契約テストへ状態破損・書込失敗・ロック保持/回復・並行更新・sentinel検査を追加し、旧実装でREDを確認する。
- [x] update_stateに辞書正規化・非ブロッキングロック・100ms上限・記録例外隔離を追加する。
- [x] main-treeのtrees/warnedと必要な下位型・時刻を正規化し、有効な記録は維持する。
- [ ] 追加fixtureと全9本を分離環境で実行し、Linux/macOSの実CIでも確認する。
- [x] READMEへ失敗時の挙動と上限を記載し、CHANGELOGとmanifest3種を更新する。
- [x] ShellCheck・生成物2種check・manifest検証を実行する。
- [ ] 新規文脈で独立レビューし、high/blocking midが2回連続0件（最大3回）となることを確認する。
- [ ] 自分のファイルだけを明示ステージしコミット・push・日本語PRを作成する。

## レーンと方式判断

既存の拒否条件・状態形式・エントリポイントを維持するbugfixとして直行レーンとする。状態更新を別runtimeへ分離する案は既存の統合方針とスコープに合わない。広い例外隔離は記録helperの境界だけに限定し、安全判定そのものを包括的に握り潰す変更はしない。100msは1回の状態ロック取得の上限であり、Git照会・OSのファイルI/Oやhook全体の実行時間を保証する値ではない。

## レビューによる横展開と検証

- 第1回の独立レビューで、issue-searchの巨大整数によるOverflowErrorとNaN/Infinityによる検索要求の欠落を検出。独立したrefuterでも反証できず、実dispatcherのcompound入力で拒否消失を再現した。共通の時刻検証を検索確認と検索記録の掃除にも適用し、不正な記録から通常の検索・起票へ回復するfixtureを追加した。
- 型・時刻検証で比較する現在時刻はロック取得後に採り、待っている間に別writerが書いた正常な時刻を誤って除去しない。
- 並行fixtureでは記録に成功したことを警告出力から確認し、その記録を保持する。100ms待ちの時間切れによる記録省略は許容し、後の再実行で回復することを検査する。
- 旧main-treeの不正JSON外形でRED、修正後にfixture成功。例外隔離をOSErrorだけへ戻した一時コピーでも、callback例外による出力消失を検出してREDを確認した。
- 初回のローカル全9本・Linux限定fixture・既存静的検査は成功。横展開修正後も全件を再実行し、最終結果はPR本文に記録する。生成物入力は変更せず、2種のcheckが成功しているため生成物の差分は不要。
