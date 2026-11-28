#!/bin/bash
# Checks the release gate reference (#156): gate.py verdicts on fixtures, and the workflow/ruleset/policy statically.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/aidd-release-gate.XXXXXX")
trap 'rm -rf "$work"' EXIT
export PYTHONDONTWRITEBYTECODE=1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# 1. gate.py on every fixture: the verdict, the exit code and the exact reasons.
python3 -B - "$repo_root" "$work" <<'PY' || fail "gate.py fixtures"
import copy, hashlib, json, os, subprocess, sys
root, work = sys.argv[1], sys.argv[2]
gate = os.path.join(root, "examples/assurance/github/gate.py")
policy = os.path.join(root, "examples/assurance/github/gate-policy.json")
approved = os.path.join(root, "examples/assurance/acceptance/approved.sha256")
T, OLD = "1" * 40, "2" * 40
with open(approved, "rb") as fh:
    trusted = "sha256:" + hashlib.sha256(fh.read()).hexdigest()
base_run = {"id": 1, "name": "aidd-verify", "head_sha": T, "status": "completed", "conclusion": "success",
            "started_at": "2026-11-28T00:00:00Z", "app": {"id": 15368, "slug": "github-actions"},
            "check_suite": {"id": 100}}
# The gate's own check run is always present and still running; it must not affect the verdict.
self_run = dict(base_run, id=99, name="aidd-release-gate", status="in_progress", conclusion=None)
base_report = {"schema": "aidd-verify-report/v1", "target_sha": T, "criteria_digest": trusted,
               "passed": ["AT-FLOW-01"], "failed": []}

def swap(value):
    return T if value == "T" else OLD if value == "OLD" else value

def run_gate(runs_text, report_path, extra=()):
    runs_file = os.path.join(work, "runs")
    with open(runs_file, "w", encoding="utf-8") as fh:
        fh.write(runs_text)
    cmd = [sys.executable, "-I", "-B", gate, "--policy", policy, "--target-sha", T,
           "--check-runs", runs_file, "--suite-id", "100", "--report", report_path,
           "--approved", approved, *extra]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.returncode, json.loads(proc.stdout)

with open(os.path.join(root, "tests/assurance/fixtures/release-gate-cases.json"), encoding="utf-8") as fh:
    cases = json.load(fh)["cases"]
ids = [c["id"] for c in cases]
assert len(ids) == len(set(ids)), "duplicate case ids"
for n, case in enumerate(cases):
    runs = [self_run]
    for over in case["runs"]:
        run = copy.deepcopy(base_run)
        run.update({k: swap(v) for k, v in over.items()})
        runs.append(run)
    # Alternate the two input shapes the workflow can produce.
    if n % 2:
        runs_text = json.dumps({"total_count": len(runs), "check_runs": runs})
    else:
        runs_text = "".join(json.dumps(r) + "\n" for r in runs)
    report_path = os.path.join(work, "report-%d.json" % n)
    if isinstance(case["report"], str):
        with open(report_path, "w", encoding="utf-8") as fh:
            fh.write(case["report"][len("RAW:"):])
    elif case["report"] is not None:
        report = dict(base_report, **{k: swap(v) for k, v in case["report"].items()})
        with open(report_path, "w", encoding="utf-8") as fh:
            json.dump(report, fh)
    code, out = run_gate(runs_text, report_path)
    want_code = 0 if case["verdict"] == "pass" else 1
    if (code, out["verdict"], sorted(out["reasons"])) != (want_code, case["verdict"], sorted(case["reasons"])):
        sys.exit("%s: got exit %d %s %s, want exit %d %s %s" % (
            case["id"], code, out["verdict"], sorted(out["reasons"]), want_code, case["verdict"], sorted(case["reasons"])))

# Fail-closed on input the gate cannot read.
good = json.dumps(base_run) + "\n"
good_report = os.path.join(work, "good-report.json")
with open(good_report, "w", encoding="utf-8") as fh:
    json.dump(base_report, fh)
assert run_gate(good, good_report)[0] == 0, "baseline must pass"
for label, runs_text, extra in [
    ("broken check-runs line", good + "{not json\n", ()),
    ("check runs not a list of objects", "[1, 2]", ()),
    ("short target sha", good, ("--target-sha", "abc123")),
]:
    code, out = run_gate(runs_text, good_report, extra)
    if code != 1 or out["verdict"] != "fail" or not out["reasons"][0].startswith("invalid-input:"):
        sys.exit("%s: expected invalid-input, got exit %d %s" % (label, code, out))
proc = subprocess.run([sys.executable, "-I", "-B", gate, "--policy", policy, "--target-sha", T,
                       "--check-runs", os.path.join(work, "runs"), "--report", good_report, "--approved", approved],
                      capture_output=True, text=True)
if proc.returncode != 1 or "needs --suite-id" not in proc.stdout:
    sys.exit("a same_run check without --suite-id must fail: %s" % proc.stdout)
print("gate fixtures: %d cases ok" % len(cases))
PY

# 2. The workflow, ruleset and policy agree with each other and with the trust split in release-gate.md.
python3 -B - "$repo_root" <<'PY' || fail "static checks of the workflow and ruleset"
import json, os, re, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, "tests/assurance"))
import workflow_lint
gh = os.path.join(root, "examples/assurance/github")
text = open(os.path.join(gh, "verification-gate.yml"), encoding="utf-8").read()
wf = workflow_lint.parse(text)
ruleset = json.load(open(os.path.join(gh, "ruleset.json"), encoding="utf-8"))
policy = json.load(open(os.path.join(gh, "gate-policy.json"), encoding="utf-8"))
problems = workflow_lint.lint_workflow(wf, text, {"pull_request", "merge_group"})

def need(cond, msg):
    if not cond:
        problems.append(msg)

jobs = wf.get("jobs") or {}
verify, gate = jobs.get("verify") or {}, jobs.get("gate") or {}
need("merge_group" in wf["on"], "the gate must also run for the merge queue (merge_group)")
need(verify.get("permissions") == {"contents": "read"}, "verify runs the change: it gets contents: read only")
need("if" not in verify, "verify must not be conditional (a skipped required check counts as passed)")
need(gate.get("if") == "${{ always() }}", "gate must run with if: ${{ always() }}")
need("verify" in (gate.get("needs") or []), "gate must need verify")
need(set(gate.get("permissions") or {}) <= {"contents", "checks", "actions"}, "gate asks for more than read access")
for job_id, job in jobs.items():
    if job_id != "verify":
        need("TARGET_SHA" not in json.dumps([s.get("with", {}).get("ref") for s in job.get("steps", [])]),
             "%s checks out the change; only verify may run it" % job_id)
need(wf["env"]["POLICY_SHA"] == "0" * 40, "POLICY_SHA must stay a placeholder in the example")

names = {j.get("name") for j in jobs.values()}
policy_names = {c["name"] for c in policy["required_checks"]}
need(policy_names <= names, "gate-policy.json requires checks the workflow does not define")
need(all(c["app_id"] == 15368 and c.get("same_run") for c in policy["required_checks"]),
     "policy checks must pin the GitHub Actions app and the gate's own run")

# Ruleset: field names follow the REST API body; only the rule types this reference uses.
allowed_top = {"name", "target", "enforcement", "bypass_actors", "conditions", "rules"}
params = {
    "deletion": None, "non_fast_forward": None,
    "pull_request": {"allowed_merge_methods", "dismiss_stale_reviews_on_push", "require_code_owner_review",
                     "require_last_push_approval", "required_approving_review_count",
                     "required_review_thread_resolution", "required_reviewers"},
    "required_status_checks": {"do_not_enforce_on_create", "strict_required_status_checks_policy",
                               "required_status_checks"},
    "workflows": {"do_not_enforce_on_create", "workflows"},
    "merge_queue": {"check_response_timeout_minutes", "grouping_strategy", "max_entries_to_build",
                    "max_entries_to_merge", "merge_method", "min_entries_to_merge",
                    "min_entries_to_merge_wait_minutes"},
}
need(set(ruleset) == allowed_top, "ruleset top-level keys %s" % sorted(ruleset))
need(ruleset["enforcement"] == "active" and ruleset["target"] == "branch", "ruleset must be an active branch ruleset")
need(ruleset["bypass_actors"] == [], "no bypass actors, administrators included")
need(ruleset["conditions"]["ref_name"]["include"] == ["~DEFAULT_BRANCH"], "ruleset targets the default branch")
rules = {}
for rule in ruleset["rules"]:
    t = rule["type"]
    need(t in params and t not in rules, "unexpected or repeated rule %s" % t)
    rules[t] = rule.get("parameters")
    if params.get(t) is None:
        need("parameters" not in rule, "%s takes no parameters" % t)
    else:
        need(set(rule["parameters"]) == params[t], "%s parameters %s" % (t, sorted(rule["parameters"])))
need(set(rules) == set(params), "missing rules: %s" % sorted(set(params) - set(rules)))
pr = rules.get("pull_request") or {}
need(pr.get("require_last_push_approval") is True, "approval of the most recent push is required")
need(pr.get("require_code_owner_review") is True and pr.get("dismiss_stale_reviews_on_push") is True,
     "code owner review, and stale approvals are dismissed")
need(pr.get("required_approving_review_count", 0) >= 1, "at least one approval")
patterns = {p for r in pr.get("required_reviewers", []) for p in r["file_patterns"]}
need({".github/**", "assurance/**"} <= patterns, "workflows and criteria need the owner team's approval")
rsc = rules.get("required_status_checks") or {}
need(rsc.get("strict_required_status_checks_policy") is True, "branches must be up to date (base update)")
contexts = {c["context"]: c.get("integration_id") for c in rsc.get("required_status_checks", [])}
need(set(contexts) == names, "required contexts %s != workflow job names %s" % (sorted(contexts), sorted(names)))
need(set(contexts.values()) == {15368}, "every required check pins the GitHub Actions app (integration_id 15368)")
wfs = (rules.get("workflows") or {}).get("workflows", [])
need(len(wfs) == 1 and wfs[0]["path"].endswith("/verification-gate.yml") and re.fullmatch(r"[0-9a-f]{40}", wfs[0]["sha"]),
     "the required workflow is pinned by path and commit")
mq = rules.get("merge_queue") or {}
need(mq.get("merge_method", "").lower() in pr.get("allowed_merge_methods", []), "merge queue method is an allowed method")

# The doc lists every placeholder the owner must replace before applying anything.
doc = open(os.path.join(root, "docs/assurance/release-gate.md"), encoding="utf-8").read()
for placeholder in ("POLICY_REPO", "POLICY_SHA", "repository_id", "reviewer.id", "CRITERIA_DIR", "所有者の承認後に実測する"):
    need(placeholder in doc, "release-gate.md does not mention %s" % placeholder)
if problems:
    sys.exit("\n".join(problems))
print("static checks: ok")
PY

# 3. The static checks reject the attacks they exist for (each mutation must be caught).
python3 -B - "$repo_root" <<'PY' || fail "mutations of the workflow were not caught"
import os, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, "tests/assurance"))
import workflow_lint
text = open(os.path.join(root, "examples/assurance/github/verification-gate.yml"), encoding="utf-8").read()
mutations = {
    "privileged trigger": ("  pull_request:\n", "  pull_request_target:\n"),
    "write token": ("      checks: read\n", "      checks: write\n"),
    "unpinned action": ("actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n        with:\n          ref: ${{ env.BASE_SHA }}\n          path: trusted",
                        "actions/checkout@v7\n        with:\n          ref: ${{ env.BASE_SHA }}\n          path: trusted"),
    "persisted credentials": ("          path: change\n          persist-credentials: false", "          path: change\n          persist-credentials: true"),
    "secret in the run": ("          GH_TOKEN: ${{ github.token }}", "          GH_TOKEN: ${{ secrets.ADMIN_TOKEN }}"),
    "script injection": ("cut -d' ' -f1)\"", "cut -d' ' -f1)\" # ${{ github.event.pull_request.title }}"),
    "path filter": ("    branches: [main]\n", "    branches: [main]\n    paths: ['src/**']\n"),
    "broad default permissions": ("permissions: {}\n", "permissions: write-all\n"),
}
missed = []
for label, (old, new) in mutations.items():
    if old not in text:
        sys.exit("mutation %r no longer applies; update the test" % label)
    mutated = text.replace(old, new, 1)
    if not workflow_lint.lint_workflow(workflow_lint.parse(mutated), mutated, {"pull_request", "merge_group"}):
        missed.append(label)
if missed:
    sys.exit("not caught: %s" % missed)
print("mutations: %d caught" % len(mutations))
PY

# 4. actionlint, when installed (it is not required; the checks above stand without it).
if command -v actionlint >/dev/null 2>&1; then
  actionlint "$repo_root/examples/assurance/github/verification-gate.yml" || fail "actionlint"
else
  echo "actionlint: not installed, skipped"
fi

if find "$repo_root/examples/assurance/github" "$repo_root/tests/assurance" -name '__pycache__' | grep -q .; then
  fail "__pycache__ written into the repository"
fi

echo "release-gate-test: ok"
