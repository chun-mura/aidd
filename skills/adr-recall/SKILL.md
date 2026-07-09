---
name: adr-recall
description: Use when making an architectural decision, changing existing structure, or proposing a design that could contradict a past decision. Checks docs/adr/ for related ADRs before proceeding.
---

# ADR 想起

アーキテクチャ変更・既存構造の変更・設計判断を行う前に、`docs/adr/` にある既存の決定と矛盾しないか確認する。

## 手順

1. `docs/adr/` が存在しなければ何もしない (ADR運用のないプロジェクト)。
2. 存在すれば、今行おうとしている変更のキーワード (コンポーネント名・技術選定・パターン名) で ADR ファイルをgrepし、関連する ADR を洗い出す。
3. 関連 ADR が見つかった場合:
   - 今回の変更が ADR の「決定」と一致するなら、そのまま進める (言及不要)。
   - 矛盾する場合は、進める前にユーザーに提示する: 「`<ADR番号>` は `<決定内容>` としているが、今回の変更はそれと矛盾する。意図的な変更か確認したい」
   - 意図的な覆しと確認できたら、`/aidd:adr` で新しい決定を記録し、旧 ADR を superseded に更新することを提案する。
4. 関連 ADR がなければ、そのまま進める (言及不要)。

## 注意

- ADR の内容を読み違えて誤検知するより、判断に迷う場合はユーザーに確認する側に倒す。
- 矛盾の指摘は提示のみ。ファイル変更はユーザー承認後、`/aidd:adr` に委ねる (このスキル自身は ADR を書かない)。
