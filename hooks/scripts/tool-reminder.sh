#!/bin/bash
# Event-aware Bash hook dispatcher (PreToolUse + PostToolUse). Every check runs in this one
# process and their verdicts are merged into a single JSON reply, because Claude Code reads one
# reply per hook run. Non-matching commands produce no output.
input=$(cat)

# Every check targets a git or gh invocation; anything else exits before python starts. Only
# the command is scanned (cwd and transcript_path often contain "git" or "gh"); a JSON escape
# such as "\n" before the word counts as a boundary. If the command cannot be cut out, python
# decides: a false match costs only time, a missed one loses the checks. (No ${var//...}
# here: bash 3.2 substitution is quadratic and stalls on long commands.)
command_pattern='"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
word_pattern='(^|[^[:alnum:]_-]|\\[a-z])(git|gh)([^[:alnum:]_-]|$)'
if [[ $input =~ $command_pattern ]]; then
  [[ ${BASH_REMATCH[1]} =~ $word_pattern ]] || exit 0
fi

# The payload stays on stdin (a command can exceed ARG_MAX, see usage-log.sh).
PY_CODE=$(cat <<'PYEOF'
import fcntl, glob, json, os, re, shlex, subprocess, sys, time

try:
    event = json.load(sys.stdin)
except Exception:
    sys.exit(0)

hook_event = event.get("hook_event_name") or ""
command = (event.get("tool_input") or {}).get("command") or ""
if not isinstance(command, str) or not command:
    sys.exit(0)
# CLAUDE_PROJECT_DIR stays on the main checkout inside a worktree; the input cwd follows it.
base_dir = event.get("cwd") or os.getcwd()
env = os.environ

denials = []
contexts = []


def add(bucket, text):
    if text not in bucket:
        bucket.append(text)


# --- command parsing: tokenize, split into simple commands, drop wrappers --------------------
# Not a shell parser. Quoted strings stay whole (so text inside -m "..." is never a command);
# commands joined by && || ; | & newlines or parentheses are checked one by one.
WRAPPERS = [["rtk", "proxy"], ["rtk"], ["command"], ["env"], ["time"], ["nohup"], ["exec"]]
# Extra wrappers: comma-separated, each may span words (e.g. "sudo -E,chronic").
WRAPPERS += [w.split() for w in env.get("AIDD_COMMAND_WRAPPERS", "").split(",") if w.strip()]
SEPARATOR_CHARS = set(";&|()\n")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def strip_heredocs(text):
    # Heredoc bodies are data (commit messages, file contents); drop them before tokenizing.
    lines = text.split("\n")
    kept = []
    i = 0
    while i < len(lines):
        kept.append(lines[i])
        delimiters = [m.group(2) for m in HEREDOC.finditer(lines[i])]
        i += 1
        for delimiter in delimiters:
            while i < len(lines) and lines[i].strip() != delimiter:
                i += 1
            i += 1
    return "\n".join(kept)


def strip_comments(text):
    # shlex's own comment handling starts a comment at any '#' (cd /x#y) and swallows the
    # newline that ends it, gluing the next line's command onto the comment. The shell only
    # starts one at an unquoted word-initial '#', and the newline still separates commands.
    out = []
    quote = None
    i = 0
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\" and quote == '"':
                out.append(text[i:i + 2])
                i += 2
                continue
            if c == quote:
                quote = None
        elif c == "\\":
            out.append(text[i:i + 2])
            i += 2
            continue
        elif c in "'\"":
            quote = c
        elif c == "#" and (i == 0 or text[i - 1] in " \t\r\n;&|()<>"):
            end = text.find("\n", i)
            if end < 0:
                break
            i = end
            continue
        out.append(c)
        i += 1
    return "".join(out)


def tokenize(text):
    lexer = shlex.shlex(text, posix=True, punctuation_chars=";&|()<>\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    try:
        return list(lexer)
    except ValueError:
        # Unbalanced quotes: fall back to whitespace words so obvious commands still match.
        return re.findall(r"&&|\|\||[;&|()\n]|[^\s;&|()]+", text)


# Words that can precede a command in a compound statement (if/then/do bodies, groups, !).
KEYWORDS = {"if", "then", "else", "elif", "while", "until", "do", "{", "!"}


def unwrap(argv):
    changed = True
    while argv and changed:
        changed = False
        while argv and (ASSIGNMENT.match(argv[0]) or argv[0] in KEYWORDS):
            argv = argv[1:]
            changed = True
        for wrapper in WRAPPERS:
            if argv[:len(wrapper)] == wrapper:
                argv = argv[len(wrapper):]
                while argv and (argv[0].startswith("-") or ASSIGNMENT.match(argv[0])):
                    argv = argv[1:]
                changed = True
                break
    return argv


def simple_commands(text):
    """Yield (argv, directory) for each simple command, following `cd` between them."""
    current = [[]]
    for token in tokenize(strip_comments(strip_heredocs(text))):
        if token and set(token) <= SEPARATOR_CHARS:
            current.append([])
        else:
            current[-1].append(token)
    directory = base_dir
    for words in current:
        argv = []
        skip = False
        for word in words:
            if skip:
                skip = False
            elif word and set(word) <= set("<>&") and ("<" in word or ">" in word):
                skip = True
            else:
                argv.append(word)
        argv = unwrap(argv)
        if not argv:
            continue
        if argv[0] == "cd" and len(argv) > 1 and argv[1] != "-":
            directory = os.path.join(directory, os.path.expanduser(argv[1]))
            continue
        yield argv, directory


GIT_OPTIONS_WITH_VALUE = {"-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}


def parse_git(argv, directory):
    i = 1
    while i < len(argv) and argv[i].startswith("-"):
        if argv[i] == "-C" and i + 1 < len(argv):
            directory = os.path.join(directory, os.path.expanduser(argv[i + 1]))
            i += 2
        elif argv[i] in GIT_OPTIONS_WITH_VALUE:
            i += 2
        else:
            i += 1
    if i >= len(argv):
        return None
    return {"dir": directory, "sub": argv[i], "args": argv[i + 1:]}


def option_values(args, long_name, short_name=None):
    values = []
    for i, arg in enumerate(args):
        if arg in (long_name, short_name) and i + 1 < len(args):
            values.append(args[i + 1])
        elif arg.startswith(long_name + "="):
            values.append(arg[len(long_name) + 1:])
        elif short_name and arg.startswith(short_name) and len(arg) > len(short_name) and not arg.startswith("--"):
            values.append(arg[len(short_name):])
    return values


def git(directory, *args):
    try:
        result = subprocess.run(
            ["git", "-C", directory, *args],
            capture_output=True, text=True, timeout=10,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def env_int(name, default):
    try:
        return max(int(env.get(name, "")), 1)
    except ValueError:
        return default


def env_regex(name, default):
    try:
        return re.compile(env.get(name) or default)
    except re.error:
        return re.compile(default)


def scan(args, short_with_value="", long_with_value=()):
    """Split git-style args into short flag letters, long flag names and positionals.

    Short clusters are read letter by letter (-am is -a -m); a letter that takes a value ends
    the cluster (-ma is -m "a"), and a value given as the next word is not read as a flag.
    """
    shorts, longs, positionals = set(), set(), []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            positionals.append("--")
            positionals.extend(args[i + 1:])
            break
        if arg.startswith("--"):
            name = arg.split("=", 1)[0]
            longs.add(name)
            if "=" not in arg and name in long_with_value:
                i += 1
        elif arg.startswith("-") and len(arg) > 1:
            for j, letter in enumerate(arg[1:]):
                shorts.add(letter)
                if letter in short_with_value:
                    if j == len(arg) - 2:
                        i += 1
                    break
        else:
            positionals.append(arg)
        i += 1
    return shorts, longs, positionals


STATE_DIR = env.get("AIDD_TEST_STATE_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "aidd")


def update_state(name, change):
    """Apply change(data) to ~/.claude/aidd/<name> under a lock; return what change returns."""
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        path = os.path.join(STATE_DIR, name)
        with open(path + ".lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                with open(path) as f:
                    data = json.load(f)
            except Exception:
                data = {}
            result = change(data)
            old_umask = os.umask(0o077)
            try:
                with open(path + ".tmp", "w") as f:
                    json.dump(data, f)
                os.replace(path + ".tmp", path)
            finally:
                os.umask(old_umask)
            return result
    except OSError:
        return None


# --- checks ----------------------------------------------------------------------------------
DOCS_ONLY = r"(^docs/|\.md$|\.txt$)"


def remind_test_perspectives(directory):
    staged = git(directory, "diff", "--cached", "--name-only")
    if staged and all(re.search(DOCS_ONLY, path) for path in staged.splitlines()):
        return
    perspectives = os.path.join(directory, "docs", "test-perspectives")
    for path in glob.glob(os.path.join(perspectives, "**", "*.md"), recursive=True):
        try:
            if os.path.getmtime(path) > time.time() - 360 * 60:
                return
        except OSError:
            pass
    add(contexts, "aidd: if /aidd:test-perspectives has not been run for this change, run it before committing (skip for docs-only or trivial changes).")


def resolve_commit(directory, names):
    for name in names:
        sha = git(directory, "rev-parse", "--verify", "--quiet", "--end-of-options", name + "^{commit}")
        if sha:
            return name, sha
    return None, None


def has_review_evidence(directory, head, head_sha):
    # autonomous-review writes under the worktree it ran in, which need not be this one.
    listing = git(directory, "worktree", "list", "--porcelain") or ""
    roots = [line[len("worktree "):] for line in listing.splitlines() if line.startswith("worktree ")]
    top = git(directory, "rev-parse", "--show-toplevel")
    if top:
        roots.insert(0, top)
    for root in dict.fromkeys(roots):
        for state_file in glob.glob(os.path.join(root, ".aidd", "autonomous-review", "*", "state.json")):
            try:
                with open(state_file) as f:
                    state = json.load(f)
            except Exception:
                continue
            if state.get("head") == head or head_sha in (state.get("head_sha"), state.get("head_sha_after_fixes")):
                return True
    return False


def warn_review_before_pr(args, directory):
    if env.get("AIDD_DISABLE_REVIEW_BEFORE_PR") == "1":
        return
    # The PR's branch is --head, not the cwd's HEAD: a PR opened from a worktree or the main
    # checkout often names a branch other than the one checked out here.
    heads = option_values(args, "--head", "-H")
    head = heads[-1].split(":", 1)[-1] if heads else git(directory, "symbolic-ref", "--quiet", "--short", "HEAD")
    if not head:
        return
    bases = option_values(args, "--base", "-B")
    base = bases[-1] if bases else env.get("AIDD_REVIEW_BASE")
    if not base:
        origin_head = git(directory, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
        base = origin_head.split("/", 1)[-1] if origin_head else None
    candidates = [base] if base else ["main", "master"]
    base_ref = None
    for candidate in candidates:
        base_ref, _ = resolve_commit(directory, ["origin/" + candidate, candidate])
        if base_ref:
            base = candidate
            break
    if not base_ref:
        add(contexts,
            f"aidd: 基点ブランチ ({' / '.join(candidates)}) を解決できないため、PR 前のレビュー証跡を確認していない。"
            "確認するには --base か AIDD_REVIEW_BASE で基点ブランチを指定すること。")
        return
    head_ref, head_sha = resolve_commit(directory, [head, "origin/" + head])
    if not head_ref:
        return
    changed = git(directory, "diff", "--name-only", base_ref + "..." + head_ref)
    if not changed:
        return
    files = changed.splitlines()
    skip = env_regex("AIDD_REVIEW_SKIP_PATHS", DOCS_ONLY)
    if all(skip.search(path) for path in files):
        return
    if has_review_evidence(directory, head, head_sha):
        return
    limit = env_int("AIDD_REVIEW_LIST_LIMIT", 20)
    listing = ", ".join(files[:limit])
    if len(files) > limit:
        listing += f" ほか {len(files) - limit} 件"
    add(contexts,
        f"aidd: ブランチ {head} は {base} に対してコードを変更しているが、.aidd/autonomous-review/ にこのブランチの証跡が無い。"
        f"PR を出す前に /aidd:autonomous-review --base {base} --head {head} を実行すること。"
        f"変更ファイル ({len(files)} 件): {listing}。"
        "意図しないファイルが含まれていれば、別ブランチのコミットの混入を疑う。")


DISCARDS = "aidd: {} は未コミットの変更を取り戻せない形で捨てるため拒否した。捨ててよいかをユーザーに確認し、必要ならユーザー自身に実行してもらうこと。"
UNNAMED_STAGE = "aidd: {} は変更を名指しせずにステージするため拒否した (別のセッションや別の作業の変更まで取り込む)。git add <path>... でファイルを名指ししてから git commit すること。"
STASH = "aidd: git stash は拒否した。stash のスタックは worktree とセッションの間で共有され、別のセッションの変更を pop したり消したりする。退避は一時コミットか別の worktree で行うこと (git stash list / show は可)。"


def deny_unsafe_git(sub, args):
    if env.get("AIDD_DISABLE_GIT_SAFETY") == "1":
        return
    if sub == "stash":
        if not args or args[0] not in ("list", "show"):
            add(denials, STASH)
    elif sub == "reset":
        _, longs, _ = scan(args)
        if "--hard" in longs:
            add(denials, DISCARDS.format("git reset --hard"))
    elif sub == "checkout":
        _, _, positionals = scan(args, "bB", ("--orphan",))
        if "--" in positionals or "." in positionals:
            add(denials, DISCARDS.format("git checkout -- <path> / git checkout ."))
    elif sub == "restore":
        shorts, longs, _ = scan(args, "s", ("--source",))
        staged = "S" in shorts or "--staged" in longs
        worktree = "W" in shorts or "--worktree" in longs
        if worktree or not staged:
            add(denials, DISCARDS.format("git restore (--staged だけの指定を除く)"))
    elif sub == "clean":
        shorts, longs, _ = scan(args, "e", ("--exclude",))
        if "n" not in shorts and "--dry-run" not in longs:
            add(denials, DISCARDS.format("git clean (-n / --dry-run を除く)"))
    elif sub == "add":
        shorts, longs, positionals = scan(args, "", ("--chmod", "--pathspec-from-file"))
        if shorts & set("Au") or longs & {"--all", "--update"} or set(positionals) & {".", ":/"}:
            add(denials, UNNAMED_STAGE.format("git add -A / . / -u"))
    elif sub == "commit":
        shorts, longs, _ = scan(
            args, "mFCctSu",
            ("--message", "--file", "--reuse-message", "--reedit-message", "--fixup", "--squash",
             "--author", "--date", "--template", "--cleanup", "--trailer"),
        )
        if "a" in shorts or "--all" in longs:
            add(denials, UNNAMED_STAGE.format("git commit -a"))


def main_tree_of(directory):
    """Return the toplevel if directory is inside a repository's main worktree, else None."""
    out = git(directory, "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir", "--show-toplevel")
    if not out:
        return None
    lines = out.splitlines()
    if len(lines) != 3 or lines[0] != lines[1]:
        return None
    return lines[2]


def warn_shared_main_tree(directory):
    # A warning, not a denial: session_id is not guaranteed to survive resume or compact, so a
    # "different session" may be this one under a new id.
    session = event.get("session_id")
    if env.get("AIDD_DISABLE_MAIN_TREE_WARNING") == "1" or not session:
        return
    top = main_tree_of(directory)
    if not top:
        return
    ttl = env_int("AIDD_MAIN_TREE_TTL_MINUTES", 30) * 60
    now = time.time()

    def record(data):
        trees = data.setdefault("trees", {})
        warned = data.setdefault("warned", {})
        for path in list(trees):
            trees[path] = {s: t for s, t in trees[path].items() if now - t < ttl}
            if not trees[path]:
                del trees[path]
        for key in [k for k, t in warned.items() if now - t >= ttl]:
            del warned[key]
        others = [s for s in trees.get(top, {}) if s != session]
        trees.setdefault(top, {})[session] = now
        fresh = [s for s in others if f"{session}\t{top}\t{s}" not in warned]
        for s in fresh:
            warned[f"{session}\t{top}\t{s}"] = now
        return bool(fresh)

    if update_state("main-tree.json", record):
        worktree_dir = env.get("AIDD_WORKTREE_DIR") or ".claude/worktrees"
        target = os.path.join(top, worktree_dir, "<name>")
        add(contexts,
            f"aidd: 主ツリー {top} は、直近 {ttl // 60} 分以内に別のセッションも使っている。"
            "ブランチの切り替えやステージが互いの作業を壊すため、このセッションの作業は worktree に移すこと "
            f"(例: git worktree add {target} -b <branch>)。同じセッションが resume / compact で別 ID になった場合は無視してよい。この警告は相手ごとに1回だけ出す。")


def record_issue_search(args):
    session = event.get("session_id")
    if session and option_values(args, "--search", "-S"):
        now = time.time()

        def record(data):
            data[session] = now
            for key in [k for k, t in data.items() if now - t > 86400]:
                del data[key]

        update_state("issue-search.json", record)


def require_issue_search():
    session = event.get("session_id")
    if env.get("AIDD_DISABLE_ISSUE_SEARCH_GATE") == "1" or not session:
        return
    ttl = env_int("AIDD_ISSUE_SEARCH_TTL_MINUTES", 30) * 60
    last = update_state("issue-search.json", lambda data: data.get(session))
    if not isinstance(last, (int, float)) or time.time() - last > ttl:
        add(denials,
            f"aidd: gh issue create の前に、このセッションで gh issue list --search '<キーワード>' を実行して重複を確認すること (直近 {ttl // 60} 分以内の検索が無い)。"
            "検索は起票と別のコマンドとして実行する (同じコマンドの中の検索は、起票の判定より後に記録される)。")


JAPANESE_NUDGE = "aidd: GitHub issue/PR のタイトルと本文は日本語で書くこと (コード識別子・コマンド・コミットメッセージは英語のまま)。既に日本語なら変更不要。"
PUSH_NUDGE = "aidd: push したブランチに open PR がある場合 (gh pr view で確認)、追加コミットが PR の範囲・内容を変えたなら gh pr edit でタイトルと概要を最新化すること (日本語)。変えていなければ何もしない。"

for argv, directory in simple_commands(command):
    program = os.path.basename(argv[0])
    if program == "git":
        parsed = parse_git(argv, directory)
        if not parsed:
            continue
        if hook_event == "PreToolUse":
            deny_unsafe_git(parsed["sub"], parsed["args"])
            warn_shared_main_tree(parsed["dir"])
            if parsed["sub"] == "commit":
                remind_test_perspectives(parsed["dir"])
        elif hook_event == "PostToolUse" and parsed["sub"] == "push":
            add(contexts, PUSH_NUDGE)
    elif program == "gh" and len(argv) >= 3:
        group, action, args = argv[1], argv[2], argv[3:]
        if hook_event == "PostToolUse":
            if group == "issue" and action == "list":
                record_issue_search(args)
            continue
        if group in ("pr", "issue") and action in ("create", "edit"):
            add(contexts, JAPANESE_NUDGE)
        if group == "pr" and action == "create":
            warn_review_before_pr(args, directory)
        if group == "issue" and action == "create":
            require_issue_search()

if denials or contexts:
    output = {"hookEventName": hook_event}
    if denials and hook_event == "PreToolUse":
        output["permissionDecision"] = "deny"
        output["permissionDecisionReason"] = "\n".join(denials)
    if contexts:
        output["additionalContext"] = "\n".join(contexts)
    print(json.dumps({"hookSpecificOutput": output}, ensure_ascii=False))
PYEOF
)

printf '%s' "$input" | python3 -c "$PY_CODE" 2>/dev/null

exit 0
