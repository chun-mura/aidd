#!/bin/bash
# Contract test for scripts/learnings.py: the ledger check must reject what could leak and pass
# ordinary observations (docs/superpowers/specs/2026-11-22-learnings-ledger-design.md).
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/scripts/learnings.py"
# An explicit template keeps TMPDIR honored (macOS mktemp -d alone ignores it).
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/aidd-learnings-test.XXXXXX")
tmp_dir=$(cd "$tmp_dir" && pwd -P)
trap 'rm -rf "$tmp_dir"' EXIT

# --- check_document: one table of inputs that must pass and inputs that must be rejected -------
python3 -I - "$script" <<'PYEOF'
import copy, importlib.util, json, sys
sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("learnings", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

NAME = ".aidd/learnings/20261122T031500Z-1a2b3c4d.json"
BASE = {
    "schema_version": 1,
    "source": "incident-retro",
    "scope": "tool",
    "status": "observed",
    "signature": "git stash",
    "fact": "git stash in a shared worktree hid another session's edits; they were restored by hand.",
    "evidence": ["1287eb5", "#116", "hooks/scripts/tool-reminder.sh"],
    "session": "0123456789ab",
}


def doc(**changes):
    data = copy.deepcopy(BASE)
    for key, value in changes.items():
        if value is None:
            data.pop(key, None)
        else:
            data[key] = value
    return data


def errors(data, name=NAME, raw=None):
    text = raw if raw is not None else json.dumps(data, ensure_ascii=False)
    return mod.check_document(name, text.encode("utf-8"))


# Token-shaped strings are assembled here so the repository never holds one.
fake = {
    "ghp": "gh" + "p_" + "Ab3dE5gH7jK9mN1pQ3sT5vX7zA9cE1gH3jK5",
    "pat": "github" + "_pat_" + "11ABCDEFG0" + "x" * 30,
    "sk": "s" + "k-" + "ant-" + "Q7w8E9r0T1y2U3i4O5p6",
    "akia": "AK" + "IA" + "ABCDEFGHIJKLMNOP",
    "xox": "xo" + "xb-" + "1234567890-abcdefghij",
    "pem": "-----BEGIN " + "PRIVATE KEY-----",
    "entropy": "Zq8" + "Lm2Rt7Vx4Bn9Kc3Wp6Hy1",
}

failures = []


def expect_pass(label, data, name=NAME):
    got = errors(data, name)
    if got:
        failures.append(f"should pass: {label}: {got}")


def expect_reject(label, data, name=NAME, raw=None):
    got = errors(data, name, raw)
    if not got:
        failures.append(f"should reject: {label}")
    # The reason must never echo the offending value (it may be the secret itself).
    for value in fake.values():
        if any(value in e for e in got):
            failures.append(f"reason echoes the value: {label}")


# Inputs that must pass, including the usual false-positive traps.
expect_pass("baseline", BASE)
expect_pass("full 40-char SHA", doc(evidence=["0123456789abcdef0123456789abcdef01234567"]))
expect_pass("empty evidence", doc(evidence=[]))
expect_pass("PR number and relative path", doc(evidence=["#7", "src/app.ts", ".aidd/learnings/20261122T031500Z-1a2b3c4d.json"]))
expect_pass("tool name signature", doc(signature="Edit"))
expect_pass("flags in signature", doc(signature="gh pr create --fill -d"))
for text in [
    "/aidd:incident-retro was run twice; A/B and and/or are fine.",
    "Output went to /dev/null and the hook wrote under ~/.claude/aidd/ as designed.",
    "foo.test.ts and app.ts failed under Node.js after the change.",
    "The check ran at 12:30:45 UTC and the npm scope @types/node resolved.",
    "Commit 0123abc reverted it, and 1287eb5 restored it.",
    "Release-v2.3.4-RC1-Build2026 shipped; MyComponent2Test.spec.tsx passed.",
    "AIDD_REQUIRED_LABEL_PREFIX was unset, so the gate stayed off.",
    "sha256_digest_for_v2_release, x86_64-apple-darwin25 and python3-urllib3-2-0-7 are names.",
    "claude-opus-5-5-20261122 and generateAssetIndex2 and src/components/Button2/index.tsx too.",
    "The ghp_ prefix alone is mentioned here without a value.",
    "ファイル 20261122T031500Z-1a2b3c4d を読んだ。",
    "日本語の事実も200字以内なら通る。" * 5,
]:
    expect_pass(f"fact: {text[:40]}", doc(fact=text))
expect_pass("fact of exactly 200 chars", doc(fact="あ" * 200))
for status in ("observed", "applied", "declined"):
    expect_pass(f"status {status}", doc(status=status))
for scope in ("project", "tool", "aidd"):
    expect_pass(f"scope {scope}", doc(scope=scope))
for source in ("incident-retro", "auto-memory"):
    expect_pass(f"source {source}", doc(source=source))

# autonomous-review records the type of a review finding, not a command: the signature is
# "review <category> <type words>", the scope is project, and evidence holds only SHAs and
# #numbers (a path would carry file names from the reviewed code).
REVIEW = doc(source="autonomous-review", scope="project", signature="review error-handling swallowed-exception",
             fact="A caught exception was logged and dropped, so the caller reported success.",
             evidence=["1287eb5", "#12"])
expect_pass("autonomous-review baseline", REVIEW)
expect_pass("autonomous-review empty evidence", {**REVIEW, "evidence": []})
for signature in [
    "review correctness off-by-one",
    "review security missing-authz-check",
    "review sibling-coverage check-missing-on-sibling handler",
    "review test assertion-never-fails",
    "review performance query-in-loop",
    "review compatibility removed-public-field",
    "review maintainability duplicated-logic",
]:
    expect_pass(f"autonomous-review signature {signature}", {**REVIEW, "signature": signature})
for label, rule, changes in [
    ("command signature", "autonomous-review needs", {"signature": "git stash"}),
    ("unknown category", "autonomous-review needs", {"signature": "review billing rounding"}),
    ("no type words", "autonomous-review needs", {"signature": "review security"}),
    ("flag as type", "autonomous-review needs", {"signature": "review security --strict"}),
    ("other head", "autonomous-review needs", {"signature": "audit security missing-check"}),
    ("tool scope", "must be project", {"scope": "tool"}),
    ("aidd scope", "must be project", {"scope": "aidd"}),
    ("path evidence", "SHA or #number only", {"evidence": ["#12", "src/app.ts"]}),
    # The general rules still hold inside an allowed shape.
    ("random type word", "high-entropy", {"signature": "review security a8f3k2m9x7q1w5e4r6t0"}),
    ("email in fact", "email address", {"fact": "Reported by someone@mailhost.zz in review."}),
]:
    got = errors({**REVIEW, **changes})
    if not any(rule in e for e in got):
        failures.append(f"should reject with {rule}: autonomous-review {label}: {got}")
# The review rules are for autonomous-review only: incident-retro keeps command signatures.
expect_pass("incident-retro keeps tool scope and paths", doc(scope="tool", evidence=["src/app.ts"]))
# A "review" signature belongs to autonomous-review alone, whatever the rest of the observation
# looks like: candidates groups by signature, so another source must not add to a review type.
for source in ("incident-retro", "auto-memory"):
    for label, changes in [
        ("loose", {"scope": "tool", "evidence": ["src/app.ts"]}),
        ("otherwise review-shaped", {"scope": "project", "evidence": ["1287eb5"]}),
    ]:
        got = errors({**REVIEW, **changes, "source": source})
        if not any("for source autonomous-review only" in e for e in got):
            failures.append(f"should reject review signature from {source} ({label}): {got}")

# Each pattern must reject on its own: the reason names that pattern's rule, so a case that a
# neighbouring pattern also catches still fails when its own pattern breaks.
for label, rule, text in [
    ("absolute path", "absolute path", "It failed in /Users/someone/project/app.sh after the edit."),
    ("windows path", "absolute path", "It failed in C:\\work\\app after the edit."),
    ("email", "email address", "Reported by someone@mailhost.zz during review."),
    ("url", "URL", "See https://example.invalid/page for the log."),
    ("www", "URL", "See www.sample for the log."),
    ("ipv4", "IP address", "The runner reached 10.0.12.34 directly."),
    ("ipv6", "IP address", "The runner reached fe80::1ff:fe23:4567 directly."),
    ("fqdn", "host name", "The job called build.example.com and timed out."),
    ("internal host", "host name", "The job called db01.internal and timed out."),
    ("ghp token", "token prefix", f"The value {fake['ghp']} leaked."),
    ("fine-grained pat", "token prefix", f"The value {fake['pat']} leaked."),
    ("sk token", "token prefix", f"The value {fake['sk']} leaked."),
    ("aws key", "token prefix", f"The value {fake['akia']} leaked."),
    ("slack token", "token prefix", f"The value {fake['xox']} leaked."),
    ("pem header", "token prefix", f"The file began with {fake['pem']}."),
    ("high entropy", "high-entropy", f"The value {fake['entropy']} leaked."),
    ("uuid", "UUID", "Record 123e4567-e89b-12d3-a456-426614174000 was touched."),
    ("long hex", "long hex", "Digest " + "ab12" * 16 + " matched."),
    ("company ja", "company name", "株式会社サンプルの案件で起きた。"),
    ("company kabu", "company name", "(株)サンプルの案件で起きた。"),
    ("company en", "company name", "It happened on the Sample Inc. project."),
    ("company llc", "company name", "It happened on the Sample LLC project."),
]:
    got = errors(doc(fact=text))
    if not any(rule in e for e in got):
        failures.append(f"should reject with {rule}: fact {label}: {got}")
    expect_reject(f"fact {label}", doc(fact=text))

# The patterns apply to every string field, not only fact.
expect_reject("token in signature", doc(signature="git " + fake["ghp"]))
expect_reject("email in evidence", doc(evidence=["someone@example.com"]))

# Schema.
expect_reject("missing key", doc(session=None))
expect_reject("extra key", doc(author="someone"))
# Key names are input too: the reason counts them and never names them.
for label, raw in [
    ("unknown key name", json.dumps(doc(leakykeyname=1))),
    ("duplicate key name", json.dumps(doc(leakykeyname=1))[:-1] + ', "leakykeyname": 2}'),
]:
    got = errors(None, raw=raw)
    if not got or any("leakykeyname" in e for e in got):
        failures.append(f"key name echoed or not rejected: {label}: {got}")
expect_reject("wrong schema_version", doc(schema_version=2))
expect_reject("bool schema_version", doc(schema_version=True))
expect_reject("unknown source", doc(source="manual"))
expect_reject("unknown scope", doc(scope="global"))
expect_reject("unknown status", doc(status="promoted"))
expect_reject("fact too long", doc(fact="あ" * 201))
expect_reject("empty fact", doc(fact=""))
expect_reject("newline in fact", doc(fact="line one\nline two"))
expect_reject("fact not a string", doc(fact=["x"]))
expect_reject("signature with a path", doc(signature="git add src/app.ts"))
expect_reject("signature with a value", doc(signature="git commit --message=fix"))
expect_reject("signature with a quote", doc(signature="git commit -m 'fix'"))
expect_reject("signature with uppercase subcommand", doc(signature="git Main"))
expect_reject("signature too many words", doc(signature="git a b c d e f g h"))
expect_reject("empty signature", doc(signature=""))
expect_reject("url in evidence", doc(evidence=["https://example.invalid/pull/1"]))
expect_reject("absolute path in evidence", doc(evidence=["/etc/hosts"]))
expect_reject("home path in evidence", doc(evidence=["~/notes.txt"]))
expect_reject("parent path in evidence", doc(evidence=["../other/file"]))
expect_reject("free text in evidence", doc(evidence=["see the chat"]))
expect_reject("too many evidence items", doc(evidence=["#1"] * 11))
expect_reject("evidence not a list", doc(evidence="#1"))
expect_reject("session not hashed", doc(session="session-a"))
expect_reject("session uppercase", doc(session="0123456789AB"))
expect_reject("not an object", None, raw="[1, 2]")
expect_reject("invalid json", None, raw="{")
expect_reject("duplicate key", None, raw=json.dumps(BASE)[:-1] + ', "fact": "again"}')
expect_reject("oversized file", None, raw=json.dumps(doc(fact="a")) + " " * 5000)

# Deep nesting is rejected, never raised (older Pythons raise RecursionError here), and so is
# any other failure inside the JSON parser.
expect_reject("deeply nested", None, raw="[" * 2000 + "]" * 2000)
real_loads = mod.json.loads
try:
    def boom(*args, **kwargs):
        raise RecursionError("simulated")
    mod.json.loads = boom
    expect_reject("parser raises", BASE)
finally:
    mod.json.loads = real_loads

# Invisible characters are rejected outright; compatibility forms are normalized before the
# patterns run; values written straight against Japanese text are still found.
for label, text in [
    ("zero-width", "a" + "\u200b" + "b"),
    ("line separator", "a" + "\u2028" + "b"),
    ("bidi control", "a" + "\u202e" + "b"),
    ("byte order mark", "a" + "\ufeff" + "b"),
]:
    got = errors(doc(fact=text))
    if not any("invisible" in e for e in got):
        failures.append(f"should reject invisible: {label}: {got}")
fullwidth = "".join(chr(ord(c) + 0xFEE0) for c in fake["ghp"])
for label, rule, text in [
    ("full-width token", "token prefix", f"値は{fullwidth}でした。"),
    ("ip next to kana", "IP address", "接続先は10.0.12.34でした。"),
    ("path next to kana", "absolute path", "場所は/Users/someone/projectでした。"),
    ("host next to kana", "host name", "接続先はbuild.example.comでした。"),
    ("email next to kana", "email address", "連絡先someone@mailhost.zzまで。"),
    ("company next to kana", "company name", "サンプルInc.の案件。"),
    ("ipv6 loopback", "IP address", "It listened on ::1 only."),
    ("ipv6 trailing compression", "IP address", "It bound to fe80:: first."),
    ("absolute path with Japanese directories", "absolute path", "設定は/ユーザー/作業/設定.json にあった。"),
    ("32 hex in fact", "long hex", "Digest " + "0123456789abcdef" * 2 + " matched."),
    ("40-char SHA in fact", "long hex", "Commit " + "0123456789abcdef" * 2 + "01234567 reverted it."),
    ("separated random", "high-entropy", "Value " + "-".join(["Zq8L", "m2Rt", "7Vx4", "Bn9K", "c3Wp", "6Hy1"]) + " leaked."),
]:
    got = errors(doc(fact=text))
    if not any(rule in e for e in got):
        failures.append(f"should reject with {rule}: {label}: {got}")
expect_pass("std namespaces and times", doc(fact="std::fs and Foo::Bar ran at 12:30:45."))
expect_pass("Japanese slashes in prose", doc(fact="読み/書き/実行の権限と、設定/作業/ファイルの順を確かめた。"))
expect_pass("ratios and dates", doc(fact="成功は 3/4 で、11/22 に再現した。"))

# Names that break the file-name pattern are not echoed.
if mod.display_name(".aidd/learnings/leaky-name.json") != mod.display_name(".aidd/learnings/other.json"):
    failures.append("display_name echoes a non-conforming name")
if mod.display_name(NAME) != NAME:
    failures.append("display_name hides a conforming name")

# File names.
expect_reject("bad file name", BASE, name=".aidd/learnings/note.json")
expect_reject("nested file", BASE, name=".aidd/learnings/promotions/20261122T031500Z-1a2b3c4d.json")
expect_reject("non-json file", BASE, name=".aidd/learnings/README.md")

if failures:
    print("\n".join(failures))
    sys.exit(1)
PYEOF

# --- CLI: add (default off, writes only checked observations), check, candidates ------------
export GIT_CONFIG_NOSYSTEM=1 HOME="$tmp_dir/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
repo="$tmp_dir/repo"
git init -q --template= -b main "$repo"
git -C "$repo" commit -q --allow-empty -m 'chore: base'

observation() {  # observation SIGNATURE [FACT]
  python3 -c '
import json, sys
print(json.dumps({"source": "incident-retro", "scope": "tool", "status": "observed",
                  "signature": sys.argv[1], "fact": sys.argv[2], "evidence": ["#1"]}))
' "$1" "${2:-A plain observation for the test.}"
}

# Disabled by default: nothing is written and the exit code says so.
set +e
out=$(observation 'git stash' | python3 -I "$script" add --repo "$repo" --session-id s1 2>&1)
status=$?
set -e
[ "$status" -eq 3 ]
printf '%s\n' "$out" | grep -F 'git config aidd.learnings true'
[ ! -e "$repo/.aidd/learnings" ]

git -C "$repo" config aidd.learnings true

# A rejected observation is not written; the reason names the rule, not the value.
set +e
out=$(observation 'git stash' 'Reported by someone@example.com today.' | \
  python3 -I "$script" add --repo "$repo" --session-id s1 2>&1)
status=$?
set -e
[ "$status" -eq 1 ]
if printf '%s\n' "$out" | grep -Fq 'someone@example.com'; then
  echo "add echoed the rejected value" >&2
  exit 1
fi
[ -z "$(ls -A "$repo/.aidd/learnings" 2>/dev/null)" ]

# A passing observation is written under a generated name, with the session hashed.
path=$(observation 'git stash' | python3 -I "$script" add --repo "$repo" --session-id s1)
printf '%s\n' "$path" | grep -Eq '^\.aidd/learnings/[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}\.json$'
python3 -I - "$repo/$path" <<'PYEOF'
import hashlib, json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["schema_version"] == 1, data
assert data["session"] == hashlib.sha256(b"s1").hexdigest()[:12], data
assert "s1" not in json.dumps(data), data
PYEOF
python3 -I "$script" check --repo "$repo" "$repo/$path"

# Callers may not set schema_version or session themselves.
set +e
python3 -c 'import json; print(json.dumps({"source": "incident-retro", "scope": "tool", "status": "observed", "signature": "git stash", "fact": "x", "evidence": [], "session": "0123456789ab"}))' | \
  python3 -I "$script" add --repo "$repo" --session-id s1 >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ]

# check rejects a bad file and exits 1.
bad="$repo/.aidd/learnings/20261122T000000Z-00000000.json"
python3 -c 'import json,sys; json.dump({"schema_version": 1}, open(sys.argv[1], "w"))' "$bad"
set +e
python3 -I "$script" check --repo "$repo" "$bad" >/dev/null
status=$?
set -e
[ "$status" -eq 1 ]
rm "$bad"

# candidates counts merged observations and the ones written in this session only.
# An own unmerged observation plus this session is still one session.
python3 -I "$script" candidates --repo "$repo" --session-id s1 --signature 'git stash' > "$tmp_dir/c1"
[ ! -s "$tmp_dir/c1" ]
# Someone else's unmerged observation (s1, seen from session s2) is not counted.
python3 -I "$script" candidates --repo "$repo" --session-id s2 --signature 'git stash' > "$tmp_dir/c2"
[ ! -s "$tmp_dir/c2" ]

# Once merged into the default branch it counts. A merged observation that fails the check is
# not counted, and is reported on stderr by name only.
python3 -c '
import json, sys
json.dump({"schema_version": 1, "source": "incident-retro", "scope": "tool", "status": "observed",
           "signature": "gh pr view", "fact": "Reported by someone@mailhost.zz today.",
           "evidence": [], "session": "aaaaaaaaaaaa"}, open(sys.argv[1], "w"))
' "$repo/.aidd/learnings/20261122T000000Z-00000001.json"
git -C "$repo" add .aidd/learnings
git -C "$repo" commit -qm 'docs: ledger'
python3 -I "$script" candidates --repo "$repo" --session-id s2 --signature 'git stash' \
  --signature 'gh pr view' > "$tmp_dir/c3" 2> "$tmp_dir/c3.err"
grep -F '"signature": "git stash"' "$tmp_dir/c3"
grep -F '"sessions": 2' "$tmp_dir/c3"
if grep -Fq 'gh pr view' "$tmp_dir/c3"; then
  echo "an observation that fails the check was counted" >&2
  exit 1
fi
grep -F '1 observation(s) on the default branch fail the check' "$tmp_dir/c3.err"
grep -F '.aidd/learnings/20261122T000000Z-00000001.json' "$tmp_dir/c3.err"
if grep -Fq 'someone' "$tmp_dir/c3.err"; then
  echo "candidates echoed a rejected value" >&2
  exit 1
fi

# On a branch: the default branch's observations count, plus this session's working-tree ones,
# without double-counting a file present in both.
git -C "$repo" switch -q -c work
observation 'git stash' | python3 -I "$script" add --repo "$repo" --session-id s3 >/dev/null
python3 -I "$script" candidates --repo "$repo" --session-id s3 > "$tmp_dir/c4" 2>/dev/null
grep -F '"sessions": 2' "$tmp_dir/c4"
[ "$(python3 -c 'import json,sys; print(len(json.loads(open(sys.argv[1]).readline())["files"]))' "$tmp_dir/c4")" -eq 2 ]
# Without a session, only merged observations count.
python3 -I "$script" candidates --repo "$repo" > "$tmp_dir/c5" 2>/dev/null
[ ! -s "$tmp_dir/c5" ]
# --all lists every counted signature, including single-session ones.
python3 -I "$script" candidates --repo "$repo" --all > "$tmp_dir/c6" 2>/dev/null
grep -F '"signature": "git stash"' "$tmp_dir/c6"
grep -F '"sessions": 1' "$tmp_dir/c6"

# A working-tree observation that fails the check is reported (its session cannot be read);
# a valid one from another session is left out silently.
python3 -c '
import json, sys
json.dump({"schema_version": 1, "source": "incident-retro", "scope": "tool", "status": "observed",
           "signature": "git stash", "fact": "Reported by someone@mailhost.zz today.",
           "evidence": [], "session": "bbbbbbbbbbbb"}, open(sys.argv[1], "w"))
' "$repo/.aidd/learnings/20261122T000000Z-00000002.json"
observation 'gh pr view' | python3 -I "$script" add --repo "$repo" --session-id s9 >/dev/null
python3 -I "$script" candidates --repo "$repo" --session-id s3 > /dev/null 2> "$tmp_dir/c7.err"
grep -F '1 observation(s) on the working tree fail the check' "$tmp_dir/c7.err"
grep -F '.aidd/learnings/20261122T000000Z-00000002.json' "$tmp_dir/c7.err"
[ "$(grep -c '^  ' "$tmp_dir/c7.err")" -eq 2 ]  # the merged bad file and this one, nothing else
if grep -Fq 'someone' "$tmp_dir/c7.err"; then
  echo "candidates echoed a rejected value" >&2
  exit 1
fi

# A default branch named master is found.
master_repo="$tmp_dir/master-repo"
git init -q --template= -b master "$master_repo"
git -C "$master_repo" config aidd.learnings true
observation 'git stash' | python3 -I "$script" add --repo "$master_repo" --session-id m1 >/dev/null
git -C "$master_repo" add .aidd/learnings
git -C "$master_repo" commit -qm 'docs: ledger'
python3 -I "$script" candidates --repo "$master_repo" --session-id m2 --signature 'git stash' > "$tmp_dir/m1"
grep -F '"sessions": 2' "$tmp_dir/m1"

# autonomous-review writes a finding type through the same add, and it is counted the same way.
python3 -c '
import json
print(json.dumps({"source": "autonomous-review", "scope": "project", "status": "applied",
                  "signature": "review error-handling swallowed-exception",
                  "fact": "A caught exception was logged and dropped.", "evidence": ["#3"]}))
' | python3 -I "$script" add --repo "$master_repo" --session-id m3 > "$tmp_dir/m3"
grep -Eq '^\.aidd/learnings/[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}\.json$' "$tmp_dir/m3"
git -C "$master_repo" add .aidd/learnings
git -C "$master_repo" commit -qm 'docs: review ledger'
python3 -I "$script" candidates --repo "$master_repo" --session-id m4 \
  --signature 'review error-handling swallowed-exception' > "$tmp_dir/m4"
grep -F '"signature": "review error-handling swallowed-exception"' "$tmp_dir/m4"
grep -F '"sessions": 2' "$tmp_dir/m4"
# Another source cannot add to a review type: its observation is rejected, by add and when merged.
review_from_retro() {
  python3 -c '
import json
print(json.dumps({"source": "incident-retro", "scope": "project", "status": "observed",
                  "signature": "review correctness off-by-one",
                  "fact": "An index stopped one short.", "evidence": ["#4"]}))
'
}
set +e
review_from_retro | python3 -I "$script" add --repo "$master_repo" --session-id m5 >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ]
review_from_retro | python3 -c '
import json, sys
data = json.load(sys.stdin)
data.update(schema_version=1, session="cccccccccccc")
json.dump(data, open(sys.argv[1], "w"))
' "$master_repo/.aidd/learnings/20261122T000000Z-00000005.json"
git -C "$master_repo" add .aidd/learnings
git -C "$master_repo" commit -qm 'docs: foreign review type'
python3 -I "$script" candidates --repo "$master_repo" --session-id m6 \
  --signature 'review correctness off-by-one' > "$tmp_dir/m6" 2> "$tmp_dir/m6.err"
if grep -Fq 'review correctness off-by-one' "$tmp_dir/m6"; then
  echo "an observation from another source was counted toward a review type" >&2
  exit 1
fi
grep -F '.aidd/learnings/20261122T000000Z-00000005.json' "$tmp_dir/m6.err"

# No default branch, or a default branch that cannot be listed: say so and exit 4 (not 0, not
# the 3 that means disabled), so merged observations are never silently counted as none.
trunk_repo="$tmp_dir/trunk-repo"
git init -q --template= -b trunk "$trunk_repo"
git -C "$trunk_repo" commit -q --allow-empty -m 'chore: base'
set +e
python3 -I "$script" candidates --repo "$trunk_repo" --session-id t1 > "$tmp_dir/t1" 2> "$tmp_dir/t1.err"
status=$?
set -e
[ "$status" -eq 4 ]
[ ! -s "$tmp_dir/t1" ]
grep -F 'merged observations could not be counted' "$tmp_dir/t1.err"

fake_bin="$tmp_dir/fake-bin"
mkdir -p "$fake_bin"
real_git=$(command -v git)
cat > "$fake_bin/git" <<EOF
#!/bin/bash
for arg in "\$@"; do [ "\$arg" = ls-tree ] && exit 128; done
exec "$real_git" "\$@"
EOF
chmod +x "$fake_bin/git"
set +e
PATH="$fake_bin:$PATH" python3 -I "$script" candidates --repo "$master_repo" --session-id m2 > "$tmp_dir/t2" 2> "$tmp_dir/t2.err"
status=$?
set -e
[ "$status" -eq 4 ]
grep -F 'could not list the ledger on the default branch' "$tmp_dir/t2.err"

# --- add: one observation per session and signature (#144) -----------------------------------
# A second observation with the same session and signature is not written, whatever its fact;
# add exits 5 (not 0, not a rejection's 1) and names the existing file, never its values.
ledger_count() { find "$1/.aidd/learnings" -name '*.json' | wc -l | tr -d ' '; }
add_status() {  # add_status REPO SESSION SIGNATURE [FACT]: run add, keep stderr in $tmp_dir/add.err
  set +e
  observation "$3" "${4:-A plain observation for the test.}" | \
    python3 -I "$script" add --repo "$1" --session-id "$2" > "$tmp_dir/add.out" 2> "$tmp_dir/add.err"
  local status=$?
  set -e
  echo "$status"
}
dup_repo="$tmp_dir/dup-repo"
git init -q --template= -b main "$dup_repo"
git -C "$dup_repo" commit -q --allow-empty -m 'chore: base'
git -C "$dup_repo" config aidd.learnings true
[ "$(add_status "$dup_repo" d1 'git stash' 'First fact about stash.')" -eq 0 ]
first=$(cat "$tmp_dir/add.out")
[ "$(add_status "$dup_repo" d1 'git stash' 'First fact about stash.')" -eq 5 ]
[ ! -s "$tmp_dir/add.out" ]
grep -F 'already recorded' "$tmp_dir/add.err"
grep -F "$first" "$tmp_dir/add.err"
[ "$(ledger_count "$dup_repo")" -eq 1 ]
# A different fact in the same session and signature is still a duplicate (user decision D1).
[ "$(add_status "$dup_repo" d1 'git stash' 'Another fact about stash.')" -eq 5 ]
if grep -Fq 'fact about stash' "$tmp_dir/add.err"; then
  echo "add echoed a fact in the duplicate message" >&2
  exit 1
fi
[ "$(ledger_count "$dup_repo")" -eq 1 ]
# Another session, or another signature, is written.
[ "$(add_status "$dup_repo" d2 'git stash')" -eq 0 ]
[ "$(add_status "$dup_repo" d1 'gh pr view')" -eq 0 ]
[ "$(ledger_count "$dup_repo")" -eq 3 ]
# An observation merged into the default branch is a duplicate too, after it left the working tree.
git -C "$dup_repo" add .aidd/learnings
git -C "$dup_repo" commit -qm 'docs: ledger'
git -C "$dup_repo" switch -q -c work
git -C "$dup_repo" rm -q -r .aidd/learnings
[ "$(add_status "$dup_repo" d1 'git stash')" -eq 5 ]
grep -F "$first" "$tmp_dir/add.err"
[ ! -e "$dup_repo/.aidd/learnings" ] || [ "$(ledger_count "$dup_repo")" -eq 0 ]
# A merged observation of the same signature from another session is not a duplicate.
[ "$(add_status "$dup_repo" d3 'git stash')" -eq 0 ]
[ "$(ledger_count "$dup_repo")" -eq 1 ]
# A same-session file that fails the check is not counted as a duplicate; add writes and says the
# duplicate check is incomplete, by count and place only (never the file's values).
mkdir -p "$dup_repo/.aidd/learnings"
python3 -c '
import hashlib, json, sys
json.dump({"schema_version": 1, "source": "incident-retro", "scope": "tool", "status": "observed",
           "signature": "git log", "fact": "Reported by someone@mailhost.zz today.",
           "evidence": [], "session": hashlib.sha256(b"d1").hexdigest()[:12]}, open(sys.argv[1], "w"))
' "$dup_repo/.aidd/learnings/20261122T000000Z-00000009.json"
[ "$(add_status "$dup_repo" d1 'git log')" -eq 0 ]
[ "$(ledger_count "$dup_repo")" -eq 3 ]
grep -F '1 observation(s) on the working tree cannot be read or fail the check' "$tmp_dir/add.err"
if grep -Fq 'someone' "$tmp_dir/add.err"; then
  echo "add echoed a value of an observation that fails the check" >&2
  exit 1
fi
# Only the scope breaks the schema: same session and signature, still written with the notice.
python3 -c '
import hashlib, json, sys
json.dump({"schema_version": 1, "source": "incident-retro", "scope": "galaxy", "status": "observed",
           "signature": "git diff", "fact": "A plain observation for the test.",
           "evidence": [], "session": hashlib.sha256(b"d1").hexdigest()[:12]}, open(sys.argv[1], "w"))
' "$dup_repo/.aidd/learnings/20261122T000000Z-0000000a.json"
[ "$(add_status "$dup_repo" d1 'git diff')" -eq 0 ]
grep -F '2 observation(s) on the working tree cannot be read or fail the check' "$tmp_dir/add.err"
[ "$(ledger_count "$dup_repo")" -eq 5 ]

# Default branch unreadable (the situation of candidates' exit 4): judge on the working tree
# alone, write, and say on stderr that the default branch was not checked (user decision D2).
git -C "$trunk_repo" config aidd.learnings true
[ "$(add_status "$trunk_repo" t1 'git stash')" -eq 0 ]
grep -F 'default branch could not be checked' "$tmp_dir/add.err"
[ "$(ledger_count "$trunk_repo")" -eq 1 ]
[ "$(add_status "$trunk_repo" t1 'git stash')" -eq 5 ]
[ "$(ledger_count "$trunk_repo")" -eq 1 ]
# On that working-tree-only path too, a file that fails the check is reported as an incomplete check.
python3 -c '
import hashlib, json, sys
json.dump({"schema_version": 1, "source": "incident-retro", "scope": "galaxy", "status": "observed",
           "signature": "git diff", "fact": "A plain observation for the test.",
           "evidence": [], "session": hashlib.sha256(b"t1").hexdigest()[:12]}, open(sys.argv[1], "w"))
' "$trunk_repo/.aidd/learnings/20261122T000000Z-0000000b.json"
[ "$(add_status "$trunk_repo" t1 'git diff')" -eq 0 ]
grep -F '1 observation(s) on the working tree cannot be read or fail the check' "$tmp_dir/add.err"
# The merged duplicate is not seen when the default branch cannot be listed, so it is written.
[ "$(PATH="$fake_bin:$PATH" add_status "$dup_repo" d1 'git stash')" -eq 0 ]
grep -F 'default branch could not be checked' "$tmp_dir/add.err"
# A merged file that git cannot read (cat-file fails) leaves the check incomplete: written, with
# the notice for the default branch.
catfile_bin="$tmp_dir/catfile-bin"
mkdir -p "$catfile_bin"
cat > "$catfile_bin/git" <<EOF
#!/bin/bash
for arg in "\$@"; do [ "\$arg" = cat-file ] && exit 128; done
exec "$real_git" "\$@"
EOF
chmod +x "$catfile_bin/git"
[ "$(PATH="$catfile_bin:$PATH" add_status "$dup_repo" d1 'gh pr view')" -eq 0 ]
grep -E '^[0-9]+ observation\(s\) on the default branch cannot be read or fail the check' "$tmp_dir/add.err"
# A working-tree ledger that cannot be read: exit 6, nothing written, no traceback.
before=$(ledger_count "$dup_repo")
chmod 000 "$dup_repo/.aidd/learnings"
status=$(add_status "$dup_repo" d5 'git stash')
chmod 755 "$dup_repo/.aidd/learnings"
[ "$status" -eq 6 ]
[ ! -s "$tmp_dir/add.out" ]
grep -F 'the working-tree ledger could not be read' "$tmp_dir/add.err"
if grep -Fq 'Traceback' "$tmp_dir/add.err"; then
  echo "add leaked a traceback" >&2
  exit 1
fi
[ "$(ledger_count "$dup_repo")" -eq "$before" ]
# A working-tree ledger that can be read but not written: exit 6 as well, nothing written, no
# traceback (the read succeeds, so only the write fails).
chmod 555 "$dup_repo/.aidd/learnings"
status=$(add_status "$dup_repo" d6 'git stash')
chmod 755 "$dup_repo/.aidd/learnings"
[ "$status" -eq 6 ]
[ ! -s "$tmp_dir/add.out" ]
grep -F 'the working-tree ledger could not be written' "$tmp_dir/add.err"
if grep -Fq 'Traceback' "$tmp_dir/add.err"; then
  echo "add leaked a traceback on a write failure" >&2
  exit 1
fi
[ "$(ledger_count "$dup_repo")" -eq "$before" ]

# --- scan: a reflux draft for the aidd repository (#107) ------------------------------------
# The draft goes outside the using repository, so it gets the same pattern check line by line,
# and cites no evidence of the using repository (commit SHA, #number). No git repository or
# enabled ledger is needed, and nothing is written.
draft_ok='[reflux] git stash: a shared worktree loses another session'"'"'s edits

## signature
git stash

## 起きたこと
Two sessions shared one worktree; git stash in one session hid the other session'"'"'s edits.

## 再現の手順
1. git init in an empty directory, edit a tracked file, run git stash from a second shell.

## 対象にする aidd の資産
hooks/scripts/tool-reminder.sh (/aidd:incident-retro)

## その規則で壊れるもの
A single-session worktree where stashing is intended.'
out=$(cd "$tmp_dir" && printf '%s\n' "$draft_ok" | python3 -I "$script" scan)
printf '%s\n' "$out" | grep -F 'draft passed the check'
[ -z "$(find "$tmp_dir" -name '__pycache__')" ]
scan_reject() {  # scan_reject LABEL RULE TEXT: rejected (exit 1), reason names the rule, not the value
  local label=$1 rule=$2 text=$3 got status
  set +e
  got=$(printf '%s\n%s\n' "$draft_ok" "$text" | python3 -I "$script" scan 2>&1)
  status=$?
  set -e
  if [ "$status" -ne 1 ] || ! printf '%s\n' "$got" | grep -Fq -- "$rule"; then
    echo "scan should reject with $rule: $label (exit $status): $got" >&2
    exit 1
  fi
  if printf '%s\n' "$got" | grep -Fq -- "$text"; then
    echo "scan echoed the rejected value: $label" >&2
    exit 1
  fi
}
scan_reject "URL" "URL" "See https://intra.zz/run/42 for the log."
scan_reject "absolute path" "absolute path" "It failed under /work/customer-app/src."
scan_reject "email" "email address" "Reported by someone@mailhost.zz."
scan_reject "token" "token prefix" "Value gh""p_Ab3dE5gH7jK9mN1pQ3sT5vX7zA9cE1gH3jK5 leaked."
scan_reject "issue number" "commit SHA or #number" "Same as #123 in our tracker."
scan_reject "full-width issue number" "commit SHA or #number" "Same as ＃１２３ in our tracker."
scan_reject "short SHA" "commit SHA or #number" "Reverted in 1a2b3c4 later."
scan_reject "company" "company name" "Seen at Sample Inc. last week."
scan_reject "tab" "invisible or control character" "$(printf 'col\tcol')"
# SHAs in any case and digit-only short SHAs, a #number after letters (review R1, S1).
scan_reject "upper-case SHA" "commit SHA or #number" "Reverted in 1A2B3C4D later."
scan_reject "digit-only short SHA" "commit SHA or #number" "Reverted in 4417302 later."
scan_reject "full SHA" "commit SHA or #number" "Commit 0123456789ABCDEF0123456789ABCDEF01234567 broke it."
scan_reject "PR#number" "commit SHA or #number" "Same as PR#12 here."
# Repository names, home-relative paths, @-words (review S1). Placeholders pass (below).
scan_reject "repo after -R" "repository name after -R/--repo" "Run gh pr view -R someorg/someapp first."
scan_reject "repo after --repo=" "repository name after -R/--repo" "Run gh pr view --repo=someorg/someapp first."
scan_reject "home path" "home-relative path" "It wrote ~/work/someapp/out.log."
scan_reject "named home" "home-relative path" "It wrote ~someone/out.log."
scan_reject "@-word" "@-mention or package scope" "Ask @someone about it."
# Any ~/ word, one level included (review R1, round 2); no ~/ form is allowed (<config-dir> instead).
scan_reject "home path, one level" "home-relative path" "It wrote ~/notes.txt."
scan_reject "home config dir" "home-relative path" "It read ~/.claude/settings.json."
# Angle brackets are not a free pass: only the fixed placeholders are (review E1).
scan_reject "bracketed #number" "commit SHA or #number" "Same as <#123> here."
scan_reject "bracketed @-word" "@-mention or package scope" "Ask <@someone> about it."
scan_reject "bracketed real repo" "repository name after -R/--repo" "Run gh pr view -R <someorg>/<someapp> first."
scan_reject "half placeholder repo" "repository name after -R/--repo" "Run gh pr view -R <owner>/someapp first."
scan_reject "placeholder followed by a word" "repository name after -R/--repo" "Run gh pr view -R <owner>/<repo>_x first."
scan_reject "placeholder followed by a path" "repository name after -R/--repo" "Run gh pr view -R <owner>/<repo>/x first."
# ASCII marks after the placeholders, then a name: rejected (review round 4).
scan_reject "mark then path" "repository name after -R/--repo" "Run gh pr view -R <path>.secret/x first."
scan_reject "mark then name" "repository name after -R/--repo" "Run gh pr view --repo=<owner>/<repo>.internal first."
scan_reject "hyphen then name" "repository name after -R/--repo" "Run gh pr view -R <owner>/<repo>-x first."
scan_reject "hyphen then name, no slash" "repository name after -R/--repo" "Run gh pr view -R <path>-x first."
# A full-width letter is the ASCII letter after NFKC, so it is still a name after the mark.
scan_reject "mark then full-width name" "repository name after -R/--repo" "Run gh pr view -R <path>.ｓｅｃｒｅｔ first."
# A closing Markdown backquote (an ASCII mark) followed by Japanese is the end of the value (round 5).
out=$(printf '%s\n%s\n%s\n' "$draft_ok" '`gh pr view -R <owner>/<repo>`を開く' '`cp -R <path>/<file> <dir>`で写す' \
  | python3 -I "$script" scan)
printf '%s\n' "$out" | grep -F 'draft passed the check'
# The value may end at a space or line end after ASCII marks, or at a non-ASCII mark (Japanese
# runs on without a space); a full-width mark counts as non-ASCII even though NFKC makes it ASCII.
out=$(printf '%s\n%s\n%s\n%s\n' "$draft_ok" 'gh pr view -R <owner>/<repo>.' \
  '「--repo=<owner>/<repo>」と -R <owner>/<repo>、次に -R <owner>/<repo>）次に' \
  'cp -R <path>/<file> <dir>; grep -R pattern <dir>' | python3 -I "$script" scan)
printf '%s\n' "$out" | grep -F 'draft passed the check'
# A value made of the fixed placeholders only passes after -R, whatever the command (cp -R included),
# and the placeholder may end at Japanese or full-width punctuation (review round 3).
out=$(printf '%s\n%s\n%s\n' "$draft_ok" 'cp -R <path>/<file> <dir> で写す。' \
  'gh pr view -R <owner>/<repo>、次に「--repo=<owner>/<repo>」と「-R <owner>/<repo>」を試す。' \
  | python3 -I "$script" scan)
printf '%s\n' "$out" | grep -F 'draft passed the check'
# Ordinary numbers and placeholders are not taken for a SHA, repository or path.
out=$(printf '%s\n%s\n' "$draft_ok" 'Seen on 0.69.0 at 2026-11-23 (20261123), 123456 lines, 3/4 runs; defaced; gh pr view -R <owner>/<repo>; --repo=<owner>/<repo>; <config-dir>/<path>; cp -R <dir> <dir>; git switch <branch>; run <command> on <file>.' \
  | python3 -I "$script" scan)
printf '%s\n' "$out" | grep -F 'draft passed the check'
# The draft keeps the shape retro reads: the [reflux] title on line 1, every section, and a
# signature line that passes the ledger's signature rule and is not a review finding type (S9).
scan_draft_reject() {  # scan_draft_reject LABEL RULE DRAFT
  local got status
  set +e
  got=$(printf '%s\n' "$3" | python3 -I "$script" scan 2>&1)
  status=$?
  set -e
  if [ "$status" -ne 1 ] || ! printf '%s\n' "$got" | grep -Fq -- "$2"; then
    echo "scan should reject with $2: $1 (exit $status): $got" >&2
    exit 1
  fi
}
scan_draft_reject "no title prefix" "first line must be the title" "${draft_ok#\[reflux\] }"
scan_draft_reject "missing section" "missing section: ## 再現の手順" "${draft_ok/\#\# 再現の手順/## 手順}"
scan_draft_reject "path in signature" "signature: only a command or tool name" "${draft_ok/$'\ngit stash\n'/$'\ngit add src/app.ts\n'}"
scan_draft_reject "review type" "review finding type is not a reflux candidate" "${draft_ok/$'\ngit stash\n'/$'\nreview correctness off-by-one\n'}"
scan_draft_reject "no signature line" "no signature line" "${draft_ok/$'\ngit stash\n'/$'\n\n'}"
# Reasons point at the line, so the rewrite can find it without the value being repeated.
set +e
got=$(printf 'clean line\nSee https://intra.zz/x\n' | python3 -I "$script" scan 2>&1)
set -e
printf '%s\n' "$got" | grep -F 'line 2: contains a URL'
# Not valid UTF-8, empty: rejected.
set +e
printf '\xff\xfe\n' | python3 -I "$script" scan >/dev/null 2>&1
s1=$?
printf '\n' | python3 -I "$script" scan >/dev/null 2>&1
s2=$?
set -e
[ "$s1" -eq 1 ] && [ "$s2" -eq 1 ]
# An unexpected failure is not a rejection: exit 2 with the exception name, no traceback (review E3).
python3 -I - "$script" <<'PYEOF'
import contextlib, importlib.util, io, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("learnings", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
def broken(text):
    raise RuntimeError("boom")
mod.scan_draft = broken
sys.stdin = io.TextIOWrapper(io.BytesIO(b"[reflux] x\n"), encoding="utf-8")
err = io.StringIO()
with contextlib.redirect_stderr(err):
    status = mod.cmd_scan(None)
assert status == 2, status
assert "scan failed (RuntimeError)" in err.getvalue(), err.getvalue()
assert "boom" not in err.getvalue() and "Traceback" not in err.getvalue(), err.getvalue()
PYEOF

echo "learnings-test: ok"
