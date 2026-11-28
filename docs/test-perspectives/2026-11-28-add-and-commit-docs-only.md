# テスト観点: git add と git commit を1回で実行する文書だけのコミット (#197)

対象: `docs/superpowers/specs/2026-11-28-add-and-commit-docs-only-design.md`。実装は `hooks/scripts/tool-reminder.sh` の `added_paths`・`remind_test_perspectives`、テストは `tests/hook-contract-test.sh`。

## 1. 正常系

| 観点 | 優先度 |
|---|---|
| `git add docs/x.md && git commit` (staged は空) で通知を出さない | must |
| 複数の文書の add、heredoc のコミットメッセージでも出さない | should |
| `cd docs && git add x.md`・`git -C <repo> add` のディレクトリから解決する | should |
| `./docs/x.md` は文書として扱う | should |

## 2. 境界値 (ECP 適用: 文書 / コード / 不明)

| 観点 | 優先度 |
|---|---|
| コードを add すれば通知を出す | must |
| 文書とコードを一緒に add すれば通知を出す | must |
| staged にコードがあり、文書だけを add しても通知を出す | must |
| `docs/../src/app.sh` は畳み込んでコードとして扱う | must |

## 3. 異常系 (判定できない add は通知を出す側に倒す)

| 観点 | 優先度 |
|---|---|
| リポジトリの外 (`../outside.md`)・magic pathspec (`:/docs`) | must |
| シェルが展開する文字 (`$X`・`$(…)`・`~`・`{x,y}`) を含むパス | must |
| `AIDD_DISABLE_GIT_SAFETY=1` のもとでの `git add -A` | must |
| staged に文書があり、名指ししない `git add -p` | must |

## 4. 状態遷移

| 観点 | 優先度 |
|---|---|
| commit の後ろにある add は、その commit に足さない | must |
| 別のリポジトリでの文書の add は、このリポジトリの commit に足さない | must |

## 5. 回帰

| 観点 | 優先度 |
|---|---|
| staged の文書だけのコミットは、今までどおり出さない | must (テストを追加) |
| add の無い commit の通知と、6時間以内の観点の保存で黙る挙動は変わらない | must (カバー済み: 27・428-434行目付近) |
| `git add -A` などの拒否 (`deny_unsafe_git`) は変わらない | must (カバー済み: 既存の拒否のテスト) |

## 6. フレームワーク結合

なし (hook を実際に起動するテストで、mock を使わない)。

負荷・性能テストはスコープ外。
