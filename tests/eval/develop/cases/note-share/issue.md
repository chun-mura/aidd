title:	メモを所有者と共有先だけが読めるようにし、共有できるようにする
state:	OPEN
author:	example-user
labels:	enhancement
comments:	0
number:	1
--
## 背景

今は `NoteService.read` がメモの所有者を確かめないので、ログインした利用者なら誰でも他人のメモを読める。また、メモをほかの利用者に見せる手段が無い。

## 受け入れ基準

1. メモの所有者は自分のメモを読める
2. 所有者は `NoteService.share(user, note_id, target)` で、ほかの利用者 `target` にメモを共有できる。共有された利用者はそのメモを読める
3. 所有者でも共有先でもない利用者が読もうとしたら、`notes.service.PermissionDenied` を出す
4. 所有者でない利用者 (共有先を含む) が共有しようとしたら、`PermissionDenied` を出す
5. 存在しないメモは、読む・共有のどちらでも `NotFound` を出す (社内ツールなので、メモの有無を隠す必要は無い)
6. 既存のテストは通ったままにする

## 範囲外

- 共有の取り消し、HTTP のハンドラ、永続化 (ストアはメモリ上のまま)
