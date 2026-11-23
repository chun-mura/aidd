# #117 CI契約テストのテスト観点

出典: [Issue #117](https://github.com/chun-mura/aidd/issues/117) と依頼者の指示。起票時の7本ではなく、最新main `08c94cd` の9本を実行条件・副作用から確認した。

| 分類 | 優先度 | 観点 | 検証方法 |
|---|---|---|---|
| 正常系 | must | 対象9本すべてがLinux/macOSで成功する | GitHub Actionsの全18組合せ。ローカルでも分離実行 |
| 異常系（ECP適用） | must | テストの非0終了がジョブ失敗になり、他の組合せは中止されない | workflow構造検査と実行ブロックへのexit 42 fixture投入 |
| 状態遷移・並行実行 | must | HOME・設定・状態・一時領域を分離し、利用者や他セッションのファイルを変更しない | 各テストの書込先監査、専用rootと状態の確認、終了後のroot削除確認 |
| 回帰 | must | 既存validateジョブのShellCheck・生成物2種・CLI導入・manifest検証を維持する | 更新前後のvalidateジョブを構造比較し、既存検査も実行 |
| フレームワーク結合 | must | 実際のActionsでmatrixが展開され、シグナル・一時領域を扱うテストも動く | 実GitHub ActionsのLinux/macOS結果（mockレス） |
| 回帰 | must | CI説明・対象一覧と実際の配線が一致する | `.claude/CLAUDE.md` とmatrixを照合 |
| 異常系（ECP適用） | must | Python不在の模擬がOSの `/bin/python3` の有無に依存しない | 既存hook-contractのno_python3記録・空出力・sentinel不在の検査を維持。Linux旧実装の失敗を再現済み |
| 運用 | should | Python版・ジョブの時間上限を明示する | Python 3.12・10分timeoutの構造検査 |

数値・長さ・日付境界を変更しないためBVAは非該当。プロダクトの信頼境界や権限を変更しない。性能目標は追加しない。

## 対象9本の実行条件と副作用

| テスト | 実行内容・依存 | 副作用とCI適性 |
|---|---|---|
| autonomous-review-contract | Bash/grepによる文言契約 | 読取のみ。モデルCLIを起動せずCI向き |
| command-contract | 文言契約、Pythonでdoctor等の抽出snippetを実行 | 架空設定・dummy token・一時repoを使用。外部APIへの書込なし |
| codex-agents-contract | Python生成物check、installerのコピーとstale/missing検出 | コピー先は一時dest/project。利用者のagentsへインストールしない |
| redundancy-contract | 文言と削除資産の静的検査 | 読取のみ |
| hook-contract | 偽イベントで実hook、Python、Gitの一時repo | HOME/state分離。入力コマンドは実行せず、Git変更は使い捨てrepoのみ。Python不在PATHの移植性だけ修正 |
| hook-log | 実wrapper、入出力・終了コード、SIGINT/TERM/KILL/PIPE、偽memory | 一時hookと自身の子PIDだけを操作。ログ・Git repo・memoryを分離 |
| session-start | 実hook、経過時間、Git common-dirキー | 偽project/stateを使用。冒頭のHOME読取も外側で分離 |
| incident-retro-memory | Python抽出snippetと台帳集計、Git | 偽memory・HOME・一時repo。利用者memoryを読み込まない |
| learnings | Python標準ライブラリの検査・opt-in・集計、Git | 架空JSONと一時repo。モデル・外部APIなし |

共通の依存はBash、Python 3.12、Git、標準Unixコマンド。既存テストのアサーションを削除せず、記述方式を維持する。各matrixジョブは専用の一時rootを持ち、Gitのglobal/system設定と実利用者のHOMEを引き継がない。
