# #119 テスト観点 (2026-11-23)

## 正常系
- must: exit 0 の空出力・通知 JSON・テキスト・拒否 JSON は従来の変換を保ち、異常終了を記録しない (ECP)。
- must: 同一原因の再実行は count を増やし、doctor の既存コードが理由と件数を表示する。

## 境界値
- must: returncode 0 / 正 / 負を区別する (BVA/ECP)。実際の exit 42 と自己 SIGTERM を使う。
- must: reason/context の孤立サロゲートは JSON エスケープされ、拒否と解析後の値を保持する。
- must: 拒否理由が省略・空でも拒否を保持する。非文字列 reason/context、非 object の hookSpecificOutput は有効な拒否と扱わない (ECP)。

## 異常系
- must: 子が非0終了・シグナル終了しても adapter は exit 0。空・通知 JSON・テキスト・不正 JSON は出力せず、理由を計数する。
- must: 非0/シグナル終了と有効な拒否 JSON の組合せは拒否を保持する。
- must: 実行権あり・不存在 interpreter の実起動失敗を script_failed、不存在/実行権なしを missing_script として区別する。
- must: apply_patch の前後の部分失敗 (起動失敗・不正出力・異常終了・空パス・UTF-8 変換不能な孤立サロゲート) が他ファイルの計算済み拒否を消さず、残りのファイルを処理する。

## 状態遷移
- must: 単一イベント・複数ファイルで原因ごとの count が正しく、同じ失敗を二重計数しない。
- should: 記録先に書けなくても拒否と adapter exit 0 を維持する。

## 回帰
- カバー済み: 実際の hooks.json / hooks-cursor.json の配線、Codex apply_patch と Cursor Shell/Write/Read/SessionStart の既存変換、no_python3 など (既存 hook-contract-test.sh)。
- must: 全9契約テスト・既存CI全19ジョブを維持する。

## 結合・セキュリティ
- must: mock ではなく adapter → 実子プロセス → stdout/終了ステータス → 記録 → doctor 読取の経路を検証する。Codex/Cursor の両方を使う。
- must: stderr、入力コマンド、stdout の秘密 sentinel が adapter-skips.json に保存されない。新しい記録は既存の限定メタデータのみ。
- must: HOME/config/state/tmp と Git 設定を分離し、シグナルは fixture 自身だけに送る。

負荷・性能評価は今回の対象外。子プロセスの timeout とロック設計の刷新も追加しない。
