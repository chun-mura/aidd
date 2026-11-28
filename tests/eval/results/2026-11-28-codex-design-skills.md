# Codex の issue-implement は test-perspectives・design-doc・design-review を使えるか (#205)

#196 (0.95.0) で、Claude Code 側は3つの skill をモデルから起動できるようにした。Codex 側の `skills/<name>/agents/openai.yaml` は `policy.allow_implicit_invocation: false` のままで、Codex の `$aidd:issue-implement` が3つを使えるかは測っていなかった。**直行レーン・設計レーンとも有効な試行は1〜2回**なので、結果は参考値である。

## 条件

| 項目 | 値 |
|---|---|
| 日時 | 2026-11-28 |
| CLI | codex-cli 0.163.0。`codex exec --json -s workspace-write -c allow_login_shell=false --add-dir <fixture> -C <repo> '$aidd:issue-implement <番号>'` (stdin は `/dev/null`) |
| モデル | 利用者の `~/.codex/config.toml` の既定 (`model = "gpt-6.1-sol"`、`model_reasoning_effort = "low"`) |
| aidd | 利用者の Codex に導入済みの aidd 0.97.1 (`codex plugin list` で `installed, enabled`)。この測定時点の main と同じ skill。Codex の設定・プラグインは変えていない |
| 認証 | 既存の Codex の認証をそのまま使った。資格情報ファイルは読んでいない |
| 対象 | 実行ごとに作り直す使い捨てのローカル repo (架空の `wordfreq`: Python の関数1つとテスト1件、リモート無し) |
| gh | PATH の先頭に置いたスタブ。`gh issue view 1` と `gh issue view 2` にだけ本文を返し、ほかは失敗する。GitHub には何も書いていない |
| issue | 1 (直行): `top_words` が大文字と小文字を別の語として数える。2 (設計): `python3 -m wordfreq FILE [--top N]` の CLI を足す (エントリポイントの追加なので設計レーン) |

### 条件を変えた理由

- **login shell**: Codex は既定で `zsh -lc` でコマンドを実行する。login shell が `/etc/paths.d` から PATH を組み直し、スタブより Homebrew の `gh` が先になった (direct1・design1)。実 `gh` はリモートの無い repo で `no git remotes found` で失敗し、issue-implement は手順どおり `blocked/gh_unavailable` で止まった (書き込みは無し)。以降は `-c allow_login_shell=false` でスタブを使った
- **issue 2 の本文**: design2 は、入力の文字コード (UTF-8 固定か環境の既定か) を仕様の選択として `needs_input/spec_choice` で止まった。手順どおりの停止で、design-review まで進まなかったので、design3 以降は本文に「FILE は UTF-8 として読む」を足した
- **`--ephemeral`**: design3 は、design-review の Agent 6 (外部入力を扱うとしてセキュリティ担当) を subagent で起動しようとして、`collab spawn failed: ... no rollout found for thread id` で2回失敗し、`blocked/incomplete` で止まった。セッションを保存しない `--ephemeral` では Codex の subagent が親のセッションを読めないため。design4 は `--ephemeral` を外した

## 結果

Codex には Claude Code の Skill ツールにあたる呼び出しが無い。モデルは skill の SKILL.md をシェルで読んで (`cat <plugin>/skills/<name>/SKILL.md`) 手順に従う。ここでは「SKILL.md を読み、その手順の成果物を残した」ことを起動とみなした。

| 実行 | issue | 所要 | 読んだ3つの SKILL.md | 成果物 | outcome |
|---|---|---|---|---|---|
| direct1 | 1 | 24秒 | なし | なし | `blocked/gh_unavailable` (実 gh。上の login shell) |
| design1 | 2 | 22秒 | なし | なし | `blocked/gh_unavailable` (同上) |
| direct2 | 1 | 142秒 | test-perspectives | テスト観点 (`docs/test-perspectives/`)、計画、テスト2件と修正、完了報告。テストは全件通過 | `done` |
| design2 | 2 | 66秒 | design-doc、design-review | 設計書 | `needs_input/spec_choice` (文字コード) |
| design3 | 2 (UTF-8 を明記) | 90秒 | design-doc、design-review、test-perspectives | 設計書、テスト観点。design-review は直接レビューまで進み、Agent 6 の subagent の起動で失敗 | `blocked/incomplete` (上の `--ephemeral`) |
| design4 | 2 (UTF-8 を明記) | 262秒 | design-doc、design-review、test-perspectives | 設計書、design-review 2ラウンド (high・blocking mid なし)、テスト観点、計画、CLI とテスト14件の追加、完了報告。テストは15件通過。subagent の起動の失敗は無し | `done` |

- `allow_implicit_invocation: false` のままでも、`$aidd:issue-implement` の手順が3つを指すと、モデルは issue-implement の SKILL.md の場所からプラグインの `skills/` を探して3つの SKILL.md を読み、手順に従った。#196 の Claude Code (0.94.0) のように起動が拒否されて止まることは無かった
- `allow_implicit_invocation` が効くのは、依頼の内容から skill を選んで暗黙に起動するかどうかで、ほかの skill の手順から SKILL.md を読むことは妨げない。設定は変えない (`true` にすると、Codex でも、issue-implement の外で依頼の内容から3つが選ばれうる。#204 で Claude Code について測った起動しすぎの心配が Codex にも広がる)
- 試行で止まった理由 (gh の解決、仕様の選択、`--ephemeral` での subagent) は、どれも3つの skill の起動の問題ではない

## 費用

Codex はサブスクリプションの枠で動かしたので、金額は出ない。`turn.completed` の `usage` (トークン数) は次のとおり。

| 実行 | input (うち cached) | output (うち reasoning) |
|---|---|---|
| direct1 | 131,085 (104,704) | 601 (24) |
| design1 | 98,280 (79,360) | 570 (10) |
| direct2 | 940,043 (880,896) | 5,185 (375) |
| design2 | 221,602 (178,432) | 2,217 (125) |
| design3 | 370,742 (323,072) | 3,229 (277) |
| design4 | 1,533,752 (1,465,600) | 9,946 (674) |

## 限界

- 各レーン有効な試行は1〜2回。モデルが SKILL.md の場所を自分で探しているので、プラグインの配置や手順の書き方が変わると探せない可能性はある
- モデルは利用者の既定 (reasoning effort `low`) で、ほかの設定では測っていない
- `codex exec` の非対話だけで、Codex の対話 (TUI) は測っていない
- HOME と Codex の設定は分離していない (利用者が導入済みの superpowers などのプラグインが効いている)

## 残していないもの

- `events.jsonl` と使い捨ての repo は、利用者の環境のパスを含むので保存していない
