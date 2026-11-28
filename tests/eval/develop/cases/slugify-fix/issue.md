title:	slugify が記号の連続や前後の記号でハイフンを重ねる
state:	OPEN
author:	example-user
labels:	bug
comments:	0
number:	1
--
## 現象

`slugify("Hello,  World!")` が `hello---world-` を返す。ページの URL に使うと読みにくい。

## 受け入れ基準

1. 英数字以外の文字が続く箇所は、ハイフン1つにまとめる (`slugify("Hello,  World!")` は `hello-world`)
2. 先頭と末尾にハイフンを残さない (`slugify("  -Draft- ")` は `draft`)
3. 英数字を1文字も含まない入力は空文字を返す (`slugify("!!!")` は `""`)
4. 英字は今までどおり小文字にする。既存のテストは通ったままにする

## 範囲外

- 英数字以外の文字 (日本語など) を残す・読み替える対応はしない
