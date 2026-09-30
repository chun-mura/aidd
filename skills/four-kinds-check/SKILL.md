---
name: four-kinds-check
description: Use right before git commit when the staged diff adds code comments or test names, or when drafting the commit message, in a project whose CLAUDE.md has the How / What / Why / Why-not comment placement rule or where AIDD_COMMIT_WHY_CANON is set. Not for reviewing someone else's existing code.
---

# 4分類 (How / What / Why / Why not) の確認

`templates/CLAUDE.md.template` の規約「コードには How、テストコードには What、コミットログには Why、コードコメントには Why not」を、これからコミットする変更に当てて確かめる。

## 正典

- 既定の正典は、利用側プロジェクトの `CLAUDE.md` の「コメントの置き場所」の節。環境変数 `AIDD_COMMIT_WHY_CANON` が設定されていれば (`echo "$AIDD_COMMIT_WHY_CANON"` で確かめる)、そこに書かれた文書と節を正典にする。
- 正典が見つからなければ、このプロジェクトは規約を採っていない。何もしない。
- 正典とこの skill が食い違えば正典に従う。

## 手順

見るのは今回**追加した行**だけ (`git diff --cached -U0` の `+` 行)。既存の行は対象外。

1. **コメント**: 追加したコメントを1つずつ分類し、Why not (自明な代替案を採らなかった理由) 以外は置き場所を移す。
   - How (実況型。`// ユーザーIDを取得する`) → 消す。コードが語る。伝わらないなら名前や構造を直す
   - What (期待する振る舞い) → テスト名かテストコードへ
   - Why (変更の理由・経緯。`// 〜を追加した`) → コミット本文へ
   - タスク ID (`// fixes JIRA-1234`) → issue / PR へ
2. **テスト名**: 追加したテストの名前が What (入力・条件と期待する結果) を言っているか。実装の手順 (How) や `test1` のような名前は、振る舞いを言う名前に直す。
3. **コミット本文**: 本文に Why (なぜこの変更が要るか、何が困っていたか) があるか。差分の言い換え (How) だけなら書き直す。件名は正典またはリポジトリの規約の形式に合わせる。

## 結果の扱い

- 自分がこのセッションで書いた変更なら、直してからコミットする。移した先 (コミット本文・テスト名) も同じコミットで整える。
- 判断に迷うコメント (Why と Why not の境目など) は、そのまま残して理由を1行で報告する。消しすぎより残しすぎの側に倒す。
- コミット後は `tool-reminder.sh` が HEAD を検査する。本文の有無は正典があるときだけ、件名の Conventional Commits 形式は `AIDD_COMMIT_TYPES` か commitlint の設定があるときだけ見る。この skill はその前段で、本文の中身 (Why かどうか) とコメント・テスト名を見る。
