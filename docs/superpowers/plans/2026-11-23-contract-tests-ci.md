# #117 CI契約テスト Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 既存CIを維持し、現行の契約テスト9本でLinux/macOSの回帰を検出する。

**Architecture:** 既存validateとは別に、OS×テストのmatrixジョブを追加する。テスト方式は維持し、OS依存のPython不在模擬だけを専用PATHへ修正する。汎用runnerは追加しない。

**Tech Stack:** GitHub Actions、Bash、Python 3.12、Git。

**Spec:** Issue #117、依頼者の衝突回避・公開範囲の指示、`docs/test-perspectives/2026-11-23-contract-tests-ci.md`。参考設計書は別worktreeのため読み取り専用で参照した。

## Global Constraints

- 専用ブランチ `fix/issue-117-contract-tests-ci`、起点 `08c94cd`。他worktreeは編集しない。
- `.github/workflows/validate.yml` と `.claude/CLAUDE.md` が配線と説明、`tests/hook-contract-test.sh` がOS非依存のfixture、上記観点文書と本計画が証跡を担う。
- 資産・manifest・生成物の変更は不要。マージ・リリース・再インストール・共有設定変更はしない。
- PR作成は許可済み。実装はこのセッションで行い、独立レビューは新しい文脈へ依頼する。

## Review Focus

- 9本とmatrix一覧の不一致: ファイル一覧との構造比較で検出する。
- 非0終了の握り潰し: 実行ブロックをexit 42 fixtureで検証する。
- HOME/stateの漏れ: 専用rootを検査し、自分のrootだけのcleanupを確認する。
- LinuxのPython不在模擬: 旧ケースの失敗を再現し、専用PATHへ変更して両OSで検証する。
- シグナルのOS差: hook-logを実Actionsの両OSで実行する。

## Task 1: CIへの配線と移植性の修正

- [x] 更新前のworkflow構造検査がcontract-tests不在で失敗することを確認する。
- [x] Python不在ケースがLinuxで失敗することを確認する。
- [x] contract-testsへubuntu-latest/macos-latest×現行9本、fail-fast=false、Python 3.12、10分timeout、分離rootでの直接Bash実行を追加する。
- [x] Python不在の専用PATHを既存ケース間で利用し、アサーションを維持する。
- [x] `.claude/CLAUDE.md` のCI説明・テスト一覧・ローカル実行上の注意を配線に合わせる。
- [x] 構造検査、成功/失敗fixture、全9本、ShellCheck、生成物check、manifest validateを実行する（ローカルmacOS）。
- [ ] 独立レビューのhigh/blocking midを解消する。終了条件は連続2ラウンドでhigh/blocking midが0件、最大3ラウンド。
- [ ] 自分の5ファイルだけを明示ステージしてコミット・pushし、日本語PRを作成する。
- [ ] GitHub Actionsの全18組合せと既存validate成功を確認し、結果を報告する。

## 方式判断と実装前レビュー

2 OSの単一ループよりテスト別matrixを採用する。個別結果を識別でき、fail-fast=falseで失敗後も他の対象を確認できるため。既存validateジョブをmatrix化するとCLI導入等を重複するため分離する。

実装前の独立レビューでは、CI保持・分離・失敗伝播・対象9本の方針は妥当、Python不在模擬のLinux非互換がmidと判定された。使い捨てLinuxで再現したため、fixtureのみの修正を本計画へ追加した。依頼者からPR #139マージ済み・今後他ファイルの変更なしと回答を得て再開した。

## ローカル検証記録

- workflow構造検査: 追加前はcontract-tests不在で失敗、追加後は既存validate保持・9本×2 OS・fail-fast=false・分離設定を確認して成功。
- Actionsと同じBash実行ブロック: 成功fixtureは0、失敗fixtureは42を返し、どちらも自分のrootを削除。
- macOSの全9本: 同じ実行ブロックで終了コード0。
- Python不在の前提確認: Bash 3.2の親シェルのコマンドキャッシュを避け、新しい子Bashで判定。専用PATHにPythonを混入すると終了1になることを確認。
- actionlint v1.7.12、既存CI対象のShellCheck、生成物2種のcheck、manifest strict検証: 成功。manifestには既存のアイコン未設定警告あり。
- 追加でテスト本体にもShellCheckを実行。既存の模擬コマンド文字列へのSC2016/SC2088以外は指摘なし（これらを除外した検査は成功）。既存CIの対象・設定は変更しない。

独立レビューの最終結果、push・PRと実Actionsの結果はPR本文に記録する。プロンプト資産を変更しないためevalは対象外。適用先アプリのE2E・移行・性能検証も本CI変更では対象外とする。
