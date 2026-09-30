---
name: issue-priority
description: Use when asked to set, review, or triage the priority label of GitHub issues, or when about to file a GitHub issue (gh issue create) in a repository that uses priority labels (AIDD_REQUIRED_LABEL_PREFIX is set, .aidd/issue-priority.md exists, or gh label list shows priority labels). Not for ordering implementation tasks inside a plan.
---

# issue の優先度の判定

issue を読んで優先度ラベルを判定し、付ける。基準は「重要だから上げる」ではなく「**待たせられないから上げる**」。重要でも待てるものは上げない。

## 何もしない条件

優先度の付与や見直しを明示的に頼まれていない起票では、次の3つがすべて当てはまれば何もしない (判定もラベル作成の提案もせず、そのまま起票する)。優先度ラベルを使っていないリポジトリで、起票のたびに判定と確認を挟まないため。

1. `AIDD_REQUIRED_LABEL_PREFIX` が未設定
2. 利用側リポジトリに `.aidd/issue-priority.md` が無い
3. `gh label list --search priority` に優先度ラベルが無い

## 先に確かめること

1. **系列が独自のラベル運用を宣言していないか**。利用側リポジトリの `CLAUDE.md`・`CONTRIBUTING.md`・`.github/` の issue テンプレートに優先度ラベルの規約があれば、それに従い、この skill の段数と名前で上書きしない。
2. **追加の軸の定義**: `.aidd/issue-priority.md` があれば読み、そこで定義されたラベル名・段数・追加の軸 (例: 顧客影響、法令期限) を下の既定より優先する。
3. **既存のラベル**: 対象 issue に優先度ラベルが既に付いていれば、黙って張り替えない。判定が違う場合は、現在のラベル・判定・根拠を並べて確認してから変える。

## 既定のラベル (4段)

| ラベル | 意味 |
|--------|------|
| `priority:P0` | 今の作業を止めて対応する。待つほど損害が広がる |
| `priority:P1` | 次に着手する。待つと期限や他の作業が詰まる |
| `priority:P2` | 通常の順番で扱う。待っても損害が増えない |
| `priority:P3` | 余裕があれば扱う |

段の順序は `P0` が最上位で、数字が大きいほど下位 (`P0` > `P1` > `P2` > `P3`)。`.aidd/issue-priority.md` で段を定義した場合は、そこに並べた順で上位から下位とする。

## 判定

深刻さと広さの2軸で出発点を決め、放置コストで上げる。

- **深刻さ**: データ消失・セキュリティ・機能停止 > 回避策のない不具合 > 回避策のある不具合・不便 > 見た目・文言
- **広さ**: 全利用者・全セッション > 一部の利用者・特定の設定 > 特定の条件でだけ起きる > 報告者だけ
- 各軸の4段のうち、先頭の2段を上位、残りの2段を下位とする (例: 広さの「一部の利用者・特定の設定」は上位、「特定の条件でだけ起きる」は下位)。
- 両方が上位なら P1、片方だけなら P2、両方とも下位なら P3 を出発点にする。
- **放置コスト**: 待つと増えるもの (損害の拡大、期限、他の issue や作業のブロック、回避の手間の累積) があれば1段上げる。無ければ、深刻でも上げない。

判定には根拠を1行ずつ添える (深刻さ・広さ・放置コストのそれぞれ)。issue の本文から読み取れない軸は「不明」と書き、推測で上げない。

## 付けるとき

- **最上位 (`P0`、または系列の最上位) は自分だけで付けない**。根拠を示してユーザーに確認し、了承を得てから付ける。
- 新規の起票は `gh issue create --label <ラベル>` で付ける。既存の issue は `gh issue edit <番号> --add-label <ラベル>` (張り替えは確認後に `--remove-label` と併用)。
- リポジトリにそのラベルが無ければ、勝手に作らない。作るかどうかの確認は、優先度の付与や見直しを明示的に頼まれたときだけ行う (起票のついでには提案しない)。
- `AIDD_REQUIRED_LABEL_PREFIX` が設定されていると、`tool-reminder.sh` はその接頭辞のラベルが無い `gh issue create` を拒否する。拒否されたら、この判定をしてからラベルを付けて起票し直す。
