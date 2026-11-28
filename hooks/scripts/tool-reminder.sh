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
import fcntl, fnmatch, glob, json, os, re, shlex, stat, subprocess, sys, time

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
# Node runs a lone surrogate (JSON.stringify sends it as \ud800) as U+FFFD, so judge that command.
command = re.sub("[\ud800-\udfff]", "\ufffd", command)
if isinstance(base_dir, str):
    base_dir = re.sub("[\ud800-\udfff]", "\ufffd", base_dir)
env = os.environ
LEARNINGS_SCRIPT = sys.argv[1] if len(sys.argv) > 1 else ""

denials = []
contexts = []


def add(bucket, text):
    if text not in bucket:
        bucket.append(text)


# --- command parsing: tokenize, split into simple commands, drop wrappers --------------------
# Not a shell parser. Quoted strings stay whole (so text inside -m "..." is never a command);
# commands joined by && || ; | & newlines or parentheses are checked one by one.
# timeout / time / nice / nohup / stdbuf are the wrappers Claude Code itself strips before
# matching permission rules, so a rule and this hook see the same inner command.
WRAPPERS = [["rtk", "proxy"], ["rtk"], ["command"], ["env"], ["time"], ["nohup"], ["exec"],
            ["timeout"], ["nice"], ["stdbuf"]]
# Extra wrappers: comma-separated, each may span words (e.g. "sudo -E,chronic").
WRAPPERS += [w.split() for w in env.get("AIDD_COMMAND_WRAPPERS", "").split(",") if w.strip()]
# Wrapper options whose value is the next word, and leading operands that are not the command
# (timeout 30 git push: 30 is the duration).
WRAPPER_VALUE_OPTIONS = {
    "timeout": {"-s", "--signal", "-k", "--kill-after"},
    "nice": {"-n", "--adjustment"},
    "stdbuf": {"-i", "-o", "-e", "--input", "--output", "--error"},
}
WRAPPER_OPERANDS = {"timeout": 1}
SEPARATOR_CHARS = set(";&|()\n")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def scan_heredocs(text):
    """Split text into the lines outside heredocs and the heredoc bodies [(delimiter, quoted, body)]."""
    lines = text.split("\n")
    kept = []
    bodies = []
    i = 0
    while i < len(lines):
        kept.append(lines[i])
        delimiters = [(m.group(2), bool(m.group(1))) for m in HEREDOC.finditer(lines[i])]
        i += 1
        for delimiter, quoted in delimiters:
            start = i
            while i < len(lines) and lines[i].strip() != delimiter:
                i += 1
            bodies.append((delimiter, quoted, "\n".join(lines[start:i])))
            i += 1
    return "\n".join(kept), bodies


def strip_heredocs(text):
    # Heredoc bodies are data (commit messages, file contents); drop them before tokenizing.
    return scan_heredocs(text)[0]


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
                name = " ".join(wrapper)
                takes_value = WRAPPER_VALUE_OPTIONS.get(name, set())
                while argv and (argv[0].startswith("-") or ASSIGNMENT.match(argv[0])):
                    argv = argv[2:] if argv[0] in takes_value else argv[1:]
                argv = argv[WRAPPER_OPERANDS.get(name, 0):]
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


def scan(args, short_with_value="", long_with_value=(), short_attached=""):
    """Split git-style args into short flag letters, long flag names and positionals.

    Short clusters are read letter by letter (-am is -a -m); a letter that takes a value ends
    the cluster (-ma is -m "a"), and a value given as the next word is not read as a flag.
    A letter whose value is optional and only attached (-S[<keyid>]) ends the cluster too, but
    the next word stays an argument of its own (-S -a is -S and -a).
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
                if letter in short_attached:
                    break
        else:
            positionals.append(arg)
        i += 1
    return shorts, longs, positionals


def valid_timestamp(value, now):
    return type(value) in (int, float) and 0 <= value <= now


STATE_DIR = env.get("AIDD_TEST_STATE_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "aidd")


def update_state(name, change):
    """Apply change(data) to ~/.claude/aidd/<name> under a lock; return what change returns."""
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        path = os.path.join(STATE_DIR, name)
        with open(path + ".lock", "w") as lock:
            deadline = time.monotonic() + 0.1
            while True:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        return None
                    time.sleep(min(0.01, remaining))
            try:
                with open(path) as f:
                    data = json.load(f)
            except Exception:
                data = {}
            if not isinstance(data, dict):
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
    except Exception:
        return None


# --- checks ----------------------------------------------------------------------------------
DOCS_ONLY = r"(^docs/|\.md$|\.txt$)"


def changed_paths(directory, *revs):
    """The paths a diff changes, or None when git fails. --no-renames: a file moved elsewhere is
    also a deletion where it was. --ignore-submodules=none: ignore = all in .gitmodules would hide a
    submodule pointer. --no-relative: diff.relative from a subdirectory would hide changes outside
    it. -z: paths with non-ASCII or control characters come unquoted (and nothing is stripped).
    The trailing --: a file named like a revision (main...feat) must not make git fail."""
    out = git_bytes(directory, "diff", "--no-ext-diff", "--no-renames", "--ignore-submodules=none",
                    "--no-relative", "--name-only", "-z", *revs, "--")
    if out is None:
        return None
    return [path for path in out.decode("utf-8", "replace").split("\0") if path]


def remind_test_perspectives(directory):
    staged = changed_paths(directory, "--cached")
    if staged and all(re.search(DOCS_ONLY, path) for path in staged):
        return
    perspectives = os.path.join(directory, "docs", "test-perspectives")
    for path in glob.glob(os.path.join(glob.escape(perspectives), "**", "*.md"), recursive=True):
        try:
            if os.path.getmtime(path) > time.time() - 360 * 60:
                return
        except OSError:
            pass
    add(contexts, "aidd: no test perspectives saved under docs/test-perspectives/ in the last 6 hours. If none were produced for this change, run /aidd:test-perspectives <design doc path or change description> before the remaining implementation and write its must items as tests first. If they were already produced for this change, or the change is docs-only or trivial, do not run it again. If implementation is already complete, do not create them retroactively.")


def resolve_commit(directory, names):
    for name in names:
        sha = git(directory, "rev-parse", "--verify", "--quiet", "--end-of-options", name + "^{commit}")
        if sha:
            return name, sha
    return None, None


SHA = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")


def review_finished(state):
    """A finished review in the current schema (5+). Older or malformed evidence is unconfirmed."""
    if not isinstance(state, dict):
        return False
    version = state.get("schema_version")
    if type(version) is not int or version < 5:
        return False
    status = state.get("status")
    if not isinstance(status, str) or status != state.get("final_decision"):
        return False
    # The reason must be present even when null: a run without it predates the split below.
    if "human_required_reason" not in state:
        return False
    reason = state["human_required_reason"]
    after = state.get("head_sha_after_fixes")  # optional in the schema
    if not all(isinstance(state.get(key), str) and SHA.fullmatch(state[key]) for key in ("base_sha", "head_sha")):
        return False
    if after is not None and not (isinstance(after, str) and SHA.fullmatch(after)):
        return False
    # human_required splits into review_incomplete (no finished review) and human_judgment (the
    # review finished; a person makes the final call).
    return (status, reason) in (("auto_merge_eligible", None), ("human_required", "human_judgment"))


# Commits after the reviewed one may add only these (committed evidence, the ledger commit).
AFTER_REVIEW = (".aidd/autonomous-review/", ".aidd/learnings/")


def covers_head(directory, reviewed, head_sha):
    """True when head_sha is the reviewed commit, or adds on top of it only AFTER_REVIEW paths,
    so the code under review is unchanged."""
    if reviewed == head_sha:
        return True
    if git(directory, "merge-base", reviewed, head_sha) != reviewed:
        return False
    # Both ends are compared, not each commit between them: a change undone later leaves the code
    # the PR carries the same as the reviewed code.
    changed = changed_paths(directory, reviewed, head_sha)
    return changed is not None and all(path.startswith(AFTER_REVIEW) for path in changed)


def has_review_evidence(directory, base_shas, head_sha):
    # autonomous-review writes under the worktree it ran in, which need not be this one.
    listing = git(directory, "worktree", "list", "--porcelain") or ""
    roots = [line[len("worktree "):] for line in listing.splitlines() if line.startswith("worktree ")]
    top = git(directory, "rev-parse", "--show-toplevel")
    if top:
        roots.insert(0, top)
    for root in dict.fromkeys(roots):
        for state_file in glob.glob(os.path.join(glob.escape(root), ".aidd", "autonomous-review", "*", "state.json")):
            try:
                with open(state_file) as f:
                    state = json.load(f)
            except Exception:
                continue
            if not review_finished(state) or state["base_sha"] not in base_shas:
                continue
            if covers_head(directory, state.get("head_sha_after_fixes") or state["head_sha"], head_sha):
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
    files = changed_paths(directory, base_ref + "..." + head_ref)
    if files is None:  # no merge base (a shallow clone, unrelated histories), a git failure
        add(contexts,
            f"aidd: ブランチ {head} と {base} の差分を取得できないため、PR 前のレビュー証跡を確認していない。"
            f"PR を出す前に /aidd:autonomous-review --base {base} --head {head} を実行したかを確かめること。")
        return
    if not files:
        return
    skip = env_regex("AIDD_REVIEW_SKIP_PATHS", DOCS_ONLY)
    if all(skip.search(path) for path in files):
        return
    # The review may have resolved the base to the local branch or to origin's. origin's tip
    # counts. The local tip counts too when origin/<base> contains it (a local base that lags
    # behind origin still matches the review), but not when it has unpushed commits the PR would
    # carry unreviewed; with no origin/<base> to check against, the local tip is the base. Any
    # other base_sha does not count (the base moved on after the review).
    _, origin_sha = resolve_commit(directory, ["origin/" + base])
    _, local_sha = resolve_commit(directory, [base])
    base_shas = {origin_sha} if origin_sha else set()
    if local_sha and (not origin_sha
                      or git(directory, "merge-base", "--is-ancestor", local_sha, origin_sha) is not None):
        base_shas.add(local_sha)
    try:
        found = has_review_evidence(directory, base_shas, head_sha)
        unchecked = ""
    except Exception:  # keep the other checks' verdicts; an unjudged evidence is not a review
        found = False
        unchecked = "レビュー証跡を確認できなかった (判定中に失敗した)。"
    if found:
        return
    limit = env_int("AIDD_REVIEW_LIST_LIMIT", 20)
    listing = ", ".join(files[:limit])
    if len(files) > limit:
        listing += f" ほか {len(files) - limit} 件"
    add(contexts,
        f"aidd: {unchecked}ブランチ {head} は {base} に対してコードを変更しているが、.aidd/autonomous-review/ に現在の差分のレビューを完了した証跡が無い"
        " (schema_version 5 以上で、記録した base_sha と最終の head が今の基点ブランチと head に一致するもの。"
        "古い・未完了・失敗・型が不正な証跡と、human_required_reason が review_incomplete のものは数えない)。"
        f"PR を出す前に /aidd:autonomous-review --base {base} --head {head} を実行すること。"
        "ユーザーが実行を断った場合は、このブランチでは再び起動せず、PR 本文に autonomous-review は未実施と書くこと。"
        f"変更ファイル ({len(files)} 件): {listing}。"
        "意図しないファイルが含まれていれば、別ブランチのコミットの混入を疑う。")


DISCARDS = "aidd: {} は未コミットの変更を取り戻せない形で捨てるため拒否した。捨ててよいかをユーザーに確認し、必要ならユーザー自身に実行してもらうこと。"
UNNAMED_STAGE = "aidd: {} は変更を名指しせずにステージするため拒否した (別のセッションや別の作業の変更まで取り込む)。git add <path>... でファイルを名指ししてから git commit すること。"
STASH = "aidd: git stash は拒否した。stash のスタックは worktree とセッションの間で共有され、別のセッションの変更を pop したり消したりする。退避は一時コミットか別の worktree で行うこと (git stash list / show は可)。"
DEFAULT_BRANCH_PUSH = "aidd: {} は既定ブランチ {} の履歴をリモートで書き換えるか消すため拒否した (ほかの人がその上に積んだ作業を失う)。必要ならユーザーに確認し、ユーザー自身に実行してもらうこと。自分の作業ブランチへの force push は止めない。"
UNRESOLVED_PUSH = "aidd: force / delete / prune を伴う git push の送り先 (remote か refspec) に変数・コマンド置換・ブレース展開 ($・バッククォート・{a,b}) があり、既定ブランチに届くかを判定できないため拒否した。ブランチ名を展開した形で書き直すこと。"


def default_branch(directory, remote):
    # The remote's HEAD names its default branch (a remote given as a URL or path has no
    # remote-tracking refs, so origin's is the next guess), but only when it points at a ref
    # that exists: a HEAD aimed at a missing branch must not lift the guard. main and master
    # always count, so a stale or rewritten HEAD cannot unprotect them (a fork's main too).
    names = []
    for name in dict.fromkeys([remote, "origin"]):
        if name and re.fullmatch(r"[A-Za-z0-9._-]+", name):
            target = git(directory, "symbolic-ref", "--quiet", f"refs/remotes/{name}/HEAD")
            prefix = f"refs/remotes/{name}/"
            if target and target.startswith(prefix) and git(
                    directory, "rev-parse", "--verify", "--quiet", target) is not None:
                names.append(target[len(prefix):])
                break
    return list(dict.fromkeys(names + ["main", "master"]))


def push_remote(directory, current):
    # The remote a push without one goes to, in git's order.
    keys = [f"branch.{current}.pushRemote", "remote.pushDefault", f"branch.{current}.remote"]
    for key in keys if current else keys[1:2]:
        value = git(directory, "config", key)
        if value:
            return value
    return "origin"


def implicit_refspecs(directory, remote, current):
    # A push without refspecs sends remote.<name>.push, else what push.default picks: with
    # upstream the current branch goes to its upstream's name, which can be the default branch.
    if re.fullmatch(r"[A-Za-z0-9._-]+", remote):
        configured = git(directory, "config", "--get-all", f"remote.{remote}.push")
        if configured:
            return configured.split("\n")
    mode = git(directory, "config", "push.default") or "simple"
    if mode == "matching":
        return [":"]
    if not current or mode == "nothing":
        return []
    if mode in ("upstream", "tracking"):
        merge = git(directory, "config", f"branch.{current}.merge")
        return [f"{current}:{merge}"] if merge else []
    return [current]


PUSH_OPTIONS = ["all", "atomic", "branches", "delete", "dry-run", "exec", "follow-tags", "force",
                "force-if-includes", "force-with-lease", "mirror", "porcelain", "progress", "prune",
                "push-option", "quiet", "receive-pack", "recurse-submodules", "repo", "set-upstream",
                "signed", "tags", "thin", "verbose"]
PUSH_LONGS = ({f"--{o}" for o in PUSH_OPTIONS} | {f"--no-{o}" for o in PUSH_OPTIONS}
              | {"--ipv4", "--ipv6", "--verify", "--no-verify"})


def full_push_options(args):
    # git push accepts any unambiguous prefix of a long option (--force-w is --force-with-lease).
    out = []
    for i, arg in enumerate(args):
        if arg == "--":
            return out + args[i:]
        name, eq, value = arg.partition("=")
        if arg.startswith("--") and name not in PUSH_LONGS:
            found = [o for o in PUSH_LONGS if o.startswith(name)]
            if len(found) == 1:
                arg = found[0] + eq + value
        out.append(arg)
    return out


def dry_run(args):
    # The last of -n / --dry-run / --no-dry-run wins; a value of -o / --repo is not a flag.
    dry, skip = False, False
    for arg in args:
        if skip:
            skip = False
        elif arg == "--":
            break
        elif arg in ("--dry-run", "--no-dry-run"):
            dry = arg == "--dry-run"
        elif arg in ("--repo", "--push-option", "--receive-pack", "--exec"):
            skip = True
        elif arg.startswith("-") and not arg.startswith("--"):
            shorts, _, _ = scan([arg], "o")
            dry = dry or "n" in shorts
            skip = arg.endswith("o") and "o" in shorts and arg.index("o") == len(arg) - 1
    return dry


def deny_default_branch_push(args, directory):
    args = full_push_options(args)
    shorts, longs, positionals = scan(
        args, "o", ("--repo", "--push-option", "--receive-pack", "--exec"))
    if dry_run(args):
        return
    positionals = [p for p in positionals if p != "--"]
    current = git(directory, "symbolic-ref", "--quiet", "--short", "HEAD")
    # A positional repository wins over --repo.
    repo = option_values(args, "--repo")
    if positionals:
        remote, refspecs = positionals[0], positionals[1:]
    else:
        remote, refspecs = repo[-1] if repo else push_remote(directory, current), []
    # remote.<name>.mirror makes a plain push a mirror push.
    if re.fullmatch(r"[A-Za-z0-9._-]+", remote) and git(
            directory, "config", "--bool", f"remote.{remote}.mirror") == "true":
        longs.add("--mirror")
    force = "f" in shorts or longs & {"--force", "--force-with-lease", "--mirror"}
    delete = "d" in shorts or "--delete" in longs
    prune = "--prune" in longs
    every = longs & {"--all", "--branches", "--mirror"}
    # The shell expands $VAR, $(...), backquotes, $'...' and braces ({main,feat}, {a..b}) after
    # this check sees the words, so a destination built from them cannot be judged; a push that
    # forces or deletes (by option, or by a +refspec / :refspec) with one is denied.
    # (\x60 is the backquote: a literal one inside this heredoc breaks bash 3.2's parse.)
    unresolved = re.compile("[$\x60]|\\{[^}]*(,|\\.\\.)[^}]*\\}")
    forcing = force or delete or prune or any(r.startswith(("+", ":")) for r in refspecs)
    if forcing and any(unresolved.search(w) for w in positionals + repo):
        add(denials, UNRESOLVED_PUSH)
        return
    implicit = not refspecs and not every and "--tags" not in longs
    if implicit:
        refspecs = implicit_refspecs(directory, remote, current)
    if not (force or delete or prune or any(r.startswith(("+", ":")) for r in refspecs)):
        return
    defaults = default_branch(directory, remote)

    def full(ref):
        # The remote resolves heads/main and main to refs/heads/main.
        if ref in ("HEAD", "@"):
            ref = current or ""
        if not ref or ref.startswith("refs/"):
            return ref
        return "refs/" + ref if ref.startswith("heads/") else "refs/heads/" + ref

    def matches(name, ref):
        return bool(ref) and fnmatch.fnmatchcase(f"refs/heads/{name}", full(ref))

    def exists(ref):
        return bool(ref) and git(directory, "rev-parse", "--verify", "--quiet", ref) is not None

    def local(name):
        return exists(f"refs/heads/{name}")

    def pruned(name):
        # --prune deletes a remote branch with no local counterpart. A missing remote-tracking
        # ref proves nothing, so the first default (the remote's HEAD, or main) always counts.
        if name == defaults[0] or not re.fullmatch(r"[A-Za-z0-9._-]+", remote):
            return True
        return exists(f"refs/remotes/{remote}/{name}")

    def source(name, src, dst):
        # The ref a pattern refspec sends to refs/heads/<name> (src and dst have one * each).
        prefix, _, suffix = full(dst).partition("*")
        ref = f"refs/heads/{name}"
        return full(src).replace("*", ref[len(prefix):len(ref) - len(suffix)], 1)

    def mapped(src):
        # A refspec without a destination goes where remote.<name>.push maps its source
        # (git push -f origin feat lands on main under refs/heads/feat:refs/heads/main).
        if implicit or not re.fullmatch(r"[A-Za-z0-9._-]+", remote):
            return src
        for spec in (git(directory, "config", "--get-all", f"remote.{remote}.push") or "").split("\n"):
            s, colon, d = spec.lstrip("+").partition(":")
            if not colon or not d or s.startswith("^"):
                continue
            ref = full(src)
            if "*" in s:
                prefix, _, suffix = full(s).partition("*")
                if ref.startswith(prefix) and ref.endswith(suffix) and len(ref) >= len(prefix) + len(suffix):
                    return full(d).replace("*", ref[len(prefix):len(ref) - len(suffix)], 1)
            elif full(s) == ref:
                return d
        return src

    # A negative refspec (^<ref>) takes refs out of the pattern refspecs.
    excluded = {d for d in defaults for r in refspecs if r.startswith("^") and matches(d, r[1:])}
    hit = None
    if "--mirror" in longs or (force and every and any(local(d) for d in defaults)):
        hit = "git push --force --all / --mirror"
    elif prune and every and any(pruned(d) and not local(d) for d in defaults):
        hit = "git push --prune (ローカルに無い既定ブランチを消す)"
    for refspec in refspecs:
        if refspec.startswith("^"):
            continue
        plus = refspec.startswith("+")
        src, colon, dst = refspec.lstrip("+").partition(":")
        if colon and not src and not dst:
            # ":" pushes every branch that exists on both sides under the same name.
            if (force or plus) and any(local(d) for d in defaults):
                hit = "git push --force <remote> : / +:"
            elif prune and any(pruned(d) and not local(d) for d in defaults):
                hit = "git push --prune (ローカルに無い既定ブランチを消す)"
            continue
        target = dst if colon else (src if "*" in src else mapped(src))
        reached = False
        for d in defaults:
            if not matches(d, target):
                continue
            if "*" not in refspec:
                reached = True
            elif d not in excluded:
                # A pattern sends only the refs that exist here; --prune deletes the rest.
                if exists(source(d, src, target)):
                    reached = True
                elif prune and pruned(d):
                    hit = "git push --prune (ローカルに無い既定ブランチを消す)"
        if not reached:
            continue
        if delete or (colon and not src):
            hit = "git push --delete <既定ブランチ> / git push <remote> :<既定ブランチ>"
        elif force or plus:
            hit = ("git push --force (refspec を省いた push の送り先)" if implicit
                   else "git push --force / +<refspec>")
    if hit:
        add(denials, DEFAULT_BRANCH_PUSH.format(hit, " / ".join(defaults)))


def is_whole_tree(pathspec, directory, top):
    """True if a pathspec names the directory itself, the repository root or above (., ./, :, :/, ..)."""
    base = directory
    rest = pathspec
    if pathspec.startswith(":("):
        end = pathspec.find(")")
        magic = pathspec[2:end].split(",") if end > 0 else []
        if "exclude" in magic:
            return False
        if "top" in magic:
            base = top
        rest = pathspec[end + 1:] if end > 0 else ""
    elif pathspec.startswith(":"):
        rest = pathspec[1:]
        magic = ""
        while rest and rest[0] in "/!^":
            magic += rest[0]
            rest = rest[1:]
        if "!" in magic or "^" in magic:
            return False
        if rest.startswith(":"):
            rest = rest[1:]
        if "/" in magic:
            base = top
    resolved = os.path.realpath(os.path.join(base, rest or "."))
    if resolved == os.path.realpath(directory):
        return True
    root = os.path.realpath(top)
    return root == resolved or root.startswith(resolved.rstrip(os.sep) + os.sep)


ADD_OPTIONS = ("", ("--chmod", "--pathspec-from-file"))
COMMIT_OPTIONS = (
    "mFCct",
    ("--message", "--file", "--reuse-message", "--reedit-message", "--fixup", "--squash",
     "--author", "--date", "--template", "--cleanup", "--trailer"),
    "Su",
)


def deny_unsafe_git(sub, args, directory):
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
        shorts, longs, positionals = scan(args, "bB", ("--orphan", "--pathspec-from-file"))
        # checkout [<tree-ish>] [--] <pathspec>...: everything after the first positional is a
        # path, and a lone positional is a path when it is not a commit but exists on disk.
        paths = positionals[1:] or [
            p for p in positionals
            if not resolve_commit(directory, [p])[0] and os.path.lexists(os.path.join(directory, p))
        ]
        if paths or "--pathspec-from-file" in longs:
            add(denials, DISCARDS.format("git checkout <path> / git checkout -- <path> / git checkout ."))
        elif "f" in shorts or "--force" in longs:
            add(denials, DISCARDS.format("git checkout -f / --force"))
    elif sub == "switch":
        shorts, longs, _ = scan(args, "cC", ("--create", "--force-create", "--orphan"))
        if "f" in shorts or longs & {"--force", "--discard-changes"}:
            add(denials, DISCARDS.format("git switch -f / --force / --discard-changes"))
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
        shorts, longs, positionals = scan(args, *ADD_OPTIONS)
        top = git(directory, "rev-parse", "--show-toplevel") or directory
        whole = any(is_whole_tree(p, directory, top) for p in positionals if p != "--")
        if shorts & set("Au") or longs & {"--all", "--update"} or whole:
            add(denials, UNNAMED_STAGE.format("git add -A / . / -u"))
    elif sub == "commit":
        shorts, longs, _ = scan(args, *COMMIT_OPTIONS)
        if "a" in shorts or "--all" in longs:
            add(denials, UNNAMED_STAGE.format("git commit -a"))
    elif sub == "push":
        deny_default_branch_push(args, directory)


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
    if env.get("AIDD_DISABLE_MAIN_TREE_WARNING") == "1" or not isinstance(session, str) or not session:
        return
    top = main_tree_of(directory)
    if not top:
        return
    ttl = env_int("AIDD_MAIN_TREE_TTL_MINUTES", 30) * 60

    def record(data):
        now = time.time()

        trees = data.get("trees")
        warned = data.get("warned")
        data["trees"] = trees = trees if isinstance(trees, dict) else {}
        data["warned"] = warned = warned if isinstance(warned, dict) else {}
        for path in list(trees):
            if not isinstance(trees[path], dict):
                del trees[path]
                continue
            trees[path] = {s: t for s, t in trees[path].items() if valid_timestamp(t, now) and now - t < ttl}
            if not trees[path]:
                del trees[path]
        # A pair is forgotten only once the peer's occupancy has expired, so a peer that keeps
        # working is warned about once, not once per TTL.
        for key in list(warned):
            parts = key.split("\t")
            if not valid_timestamp(warned[key], now) or len(parts) != 3 or parts[2] not in trees.get(parts[1], {}):
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


def normalize_repo(value):
    """OWNER/REPO (lowercase) from OWNER/REPO, HOST/OWNER/REPO, an https URL or an ssh remote."""
    value = re.sub(r"\.git/?$", "", value.strip().rstrip("/"))
    parts = [p for p in re.split(r"[/:]", value) if p]
    return "/".join(parts[-2:]).lower() if len(parts) >= 2 else value.lower()


def target_repo(repo_flag, directory):
    # gh resolves the same way: -R / --repo first, else the checkout's remote.
    if repo_flag:
        return normalize_repo(repo_flag)
    origin = git(directory, "remote", "get-url", "origin")
    return normalize_repo(origin) if origin else ""


def record_issue_search(args, repo):
    session = event.get("session_id")
    if session and option_values(args, "--search", "-S"):
        def record(data):
            now = time.time()
            data[f"{session}\t{repo}"] = now
            for key in [k for k, t in data.items() if not valid_timestamp(t, now) or now - t > 86400]:
                del data[key]

        update_state("issue-search.json", record)


def require_issue_search(repo):
    session = event.get("session_id")
    if env.get("AIDD_DISABLE_ISSUE_SEARCH_GATE") == "1" or not session:
        return
    ttl = env_int("AIDD_ISSUE_SEARCH_TTL_MINUTES", 30) * 60
    last = update_state("issue-search.json", lambda data: data.get(f"{session}\t{repo}"))
    now = time.time()
    if not valid_timestamp(last, now) or now - last > ttl:
        where = f" ({repo})" if repo else ""
        add(denials,
            f"aidd: gh issue create の前に、このセッションで起票先のリポジトリ{where}に対して gh issue list --search '<キーワード>' を実行して重複を確認すること (直近 {ttl // 60} 分以内の検索が無い)。"
            "検索は起票と別のコマンドとして実行する (同じコマンドの中の検索は、起票の判定より後に記録される)。")


def parse_gh(argv):
    """Return (group, action, args, repo flag); gh accepts -R / --repo before the group too."""
    i = 1
    repo = None
    while i < len(argv) and argv[i].startswith("-"):
        if argv[i] in ("-R", "--repo") and i + 1 < len(argv):
            repo = argv[i + 1]
            i += 2
            continue
        if argv[i].startswith("--repo="):
            repo = argv[i][len("--repo="):]
        elif argv[i].startswith("-R") and not argv[i].startswith("--"):
            repo = argv[i][2:]
        i += 1
    if i + 1 >= len(argv):
        return None
    args = argv[i + 2:]
    repos = option_values(args, "--repo", "-R")
    return argv[i], argv[i + 1], args, (repos[-1] if repos else repo)


def require_label(args):
    # Opt-in: a repository without such labels could not file issues at all.
    prefix = env.get("AIDD_REQUIRED_LABEL_PREFIX")
    if not prefix:
        return
    labels = [l.strip() for v in option_values(args, "--label", "-l") for l in v.split(",")]
    if not any(l.startswith(prefix) for l in labels):
        add(denials,
            f"aidd: gh issue create に {prefix} で始まるラベルが無い。issue-priority skill の基準で判定し、"
            f"--label {prefix}... を付けて起票すること (最上位はユーザーに確認してから付ける)。")


def env_list(name, default):
    return [v.strip() for v in (env.get(name) or default).split(",") if v.strip()]


def check_commit_why(directory):
    # Reads the recorded HEAD instead of the command line: a message given as
    # -m "$(cat <<'EOF' ...)" cannot be cut out of the command string reliably.
    if env.get("AIDD_DISABLE_COMMIT_WHY_CHECK") == "1":
        return
    top = git(directory, "rev-parse", "--show-toplevel")
    if not top:
        return
    # Each check runs only where the repository adopts its convention; elsewhere (e.g. a repo
    # that writes Japanese subjects) telling the model to amend would fight the local rule.
    check_body = bool(env.get("AIDD_COMMIT_WHY_CANON")) or has_why_canon(top)
    check_subject = bool(env.get("AIDD_COMMIT_TYPES")) or has_commitlint(top)
    if not check_body and not check_subject:
        return
    out = git(directory, "log", "-1", "--format=%H%x00%P%x00%ct%x00%B", "HEAD")
    if not out or out.count("\0") < 3:
        return
    sha, parents, committed, message = out.split("\0", 3)
    # A failed commit leaves an older HEAD in place, possibly someone else's.
    if len(parents.split()) > 1 or time.time() - int(committed or 0) > 600:
        return
    subject = message.split("\n", 1)[0].strip()
    if subject.startswith(("fixup!", "squash!", "amend!")):
        return
    if not update_state("commit-why.json", lambda data: _mark_judged(data, sha)):
        return
    types = env_list("AIDD_COMMIT_TYPES", "feat,fix,docs,style,refactor,perf,test,build,ci,chore,revert")
    exempt = env_list("AIDD_COMMIT_BODY_EXEMPT_TYPES", "docs,style,chore")
    trailers = {t.lower() for t in env_list(
        "AIDD_COMMIT_IGNORED_TRAILERS",
        "Co-Authored-By,Signed-off-by,Refs,Closes,Fixes,Resolves,Reviewed-by,Change-Id")}
    match = re.match(r"^([A-Za-z0-9-]+)(\([^)]*\))?!?: \S", subject)
    commit_type = match.group(1) if match else None
    problems = []
    # git revert writes Revert "<subject>"; commitlint accepts it too.
    if check_subject and commit_type not in types and not subject.startswith('Revert "'):
        problems.append(f"件名が Conventional Commits 形式 (<type>: <要約>、type は {'/'.join(types)}) でない")
    if check_body and not commit_body(message, trailers) and commit_type not in exempt:
        problems.append("本文 (変更の Why) が無い")
    if problems:
        text = f"aidd: 直前のコミット {sha[:7]} は、{'、'.join(problems)}。"
        if check_body:
            canon = env.get("AIDD_COMMIT_WHY_CANON") or "CLAUDE.md の「コメントの置き場所」"
            text += f"コミットログには Why を書く (正典: {canon})。"
        add(contexts, text + "push 前なら git commit --amend で直し、push 済みなら書き換えずに次のコミットから守ること。")


def has_why_canon(top):
    for name in ("CLAUDE.md", os.path.join(".claude", "CLAUDE.md")):
        try:
            with open(os.path.join(top, name), encoding="utf-8", errors="replace") as f:
                if re.search(r"^#+[ \t]*コメントの置き場所", f.read(), re.M):
                    return True
        except OSError:
            pass
    return False


def has_commitlint(top):
    if glob.glob(os.path.join(top, "commitlint.config.*")) or glob.glob(os.path.join(top, ".commitlintrc*")):
        return True
    try:
        with open(os.path.join(top, "package.json")) as f:
            return "commitlint" in json.load(f)
    except Exception:
        return False


TRAILER = re.compile(r"^[A-Za-z0-9-]+:\s")
# Issue references are trailers without a colon too ("Closes #19"), but only in this form, so
# body prose such as "Fixes the crash ..." stays body.
ISSUE_TRAILER = re.compile(r"^(Closes|Fixes|Resolves|Refs)\s+(#\d+|\S+#\d+|https?://)", re.I)


def commit_body(message, trailers):
    """Body lines, without the listed trailers of the final paragraph (trailers live only there)."""
    paragraphs = [p for p in re.split(r"\n[ \t]*\n", message.split("\n", 1)[1] if "\n" in message else "") if p.strip()]
    lines = [line for p in paragraphs for line in p.split("\n") if line.strip()]
    if not paragraphs:
        return lines
    last = [line for line in paragraphs[-1].split("\n") if line.strip()]
    if not all(TRAILER.match(line) or ISSUE_TRAILER.match(line) for line in last):
        return lines
    kept = [line for line in last if line.split(None, 1)[0].rstrip(":").lower() not in trailers]
    return [line for p in paragraphs[:-1] for line in p.split("\n") if line.strip()] + kept


def _mark_judged(data, sha):
    judged = data.setdefault("judged", {})
    if sha in judged:
        return False
    judged[sha] = time.time()
    for old in sorted(judged, key=judged.get)[:-200]:
        del judged[old]
    return True


# --- learnings ledger: the commit-time layer of docs/superpowers/specs/2026-11-22-learnings-ledger-design.md
# Runs whether or not the ledger is enabled (enabling only gates writing): a leaking file is the
# same risk in anyone's commit. Read-only; the check itself lives in scripts/learnings.py.
LEDGER_DIR = ".aidd/learnings"
LEDGER_DENY = ("aidd: 知見の台帳 (.aidd/learnings/) のファイルが検査 (scripts/learnings.py) に通らないため git commit を拒否した。"
               "伏せ字にせず該当する記述を書き直してステージし直すか、git restore --staged <file> で外すこと。")
LEDGER_UNCHECKED = ("aidd: 知見の台帳 (.aidd/learnings/) のファイルを含むコミットだが、検査スクリプト scripts/learnings.py を"
                    "読み込めないため拒否した (検査せずに通さない)。aidd の導入を /aidd:doctor で確かめること。")
LEDGER_UNLISTED = ("aidd: 知見の台帳 (.aidd/learnings/) のファイルを git で列挙できなかったため git commit を拒否した (検査せずに通さない)。"
                   "git status で git が動くか、git add / git commit に渡したパスが正しいかを確かめること。")
LEDGER_FAILED = ("aidd: 知見の台帳 (.aidd/learnings/) の検査が途中で失敗したため git commit を拒否した (検査せずに通さない)。"
                 "git diff --cached --name-only -- .aidd/learnings/ で対象を確かめ、python3 -I <aidd>/scripts/learnings.py check <file> を実行すること。")


def git_bytes(directory, *args):
    """git output as bytes, untouched (no strip, no decoding): ledger files are checked byte for byte."""
    try:
        result = subprocess.run(["git", "-C", directory, *args], capture_output=True, timeout=10)
    except Exception:
        return None
    return result.stdout if result.returncode == 0 else None


def ledger_named_files(directory, sub, args):
    """Ledger files that git add / git commit name in this command (not staged yet when PreToolUse
    runs). git resolves the pathspecs itself, so its globbing and magic apply. Returns None when
    git fails (broken git, or a pathspec git rejects): the caller must not read that as "none"."""
    shorts, longs, positionals = scan(args, *(ADD_OPTIONS if sub == "add" else COMMIT_OPTIONS))
    specs = [p for p in positionals if p != "--"]
    if not specs:
        return []
    command = ["ls-files", "-z", "--full-name", "--cached", "--others"]
    if not (sub == "add" and ("f" in shorts or "--force" in longs)):
        command.append("--exclude-standard")
    out = git_bytes(directory, *command, "--", *specs)
    if out is None:
        return None
    return [n for n in os.fsdecode(out).split("\0") if n.startswith(LEDGER_DIR + "/")]


def check_ledger(git_calls):
    """git_calls: (directory, sub, args) of the git add / git commit in this command. The staged
    version and the working-tree version of a named file are both checked: either may be what
    the commit takes."""
    tops = {}
    for directory, sub, args in git_calls:
        top = git(directory, "rev-parse", "--show-toplevel")
        if top:
            tops.setdefault(top, []).append((directory, sub, args))
    module = None
    for top, calls in tops.items():
        if not any(sub == "commit" for _, sub, _ in calls):
            continue
        entries = []  # (name, where, bytes or None)
        # A git failure while listing is not "no ledger files": deny instead of passing unchecked.
        staged = git_bytes(top, "diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR", "--", LEDGER_DIR + "/")
        if staged is None:
            add(denials, LEDGER_UNLISTED)
            continue
        for name in filter(None, os.fsdecode(staged).split("\0")):
            entries.append((name, "staged", git_bytes(top, "cat-file", "blob", ":" + name)))
        named = set()
        for directory, sub, args in calls:
            found = ledger_named_files(directory, sub, args)
            if found is None:
                break
            named.update(found)
        if found is None:
            add(denials, LEDGER_UNLISTED)
            continue
        for name in sorted(named):
            try:
                with open(os.path.join(top, name), "rb") as f:
                    entries.append((name, "working tree", f.read(8192)))
            except FileNotFoundError:
                continue  # staging a deletion leaks nothing
            except OSError:
                entries.append((name, "working tree", None))
        if not entries:
            continue
        if module is None:
            module = load_learnings()
            if not module:
                add(denials, LEDGER_UNCHECKED)
                return
        problems = []
        for name, where, raw in entries:
            errors = module.check_document(name, raw) if raw is not None else ["could not read the file"]
            if errors:
                problems.append(f"{module.display_name(name)} ({where}): " + "; ".join(errors))
        if problems:
            add(denials, LEDGER_DENY + "\n" + "\n".join(problems))


def load_learnings():
    try:
        import importlib.util
        sys.dont_write_bytecode = True  # no __pycache__ in the plugin: hooks write only under ~/.claude/aidd/
        spec = importlib.util.spec_from_file_location("aidd_learnings", LEARNINGS_SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        needed = ("check_document", "display_name")
        return module if all(callable(getattr(module, n, None)) for n in needed) else None
    except Exception:
        return None


JAPANESE_NUDGE = "aidd: GitHub issue/PR のタイトルと本文は日本語で書くこと (コード識別子・コマンド・コミットメッセージは英語のまま)。既に日本語なら変更不要。"
PUSH_NUDGE = "aidd: push したブランチに open PR がある場合 (gh pr view で確認)、追加コミットが PR の範囲・内容を変えたなら gh pr edit でタイトルと概要を最新化すること (日本語)。変えていなければ何もしない。"

# #198: the language nudge is advice, so it stays quiet only when every given title and body is
# readable and holds kana or kanji (one character is enough: identifiers and commands stay in
# English). Anything unreadable keeps it. A body file is read only by a hook run with no denial,
# because a stat, open or read that hangs (an unresponsive mount) loses the whole reply. That keeps
# denials; the other notices of such a run are still lost (accepted: rare, and only advice).
JAPANESE_CHARS = re.compile(r"[぀-ヿ一-鿿]")
BODY_FILE_LIMIT = 3
BODY_READ_BYTES = 64 * 1024
BODY_READ_SECONDS = 1.0
SUBSTITUTION = re.compile(r"\$\(|\x60|\$\{")  # \x60: a literal backquote breaks the bash $(...) around this code
HEREDOC_SUBSTITUTION = re.compile(r"\$\(\s*cat\s+" + HEREDOC.pattern + r"\s*\)")
HEREDOC_BODIES = scan_heredocs(command)[1]


def text_is_japanese(value):
    # The heredoc body was stripped before tokenizing: "$(cat <<'EOF' ... EOF)" left only
    # "$(cat <<'EOF'\n)". Judge every body under that delimiter (one may be a commit message).
    # An unquoted delimiter expands its body, so a substitution there is unresolved too.
    delimiters = [m.group(2) for m in HEREDOC_SUBSTITUTION.finditer(value)]
    if delimiters:
        if SUBSTITUTION.search(HEREDOC_SUBSTITUTION.sub("", value)):
            return False
        bodies = [(quoted, body) for name, quoted, body in HEREDOC_BODIES if name in delimiters]
        found = {name for name, _, _ in HEREDOC_BODIES}
        return all(d in found for d in delimiters) and all(
            JAPANESE_CHARS.search(body) and (quoted or not SUBSTITUTION.search(body)) for quoted, body in bodies)
    return not SUBSTITUTION.search(value) and bool(JAPANESE_CHARS.search(value))


GH_TEXT_OPTIONS = {"--title": "titles", "-t": "titles", "--body": "bodies", "-b": "bodies",
                   "--body-file": "files", "-F": "files"}


# The other options of gh pr/issue create/edit: those that take a value and those that do not.
GH_VALUE_OPTIONS = {"--base", "-B", "--head", "-H", "--label", "-l", "--assignee", "-a", "--reviewer", "-r",
                    "--milestone", "-m", "--project", "-p", "--repo", "-R", "--template", "-T", "--recover",
                    "--add-label", "--remove-label", "--add-assignee", "--remove-assignee", "--add-reviewer",
                    "--remove-reviewer", "--add-project", "--remove-project"}
GH_FLAG_OPTIONS = {"--draft", "-d", "--fill", "-f", "--fill-first", "--fill-verbose", "--web", "-w", "--editor",
                   "-e", "--no-maintainer-edit", "--dry-run", "--remove-milestone"}


def gh_text_options(args):
    """The title, body and body-file values, or None when they cannot be told apart. Options are read in
    order and a value is never read as an option (--title "-bX" and --label "-bX" hold no body). An
    option not listed above, or short flags joined together (-dw), may take the next word as its value,
    so the rest cannot be read: None, and the nudge stays."""
    found = {"titles": [], "bodies": [], "files": []}
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            break
        if not arg.startswith("-") or arg == "-":
            i += 1
            continue
        name, sep, attached = arg.partition("=") if arg.startswith("--") else (arg[:2], "", arg[2:])
        kind = GH_TEXT_OPTIONS.get(name)
        if kind and (sep or attached):
            found[kind].append(attached)
        elif kind and i + 1 < len(args):
            found[kind].append(args[i + 1])
            i += 1
        elif kind:
            return None
        elif name in GH_VALUE_OPTIONS:
            i += 0 if (sep or attached) else 1
        elif name not in GH_FLAG_OPTIONS or attached:
            return None
        i += 1
    return found["titles"], found["bodies"], found["files"]


def body_file_is_japanese(value, directory, deadline):
    if value == "-" or time.monotonic() > deadline:
        return False
    path = os.path.join(directory, os.path.expanduser(value))
    try:
        # stat first: opening a device has side effects; fstat again in case the path changed.
        if not stat.S_ISREG(os.stat(path).st_mode):
            return False
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOCTTY | getattr(os, "O_CLOEXEC", 0))
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                return False
            data = b""
            while len(data) < BODY_READ_BYTES:
                if time.monotonic() > deadline:
                    return False
                chunk = os.read(fd, BODY_READ_BYTES - len(data))
                if not chunk:
                    break
                data += chunk
        finally:
            os.close(fd)
    except (OSError, ValueError):
        return False
    return bool(JAPANESE_CHARS.search(data.decode("utf-8", "replace")))


def japanese_nudge_needed(action, args, directory):
    options = gh_text_options(args)
    if options is None:
        return True
    titles, bodies, files = options
    texts = titles + bodies
    if action == "create" and not (titles and len(texts) + len(files) > len(titles)):
        return True
    if not (texts or files) or denials or len(files) > BODY_FILE_LIMIT:
        return True
    if not all(text_is_japanese(v) for v in texts):
        return True
    deadline = time.monotonic() + BODY_READ_SECONDS
    return not all(body_file_is_japanese(f, directory, deadline) for f in files)


ledger_calls = []
language_checks = []
for argv, directory in simple_commands(command):
    program = os.path.basename(argv[0])
    if program == "git":
        parsed = parse_git(argv, directory)
        if not parsed:
            continue
        if hook_event == "PreToolUse":
            deny_unsafe_git(parsed["sub"], parsed["args"], parsed["dir"])
            warn_shared_main_tree(parsed["dir"])
            if parsed["sub"] == "commit":
                remind_test_perspectives(parsed["dir"])
            if parsed["sub"] in ("add", "commit"):
                ledger_calls.append((parsed["dir"], parsed["sub"], parsed["args"]))
        elif hook_event == "PostToolUse" and parsed["sub"] == "push":
            add(contexts, PUSH_NUDGE)
        elif hook_event in ("PostToolUse", "PostToolUseFailure") and parsed["sub"] == "commit":
            # A command that exits non-zero (git commit && git push, push rejected) arrives as
            # PostToolUseFailure even though its commit landed.
            check_commit_why(parsed["dir"])
    elif program == "gh":
        parsed = parse_gh(argv)
        if not parsed:
            continue
        group, action, args, repo_flag = parsed
        if hook_event != "PreToolUse":
            if hook_event == "PostToolUse" and group == "issue" and action == "list":
                record_issue_search(args, target_repo(repo_flag, directory))
            continue
        if group in ("pr", "issue") and action in ("create", "edit"):
            language_checks.append((action, args, directory))
        if group == "pr" and action == "create":
            warn_review_before_pr(args, directory)
        if group == "issue" and action == "create":
            require_issue_search(target_repo(repo_flag, directory))
            require_label(args)

if any(sub == "commit" for _, sub, _ in ledger_calls):
    try:
        check_ledger(ledger_calls)
    except Exception:  # RecursionError and anything else: deny, and keep the other verdicts
        add(denials, LEDGER_FAILED)

# Last, once every denial is known (see JAPANESE_CHARS). Exceptions keep the nudge.
for action, args, directory in language_checks:
    try:
        needed = japanese_nudge_needed(action, args, directory)
    except Exception:
        needed = True
    if needed:
        add(contexts, JAPANESE_NUDGE)

if denials or contexts:
    output = {"hookEventName": hook_event}
    if denials and hook_event == "PreToolUse":
        output["permissionDecision"] = "deny"
        output["permissionDecisionReason"] = "\n".join(denials)
    if contexts:
        output["additionalContext"] = "\n".join(contexts)
    text = json.dumps({"hookSpecificOutput": output}, ensure_ascii=False)
    try:
        text.encode("utf-8")
    except UnicodeEncodeError:
        # A lone surrogate left in the text (an undecodable environment value) has no UTF-8 form:
        # printing it fails or writes a stray byte. Escaped, the verdict survives.
        text = json.dumps({"hookSpecificOutput": output})
    print(text)
PYEOF
)

# The ledger check (scripts/learnings.py) sits two levels up, beside the other plugin scripts.
learnings_script="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)/scripts/learnings.py"
# -X utf8: harnesses speak UTF-8. Under a non-UTF-8 locale, python would decode this code and
# its input by the locale and fail to print a Japanese verdict, losing it (#184).
printf '%s' "$input" | python3 -I -X utf8 -c "$PY_CODE" "$learnings_script" 2>/dev/null

exit 0
