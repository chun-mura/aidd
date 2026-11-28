#!/bin/bash
# Contract test for scripts/issue-outcome.py and the stop points of skills/issue-implement/SKILL.md
# (docs/superpowers/specs/2026-11-28-issue-implement-outcome-design.md, #191).
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/scripts/issue-outcome.py"
skill="$repo_root/skills/issue-implement/SKILL.md"
# An explicit template keeps TMPDIR honored (macOS mktemp -d alone ignores it).
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/aidd-issue-outcome-test.XXXXXX")
tmp_dir=$(cd "$tmp_dir" && pwd -P)
trap 'rm -rf "$tmp_dir"' EXIT

python3 -I - "$script" "$skill" "$tmp_dir" <<'PYEOF'
import copy, importlib.util, json, os, re, subprocess, sys
sys.dont_write_bytecode = True

script, skill, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("issue_outcome", script)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

env = {k: v for k, v in os.environ.items() if k != "AIDD_ISSUE_IMPLEMENT_RUN_ID"}


def run(args, cwd, stdin="", extra_env=None):
    e = dict(env, **(extra_env or {}))
    return subprocess.run([sys.executable, "-I", script, *args], cwd=cwd, input=stdin,
                          capture_output=True, text=True, env=e)


def new_repo(name):
    path = os.path.join(tmp, name)
    os.makedirs(path)
    subprocess.run(["git", "init", "-q", path], check=True)
    os.makedirs(os.path.join(path, "docs"))
    with open(os.path.join(path, "docs", "design.md"), "w") as f:
        f.write("x\n")
    return path


repo = new_repo("repo")

# --- start -----------------------------------------------------------------------------------
r = run(["start"], repo)
assert r.returncode == 0, r.stderr
run_dir = r.stdout.strip()
assert os.path.isabs(run_dir) and os.path.isdir(run_dir), run_dir
assert os.path.dirname(run_dir) == os.path.join(repo, ".aidd", "issue-implement"), run_dir
assert re.fullmatch(r"\d{8}T\d{6}Z-[0-9a-f]{8}", os.path.basename(run_dir)), run_dir

# A host-given run ID is used as is, an existing directory is not reused, a bad ID is refused.
host_id = "20261128T101500Z-0123abcd"
r = run(["start"], repo, extra_env={"AIDD_ISSUE_IMPLEMENT_RUN_ID": host_id})
assert r.returncode == 0 and r.stdout.strip().endswith("/" + host_id), (r.stdout, r.stderr)
r = run(["start"], repo, extra_env={"AIDD_ISSUE_IMPLEMENT_RUN_ID": host_id})
assert r.returncode == 2, (r.returncode, r.stderr)
r = run(["start"], repo, extra_env={"AIDD_ISSUE_IMPLEMENT_RUN_ID": "../escape"})
assert r.returncode == 1, (r.returncode, r.stderr)
assert not os.path.exists(os.path.join(repo, ".aidd", "escape"))
r = run(["start"], tmp)  # not inside a git work tree
assert r.returncode == 2, (r.returncode, r.stderr)

# --- write: valid documents per status --------------------------------------------------------
Q = {"question": "Which?", "kind": "spec_choice",
     "options": [{"label": "A", "effect": "does a"}, {"label": "B", "effect": "does b"}]}
DONE = {"verification": "passed", "undecided_rows": 0, "untracked_deferred": 0, "security_review": "ran"}
BASES = {
    "done": {"issue": "191", "status": "done", "reason": None, "questions": [], "completion": DONE,
             "artifacts": {"design_doc": "docs/design.md", "test_perspectives": None}},
    "needs_input": {"issue": "191", "status": "needs_input", "reason": None, "questions": [Q],
                    "completion": None, "artifacts": {"design_doc": None, "test_perspectives": None}},
    "blocked": {"issue": None, "status": "blocked", "reason": "gh_unavailable", "questions": [],
                "completion": None, "artifacts": {"design_doc": None, "test_perspectives": None}},
}
outcome = os.path.join(run_dir, "outcome.json")
for status, base in BASES.items():
    r = run(["write", run_dir], repo, json.dumps(base))
    assert r.returncode == 0, (status, r.stderr)
    with open(outcome) as f:
        written = json.load(f)
    assert written["schema_version"] == 2 and written["run_id"] == os.path.basename(run_dir), written
    assert {k: v for k, v in written.items() if k not in ("schema_version", "run_id")} == base, written
    r = run(["check", outcome], tmp)
    assert r.returncode == 0, (status, r.stderr)
assert [n for n in os.listdir(run_dir) if n != "outcome.json"] == [], os.listdir(run_dir)

# Every reason and kind in the script is writable.
for reason in mod.REASONS:
    r = run(["write", run_dir], repo, json.dumps(dict(BASES["blocked"], reason=reason)))
    assert r.returncode == 0, (reason, r.stderr)
# A done run states each required step; a security review that was not needed is also done.
for key, allowed in mod.CHECKS.items():
    for value in allowed:
        r = run(["write", run_dir], repo, json.dumps(dict(BASES["done"], completion=dict(DONE, **{key: value}))))
        assert r.returncode == 0, (key, value, r.stderr)
for kind in mod.KINDS:
    q = dict(Q, kind=kind)
    r = run(["write", run_dir], repo, json.dumps(dict(BASES["needs_input"], questions=[q])))
    assert r.returncode == 0, (kind, r.stderr)

# --- write: each rejection, one case each; a rejected write leaves the last good file ----------
with open(outcome, "rb") as f:
    last_good = f.read()


def with_(base, **changes):
    data = copy.deepcopy(BASES[base])
    for key, value in changes.items():
        data[key] = value
    return data


def without(status, key):
    data = copy.deepcopy(BASES[status])
    data.pop(key)
    return data


def q_with(**changes):
    q = copy.deepcopy(Q)
    q.update(changes)
    return with_("needs_input", questions=[q])


rejects = {
    "not json": "{",
    "not an object": "[]",
    "duplicate key": '{"issue": "1", "issue": "2"}',
    "unknown key": json.dumps(with_("done", extra=1)),
    "missing key": json.dumps(without("done", "artifacts")),
    "caller sets run_id": json.dumps(with_("done", run_id="x")),
    "bad status": json.dumps(with_("done", status="finished")),
    "issue not digits": json.dumps(with_("done", issue="#191")),
    "issue as number": json.dumps(with_("done", issue=191)),
    "done with reason": json.dumps(with_("done", reason="gh_unavailable")),
    "done with questions": json.dumps(with_("done", questions=[Q])),
    "done without completion": json.dumps(with_("done", completion=None)),
    "done with failed verification": json.dumps(with_("done", completion=dict(DONE, verification="failed"))),
    "done with undecided rows": json.dumps(with_("done", completion=dict(DONE, undecided_rows=1))),
    "done with untracked deferred": json.dumps(with_("done", completion=dict(DONE, untracked_deferred=2))),
    "done with bool count": json.dumps(with_("done", completion=dict(DONE, undecided_rows=False))),
    "completion extra key": json.dumps(with_("done", completion=dict(DONE, more=0))),
    "done without security_review": json.dumps(with_("done", completion={k: v for k, v in DONE.items() if k != "security_review"})),
    "done with security_review not run": json.dumps(with_("done", completion=dict(DONE, security_review="not_run"))),
    "done with security_review denied": json.dumps(with_("done", completion=dict(DONE, security_review="denied"))),
    "done with security_review null": json.dumps(with_("done", completion=dict(DONE, security_review=None))),
    "done with security_review true": json.dumps(with_("done", completion=dict(DONE, security_review=True))),
    "done with security_review list": json.dumps(with_("done", completion=dict(DONE, security_review=["ran"]))),
    "done with security_review object": json.dumps(with_("done", completion=dict(DONE, security_review={}))),
    "needs_input without questions": json.dumps(with_("needs_input", questions=[])),
    "needs_input with reason": json.dumps(with_("needs_input", reason="gh_unavailable")),
    "needs_input with completion": json.dumps(with_("needs_input", completion=DONE)),
    "blocked without reason": json.dumps(with_("blocked", reason=None)),
    "blocked unknown reason": json.dumps(with_("blocked", reason="tired")),
    "blocked with questions": json.dumps(with_("blocked", questions=[Q])),
    "bad kind": json.dumps(q_with(kind="design")),
    "one option": json.dumps(q_with(options=[Q["options"][0]])),
    "five options": json.dumps(q_with(options=[{"label": str(i), "effect": "e"} for i in range(5)])),
    "duplicate label": json.dumps(q_with(options=[{"label": "A", "effect": "1"}, {"label": "A", "effect": "2"}])),
    "blank question": json.dumps(q_with(question="  ")),
    "blank label": json.dumps(q_with(options=[{"label": "", "effect": "1"}, {"label": "B", "effect": "2"}])),
    "blank effect": json.dumps(q_with(options=[{"label": "A", "effect": " "}, {"label": "B", "effect": "2"}])),
    "long question": json.dumps(q_with(question="x" * 1001)),
    "long label": json.dumps(q_with(options=[{"label": "x" * 81, "effect": "1"}, {"label": "B", "effect": "2"}])),
    "long effect": json.dumps(q_with(options=[{"label": "A", "effect": "x" * 401}, {"label": "B", "effect": "2"}])),
    "option extra key": json.dumps(q_with(options=[{"label": "A", "effect": "1", "x": 1}, {"label": "B", "effect": "2"}])),
    "question extra key": json.dumps(q_with(note="x")),
    "artifacts extra key": json.dumps(with_("done", artifacts={"design_doc": None, "test_perspectives": None, "plan": None})),
    "artifacts missing key": json.dumps(with_("done", artifacts={"design_doc": None})),
    "artifact absolute": json.dumps(with_("done", artifacts={"design_doc": "/etc/hosts", "test_perspectives": None})),
    "artifact dotdot": json.dumps(with_("done", artifacts={"design_doc": "docs/../docs/design.md", "test_perspectives": None})),
    "artifact missing": json.dumps(with_("done", artifacts={"design_doc": "docs/none.md", "test_perspectives": None})),
    "artifact directory": json.dumps(with_("done", artifacts={"design_doc": "docs", "test_perspectives": None})),
}
for name, raw in rejects.items():
    r = run(["write", run_dir], repo, raw)
    assert r.returncode == 1, (name, r.returncode, r.stderr)
    assert r.stderr.strip(), name
    with open(outcome, "rb") as f:
        assert f.read() == last_good, name
# A done whose security review did not run points the writer at the blocked reason to use instead.
r = run(["write", run_dir], repo, json.dumps(with_("done", completion=dict(DONE, security_review="not_run"))))
assert r.returncode == 1 and "required_check_not_run" in r.stderr, r.stderr
r = run(["write", run_dir], repo, json.dumps(with_("done", completion=dict(DONE, security_review="secret-value-xyz"))))
assert r.returncode == 1 and "secret-value-xyz" not in r.stderr, r.stderr
# A rejection names the problem but never repeats the offending value.
r = run(["write", run_dir], repo, json.dumps(with_("blocked", reason="secret-value-xyz")))
assert r.returncode == 1 and "secret-value-xyz" not in r.stderr, r.stderr

# --- write: the run directory must be the expected, real directory -----------------------------
good = json.dumps(BASES["blocked"])
r = run(["write", os.path.join(repo, "docs")], repo, good)
assert r.returncode == 1, ("not a run dir", r.stderr)
r = run(["write", os.path.join(repo, ".aidd", "issue-implement", "20261128T000000Z-ffffffff")], repo, good)
assert r.returncode == 2, ("run dir not created by start", r.stderr)

outside = os.path.join(tmp, "outside")
os.makedirs(outside)
# run dir itself is a symlink
link_id = "20261128T000001Z-00000001"
os.symlink(outside, os.path.join(repo, ".aidd", "issue-implement", link_id))
r = run(["write", os.path.join(repo, ".aidd", "issue-implement", link_id)], repo, good)
assert r.returncode == 1 and os.listdir(outside) == [], ("symlinked run dir", r.stderr)
# outcome.json is a symlink
r = run(["start"], repo)
dir2 = r.stdout.strip()
os.symlink(os.path.join(outside, "target.json"), os.path.join(dir2, "outcome.json"))
r = run(["write", dir2], repo, good)
assert r.returncode == 1 and os.listdir(outside) == [], ("symlinked outcome", r.stderr)
# a parent (.aidd/issue-implement) is a symlink
repo2 = new_repo("repo2")
os.makedirs(os.path.join(repo2, ".aidd"))
os.makedirs(os.path.join(outside, "ii", "20261128T000002Z-00000002"))
os.symlink(os.path.join(outside, "ii"), os.path.join(repo2, ".aidd", "issue-implement"))
r = run(["write", os.path.join(repo2, ".aidd", "issue-implement", "20261128T000002Z-00000002")], repo2, good)
assert r.returncode == 1, ("symlinked parent", r.stderr)
assert os.listdir(os.path.join(outside, "ii", "20261128T000002Z-00000002")) == []
r = run(["start"], repo2)
assert r.returncode == 2, ("start under symlinked parent", r.stderr)

# write does not run git: it still works with git removed from PATH.
r = subprocess.run([sys.executable, "-I", script, "write", run_dir], cwd=repo, input=good,
                   capture_output=True, text=True, env=dict(env, PATH="/nonexistent"))
assert r.returncode == 0, r.stderr

# --- check ----------------------------------------------------------------------------------
r = run(["check", outcome, "--issue", "191"], tmp)
assert r.returncode == 1, "blocked doc has issue null, --issue 191 must not match"
r = run(["write", run_dir], repo, json.dumps(BASES["needs_input"]))
assert r.returncode == 0, r.stderr
assert run(["check", outcome, "--issue", "191"], tmp).returncode == 0
assert run(["check", outcome, "--issue", "192"], tmp).returncode == 1
with open(outcome) as f:
    doc = json.load(f)
def check_fixture(name, content, layout=True):
    if layout:
        path = os.path.join(tmp, "check-" + name.replace(" ", "-"), ".aidd", "issue-implement", os.path.basename(run_dir))
    else:
        path = os.path.join(tmp, "check-" + name.replace(" ", "-"), os.path.basename(run_dir))
    os.makedirs(path)
    with open(os.path.join(path, "outcome.json"), "wb") as f:
        f.write(content if isinstance(content, bytes) else json.dumps(content).encode())
    return run(["check", os.path.join(path, "outcome.json")], tmp)


assert check_fixture("good copy", doc).returncode == 0
for name, bad in {
    "old schema": dict(doc, schema_version=1),
    "run_id mismatch": dict(doc, run_id="20261128T000000Z-00000000"),
    "missing run_id": {k: v for k, v in doc.items() if k != "run_id"},
    "not utf-8": b'{"issue": "\xff"}',
    "not json": b"{",
    "duplicate key": b'{"status": "done", "status": "done"}',
}.items():
    r = check_fixture(name, bad)
    assert r.returncode == 1, (name, r.stderr)
r = check_fixture("outside layout", doc, layout=False)
assert r.returncode == 1, ("outside layout", r.stderr)
assert run(["check", os.path.join(tmp, "nothing.json")], tmp).returncode == 1  # outside the layout
r = run(["start"], repo)
empty_dir = r.stdout.strip()
assert run(["check", os.path.join(empty_dir, "outcome.json")], tmp).returncode == 2  # in the layout, not written
# check reads only <run dir>/outcome.json and follows no symlink to it.
other = os.path.join(run_dir, "other.json")
with open(outcome, "rb") as src, open(other, "wb") as dst:
    dst.write(src.read())
r = run(["check", other], tmp)
assert r.returncode == 1, ("other file name", r.stderr)
os.remove(other)
r = run(["start"], repo)
link_dir = r.stdout.strip()
# The link target is valid for link_dir (same run_id), so only the symlink itself can be the reason.
with open(outcome) as f:
    linked = dict(json.load(f), run_id=os.path.basename(link_dir))
target = os.path.join(outside, "linked-outcome.json")
with open(target, "w") as f:
    json.dump(linked, f)
os.symlink(target, os.path.join(link_dir, "outcome.json"))
r = run(["check", os.path.join(link_dir, "outcome.json")], tmp)
assert r.returncode == 1, ("symlinked outcome for check", r.stderr)
r = run(["start"], repo)
dir_outcome = os.path.join(r.stdout.strip(), "outcome.json")
os.mkdir(dir_outcome)
r = run(["check", dir_outcome], tmp)
assert r.returncode == 1, ("outcome.json is a directory", r.returncode, r.stderr)
r = run(["check", os.path.join(repo2, ".aidd", "issue-implement", "20261128T000002Z-00000002", "outcome.json")], tmp)
assert r.returncode == 1, ("symlinked parent for check", r.stderr)

# A done outcome whose artifact was removed afterwards no longer checks.
r = run(["write", run_dir], repo, json.dumps(BASES["done"]))
assert r.returncode == 0, r.stderr
os.rename(os.path.join(repo, "docs", "design.md"), os.path.join(repo, "docs", "moved.md"))
assert run(["check", outcome], tmp).returncode == 1
os.rename(os.path.join(repo, "docs", "moved.md"), os.path.join(repo, "docs", "design.md"))

# --- write: inputs that used to end in a traceback end in a rejection, leaving no temp file ----
for name, raw in {
    "non-string label": json.dumps(q_with(options=[{"label": [1], "effect": "1"}, {"label": "B", "effect": "2"}])),
    "lone surrogate": '{"issue": null, "status": "needs_input", "reason": null, "completion": null, '
                      '"artifacts": {"design_doc": null, "test_perspectives": null}, '
                      '"questions": [{"question": "q\\ud800", "kind": "approval", '
                      '"options": [{"label": "A", "effect": "1"}, {"label": "B", "effect": "2"}]}]}',
}.items():
    r = run(["write", run_dir], repo, raw)
    assert r.returncode == 1 and "rejected" in r.stderr and "Traceback" not in r.stderr, (name, r.stderr)
r = subprocess.run([sys.executable, "-I", script, "write", run_dir], cwd=repo, env=env, capture_output=True,
                   input=json.dumps(BASES["blocked"]).encode().replace(b"null", b'"\xff"', 1))
assert r.returncode == 1 and b"Traceback" not in r.stderr, r.stderr
assert [n for n in os.listdir(run_dir) if n != "outcome.json"] == [], os.listdir(run_dir)
# Deep nesting, a NUL in a path and a trailing newline in an ID are rejections, not tracebacks.
for name, raw in {
    "nested too deeply": "[" * 200000,
    "NUL in artifact": json.dumps(with_("done", artifacts={"design_doc": "docs/\u0000", "test_perspectives": None})),
    "newline after issue": json.dumps(with_("done", issue="191\n")),
}.items():
    r = run(["write", run_dir], repo, raw)
    assert r.returncode == 1 and "Traceback" not in r.stderr, (name, r.returncode, r.stderr)
r = run(["start"], repo, extra_env={"AIDD_ISSUE_IMPLEMENT_RUN_ID": "20261128T000003Z-00000003\n"})
assert r.returncode == 1 and r.stdout == "", ("newline after run id", r.stdout, r.stderr)
# An unknown key's name is not repeated either.
r = run(["write", run_dir], repo, json.dumps(with_("done", secret_key_xyz=1)))
assert r.returncode == 1 and "secret_key_xyz" not in r.stderr, r.stderr

# An artifact reached through a symlink is not followed.
os.symlink(os.path.join(repo, "docs", "design.md"), os.path.join(repo, "docs", "link.md"))
os.symlink(os.path.join(repo, "docs"), os.path.join(repo, "docslink"))
for path in ("docs/link.md", "docslink/design.md", "docs//design.md", "./docs/design.md"):
    r = run(["write", run_dir], repo, json.dumps(with_("done", artifacts={"design_doc": path, "test_perspectives": None})))
    assert r.returncode == 1, (path, r.stderr)

# start refuses when .aidd itself is a symlink.
repo3 = new_repo("repo3")
os.makedirs(os.path.join(outside, "aidd3"))
os.symlink(os.path.join(outside, "aidd3"), os.path.join(repo3, ".aidd"))
r = run(["start"], repo3)
assert r.returncode == 2 and os.listdir(os.path.join(outside, "aidd3")) == [], r.stderr

# --- SKILL.md: stop-point markers, the section 8 table and the script enums agree -------------
with open(skill, encoding="utf-8") as f:
    text = f.read()
head, sep, tail = text.partition("\n## 8. ")
assert sep, "SKILL.md has no section 8"
marker = re.compile(r"`outcome: (done|needs_input|blocked)(?:/([a-z_]+))?`")
in_steps = set(marker.findall(head))
in_table = set(marker.findall(tail))
assert in_steps == in_table, (sorted(in_steps ^ in_table))
expected = {("done", "")} | {("blocked", r) for r in mod.REASONS} | {("needs_input", k) for k in mod.KINDS}
assert in_steps == expected, (sorted(in_steps ^ expected))
# Each stop point carries its marker in its own section, not just somewhere in the file.
sections = {m.group(1): m.start() for m in re.finditer(r"^## (\d+)\. ", head, re.M)}
order = sorted(sections, key=sections.get)
bodies = {n: head[sections[n]:(sections[order[i + 1]] if i + 1 < len(order) else len(head))]
          for i, n in enumerate(order)}
per_section = {
    "1": {("blocked", "gh_unavailable")},
    "2": {("needs_input", "spec_choice")},
    "3": {("blocked", "review_unconverged"), ("blocked", "split_proposed")},
    "5": {("blocked", "review_unconverged"), ("blocked", "audit_session_launched"),
          ("blocked", "required_check_not_run")},
    "6": {("needs_input", "approval"), ("blocked", "verification_failed")},
    "7": {("done", ""), ("blocked", "undecided_rows"), ("blocked", "incomplete")},
}
for number, markers in per_section.items():
    found = set(marker.findall(bodies[number]))
    assert markers <= found, (number, sorted(markers - found))
assert "../../scripts/issue-outcome.py" in text
PYEOF

echo "issue-outcome-test: ok"
