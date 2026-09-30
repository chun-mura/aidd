#!/bin/bash
# Event-aware Bash hook dispatcher (PreToolUse + PostToolUse). Every check runs in this one
# process and their verdicts are merged into a single JSON reply, because Claude Code reads one
# reply per hook run. Non-matching commands produce no output.
input=$(cat)

# Every check targets a git or gh invocation; anything else exits before python starts.
case "$input" in
  *git*|*gh*) ;;
  *) exit 0 ;;
esac

# The payload stays on stdin (a command can exceed ARG_MAX, see usage-log.sh).
PY_CODE=$(cat <<'PYEOF'
import glob, json, os, re, shlex, subprocess, sys, time

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


def tokenize(text):
    lexer = shlex.shlex(text, posix=True, punctuation_chars=";&|()<>\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    try:
        return list(lexer)
    except ValueError:
        # Unbalanced quotes: fall back to whitespace words so obvious commands still match.
        return re.findall(r"&&|\|\||[;&|()\n]|[^\s;&|()]+", text)


def unwrap(argv):
    changed = True
    while argv and changed:
        changed = False
        while argv and ASSIGNMENT.match(argv[0]):
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
    for token in tokenize(strip_heredocs(text)):
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
    roots = []
    top = git(directory, "rev-parse", "--show-toplevel")
    if top:
        roots.append(top)
    common = git(directory, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common and os.path.basename(common) == ".git":
        roots.append(os.path.dirname(common))
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
        base = origin_head.split("/", 1)[-1] if origin_head else "main"
    base_ref, _ = resolve_commit(directory, ["origin/" + base, base])
    head_ref, head_sha = resolve_commit(directory, [head, "origin/" + head])
    if not base_ref or not head_ref:
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


JAPANESE_NUDGE = "aidd: GitHub issue/PR のタイトルと本文は日本語で書くこと (コード識別子・コマンド・コミットメッセージは英語のまま)。既に日本語なら変更不要。"
PUSH_NUDGE = "aidd: push したブランチに open PR がある場合 (gh pr view で確認)、追加コミットが PR の範囲・内容を変えたなら gh pr edit でタイトルと概要を最新化すること (日本語)。変えていなければ何もしない。"

for argv, directory in simple_commands(command):
    program = os.path.basename(argv[0])
    if program == "git":
        parsed = parse_git(argv, directory)
        if not parsed:
            continue
        if hook_event == "PreToolUse" and parsed["sub"] == "commit":
            remind_test_perspectives(parsed["dir"])
        elif hook_event == "PostToolUse" and parsed["sub"] == "push":
            add(contexts, PUSH_NUDGE)
    elif program == "gh" and len(argv) >= 3 and hook_event == "PreToolUse":
        group, action, args = argv[1], argv[2], argv[3:]
        if group in ("pr", "issue") and action in ("create", "edit"):
            add(contexts, JAPANESE_NUDGE)
        if group == "pr" and action == "create":
            warn_review_before_pr(args, directory)

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
