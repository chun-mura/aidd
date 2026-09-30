---
description: 利用側プロジェクトの .claude/ と CLAUDE.md を棚卸しし、削除・改訂・修正の候補を出す
disable-model-invocation: true
---

利用側プロジェクトの `.claude/` と `CLAUDE.md` を棚卸しし、削除・改訂・修正の候補を提示してください。判断は提示のみ。ユーザーの承認なしにファイルを変更しない。

**いつ使うか**: 規約とフックは事故のたびに足されて単調に増える。読まれるが守られない記述は、生きている規約の重みまで下げるため、定期的に削る入口として使う。SessionStart の nudge が期限切れを知らせたときも使う。

**`/aidd:retro` との違い**: `retro` は **aidd 自身の資産** (aidd のコマンド・hooks・skills) を利用記録で棚卸しする。このコマンドは同じ型を **利用側プロジェクトの資産** (そのリポジトリの `CLAUDE.md` と `.claude/` 配下) に当てる。静的解析・CI の導入状況は `/aidd:infra-audit` の担当。事故から規約を足す側は `/aidd:incident-retro` の担当。

このコマンドはモデルが自分で起動しない (`disable-model-invocation`)。正典から記述を削る判断を、モデルが自分の判断の続きとして始めないため。

**1. 対象の列挙**

プロジェクトルートから以下を列挙し、各ファイルの最終変更コミット (`git log -1 --format='%h %ad' --date=short -- <path>`) を添える:

- `CLAUDE.md` (ルート・`.claude/CLAUDE.md`・サブディレクトリの `CLAUDE.md`)
- `.claude/settings.json` の `hooks` / `permissions` / `env` (`.claude/settings.local.json` は個人設定のため、存在だけ示し中身は候補にしない)
- `.claude/commands/`・`.claude/skills/`・`.claude/agents/`・`.claude/rules/`・`.claude/hooks/` 配下のファイル

**2. hook の発火記録の読み取り**

`aidd-hook-log.sh` (aidd の `templates/` から利用側へ導入するラッパー) で包まれた hook だけが発火を記録する。記録は次の場所にある:

```bash
project_key=$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | tr -c 'A-Za-z0-9' '-')
log_dir="$HOME/.claude/aidd/projects/$project_key/hook-log"
ls -la "$log_dir" 2>/dev/null          # <hook-id>.jsonl と、記録開始を示す .since
tail -n 1 "$log_dir"/*.jsonl 2>/dev/null   # 各 hook の最終発火
grep -c '"status":"error"' "$log_dir"/*.jsonl 2>/dev/null
```

`.claude/settings.json` の各 hook について、コマンド行の `aidd-hook-log.sh <hook-id>` から id を読み、記録と対応づける。1行は `{"ts","event","status","exit"}` で、`status` は `ok` (終了コード0)・`block` (2、意図した阻止)・`error` (それ以外) のいずれか。

**3. 判定基準**

各候補には根拠 (`ファイル:行`、記録の行、コミット) を必ず添える。根拠を示せないものは候補にしない。期間の既定は30日 (`AIDD_AUDIT_INTERVAL_DAYS` が設定されていればその値)。

| 基準 | 判定 | 区分 |
|------|------|------|
| 一定期間発火しない hook | `.since` が期間より古く、その hook の最終発火が期間より古い (または記録が無い) | 削除候補 |
| 記録が壊れている hook | `error` 行を持つ | **修正候補** (削除ではない。発火していても失敗しているなら、守らせたい規則が効いていない) |
| ラッパー未導入・記録開始から期間未満の hook | 発火を判定できない | 判定不能 (削除候補にしない) |
| 参照先が消えた | 記述が指すパス・コマンド・スクリプト・ツールが存在しない | 改訂候補 |
| 状態を述べる記述が食い違う | 「〜を使っている」「〜は無い」などの記述が現物と合わない | 改訂候補 |
| 前提が変わった | 記述の理由になった制約・ツール・構成が既に無い (`git log` で導入時の理由を確かめる) | 改訂 or 削除候補 |
| 上流に吸収された | Claude Code 本体・導入済みプラグイン・linter / formatter の設定が同じことを既に強制している | 削除候補 |
| 2箇所に同じ基準がある | 同じ規則が `CLAUDE.md` と `.claude/` 配下 (または複数の `CLAUDE.md`) にある | 統合候補 (正典を1箇所に決め、他方を削る) |
| 観測1件からの一般化 | 1回の事故から一般則にした記述で、その後に同種の事例が無い (`git log -S` で導入コミットと経緯を確かめる) | 見直し候補 |

**候補が0件なら基準を疑う**: 「問題なし」で終えない。規約は増える一方なので、0件は基準が緩いか根拠が集まっていない兆候として扱う。どの基準で根拠が欠けていたか (例: hook がラッパーで包まれていない、記録開始から期間未満、`git log` が浅い) を挙げ、基準を締めるならどれか、根拠を集めるには何が要るかを報告する。

**4. 出力と実施**

「削除候補」「改訂候補」「修正候補」「統合候補」「見直し候補」「判定不能」の区分で一覧にし、実施するものを AskUserQuestion で確認する。承認されたものだけ変更する。

- 削る・残すの判断に理由を残すべきもの (例: 別の場所で強制されているから削った) は `/aidd:adr` に委ねる
- その場で直さない修正 (壊れた hook の修正など) は `/aidd:issue-split` か issue に委ねる
- ADR・issue の書式や中身はこのコマンドで複製しない

**5. 実施日の記録**

提示を終えたら (承認の有無に関わらず) 実施日を記録する。SessionStart の nudge はこの日付から期間が過ぎたときだけ出る:

```bash
project_key=$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | tr -c 'A-Za-z0-9' '-')
state_dir="$HOME/.claude/aidd/projects/$project_key"
mkdir -p "$state_dir" && date +%F > "$state_dir/asset-audit.last"
```

`CLAUDE_PROJECT_DIR` が無い環境ではプロジェクトルートで実行すること (nudge とラッパーも `${CLAUDE_PROJECT_DIR:-$PWD}` から同じ規則でキーを作る)。
