#!/bin/bash
# Checks the evidence reference (#157): verify_evidence.py verdicts on fixtures, and provenance.yml statically.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/aidd-evidence.XXXXXX")
trap 'rm -rf "$work"' EXIT
export PYTHONDONTWRITEBYTECODE=1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# 1. verify_evidence.py on every fixture: the verdict, the exit code and the exact reasons.
python3 -B - "$repo_root" "$work" <<'PY' || fail "verify_evidence.py fixtures"
import copy, hashlib, json, os, subprocess, sys
root, work = sys.argv[1], sys.argv[2]
script = os.path.join(root, "examples/assurance/evidence/verify_evidence.py")
policy_path = os.path.join(root, "examples/assurance/evidence/policy.json")
policy = json.load(open(policy_path, encoding="utf-8"))
NOW, SOURCE, REF = "2026-11-28T00:00:00Z", "3" * 40, "refs/tags/v1.2.3"
ARTIFACT_BYTES = b"fictional release artifact\n"
ARTIFACT = hashlib.sha256(ARTIFACT_BYTES).hexdigest()
OTHER = "5" * 64
CRITERIA = policy["criteria_digest"].split(":", 1)[1]
cert = {
    "issuer": "https://token.actions.githubusercontent.com",
    "subjectAlternativeName": "https://github.com/example-org/assurance-policy/.github/workflows/provenance.yml@refs/heads/main",
    "buildSignerURI": "https://github.com/example-org/assurance-policy/.github/workflows/provenance.yml@refs/heads/main",
    "buildConfigURI": "https://github.com/example-org/example-app/.github/workflows/release.yml@refs/tags/v1.2.3",
    "runnerEnvironment": "github-hosted",
    "sourceRepositoryURI": "https://github.com/example-org/example-app",
    "sourceRepositoryDigest": SOURCE,
    "sourceRepositoryRef": REF,
    "runInvocationURI": "https://github.com/example-org/example-app/actions/runs/1001/attempts/1",
}

def entry(kind):
    predicate_type = policy["required_predicates"]["provenance" if kind == "provenance" else "test-result"]
    if kind == "provenance":
        predicate = {"buildDefinition": {"buildType": "https://actions.github.io/buildtypes/workflow/v1"}, "runDetails": {}}
    else:
        predicate = {"result": "PASSED",
                     "configuration": [{"name": "app.tar.gz", "digest": {"sha256": ARTIFACT}},
                                       {"name": "approved.sha256", "digest": {"sha256": CRITERIA}}],
                     "url": "https://github.com/example-org/example-app/actions/runs/1001",
                     "passedTests": ["AT-FLOW-01", "AT-PAY-P"], "warnedTests": [], "failedTests": []}
    return {"verificationResult": {
        "mediaType": "application/vnd.dev.sigstore.bundle.v0.3+json",
        "statement": {"_type": "https://in-toto.io/Statement/v1",
                      "subject": [{"name": "app.tar.gz", "digest": {"sha256": ARTIFACT}}],
                      "predicateType": predicate_type, "predicate": predicate},
        "signature": {"certificate": dict(cert)},
        "verifiedTimestamps": [{"type": "Tlog", "uri": "https://rekor.example.invalid", "timestamp": "2026-11-27T12:00:00Z"}],
    }}

def digest(value):
    return ARTIFACT if value == "ARTIFACT" else OTHER if value == "OTHER" else value

def apply(e, over):
    r = e["verificationResult"]
    for k, v in (over.get("cert") or {}).items():
        r["signature"]["certificate"][k] = v
    if "subject" in over:
        r["statement"]["subject"][0]["digest"]["sha256"] = digest(over["subject"])
    if "predicateType" in over:
        r["statement"]["predicateType"] = over["predicateType"]
    if "predicate" in over:
        r["statement"]["predicate"].update(over["predicate"])
    config = r["statement"]["predicate"].get("configuration") or []
    if "artifact_in_config" in over:
        config[0]["digest"]["sha256"] = digest(over["artifact_in_config"])
    if "criteria_in_config" in over:
        config[1]["digest"]["sha256"] = digest(over["criteria_in_config"])
    if "timestamps" in over:
        r["verifiedTimestamps"] = [{"type": "Tlog", "uri": "https://rekor.example.invalid", "timestamp": t}
                                   for t in over["timestamps"]]
    return e

def run(entries_by_file, artifact_bytes=ARTIFACT_BYTES, extra_args=(), source=SOURCE):
    artifact = os.path.join(work, "app.tar.gz")
    with open(artifact, "wb") as fh:
        fh.write(artifact_bytes)
    files = []
    for n, entries in enumerate(entries_by_file):
        path = os.path.join(work, "att-%d.json" % n)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(entries if isinstance(entries, str) else json.dumps(entries))
        files.append(path)
    cmd = [sys.executable, "-I", "-B", script, "--policy", policy_path, "--artifact", artifact,
           "--source-digest", source, "--source-ref", REF, "--now", NOW, "--attestations", *files, *extra_args]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.returncode, json.loads(proc.stdout)

cases = json.load(open(os.path.join(root, "tests/assurance/fixtures/evidence-cases.json"), encoding="utf-8"))["cases"]
ids = [c["id"] for c in cases]
assert len(ids) == len(set(ids)), "duplicate case ids"
for case in cases:
    prov, tres = [], []
    for kind, bucket in (("provenance", prov), ("test_result", tres)):
        if kind in case and case[kind] is None:
            continue
        e = apply(entry(kind), copy.deepcopy(case.get("both") or {}))
        bucket.append(apply(e, copy.deepcopy(case.get(kind) or {})))
    for extra in case.get("extra", []):
        (prov if extra["kind"] == "provenance" else tres).append(apply(entry(extra["kind"]), copy.deepcopy(extra)))
    artifact_bytes = b"tampered artifact\n" if case.get("artifact") == "tampered" else ARTIFACT_BYTES
    code, out = run([prov, tres], artifact_bytes)
    want = (0 if case["verdict"] == "pass" else 1, case["verdict"], sorted(case["reasons"]))
    got = (code, out["verdict"], sorted(out["reasons"]))
    if got != want:
        sys.exit("%s: got %s, want %s" % (case["id"], got, want))

# Fail-closed on input it cannot read.
good = [[entry("provenance")], [entry("test_result")]]
assert run(good)[0] == 0, "baseline must pass"
for label, files, source in [
    ("broken JSON", [good[0], "{not json"], SOURCE),
    ("not a list", [good[0], json.dumps({"verificationResult": {}})], SOURCE),
    ("entry without a certificate", [good[0], json.dumps([{"verificationResult": {"statement": {}}}])], SOURCE),
    ("short source digest", good, "abc123"),
]:
    code, out = run(files, source=source)
    if code != 1 or not out["reasons"][0].startswith("invalid-input:"):
        sys.exit("%s: expected invalid-input, got %s %s" % (label, code, out))
print("evidence fixtures: %d cases ok" % len(cases))
PY

# 2. provenance.yml: least privilege, signing only in a job that runs no project code, and agreement with the policy.
python3 -B - "$repo_root" <<'PY' || fail "static checks of provenance.yml and the policy"
import hashlib, json, os, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, "tests/assurance"))
import workflow_lint
text = open(os.path.join(root, "examples/assurance/github/provenance.yml"), encoding="utf-8").read()
policy = json.load(open(os.path.join(root, "examples/assurance/evidence/policy.json"), encoding="utf-8"))
SIGNING = {"attest": {"id-token": "write", "attestations": "write"}}

def check(text):
    wf = workflow_lint.parse(text)
    problems = workflow_lint.lint_workflow(wf, text, {"workflow_call"}, SIGNING)
    jobs = wf.get("jobs") or {}
    attest = jobs.get("attest") or {}
    if set(attest.get("needs") or []) != {"build", "verify"} or "if" in attest:
        problems.append("attest must need build and verify and run only when both passed")
    for job_id, job in jobs.items():
        uses = [s.get("uses", "") for s in job.get("steps") or []]
        signs = any(u.startswith(("actions/attest@", "actions/attest-build-provenance@")) for u in uses)
        if job_id != "attest" and signs:
            problems.append("%s signs; only attest may" % job_id)
        if job_id == "attest" and any(u.startswith("actions/checkout@") for u in uses):
            problems.append("attest checks out project code next to the signing token")
    types = [s.get("with", {}).get("predicate-type") for s in attest.get("steps") or [] if "predicate-type" in s.get("with", {})]
    if types != [policy["required_predicates"]["test-result"]]:
        problems.append("attested predicate types %s do not match the policy" % types)
    if wf.get("env", {}).get("SUBJECT") != policy["subject_name"]:
        problems.append("SUBJECT does not match subject_name in the policy")
    return problems

problems = check(text)
with open(os.path.join(root, "examples/assurance/acceptance/approved.sha256"), "rb") as fh:
    if policy["criteria_digest"] != "sha256:" + hashlib.sha256(fh.read()).hexdigest():
        problems.append("policy criteria_digest is not the digest of the example's approved.sha256")
if not policy["signer_workflow"].endswith("/.github/workflows/provenance.yml"):
    problems.append("policy signer_workflow does not name provenance.yml")
doc = open(os.path.join(root, "docs/assurance/evidence.md"), encoding="utf-8").read()
for phrase in ("所有者の承認後に実測する", "宣言しない", "保持期間", "アクセス権", "#122", "gh attestation verify"):
    if phrase not in doc:
        problems.append("evidence.md does not mention %s" % phrase)
if problems:
    sys.exit("\n".join(problems))

# Each mutation that would hand signing to project code or untrusted events must be caught.
mutations = {
    "signing token in build": ("    permissions:\n      contents: read\n    outputs:", "    permissions:\n      contents: read\n      id-token: write\n    outputs:"),
    "checkout in attest": ("      - name: Download the artifact\n        uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2\n        with:\n          name: dist\n          path: dist\n\n      - name: Download the test result",
                           "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n        with:\n          persist-credentials: false\n      - name: Download the test result"),
    "attest despite failed tests": ("    needs: [build, verify]\n", "    needs: [build, verify]\n    if: ${{ always() }}\n"),
    "pull request trigger": ("  workflow_call: {}\n", "  workflow_call: {}\n  pull_request: {}\n"),
    "contents write": ("      contents: read\n      id-token: write\n", "      contents: write\n      id-token: write\n"),
}
missed = []
for label, (old, new) in mutations.items():
    if old not in text:
        sys.exit("mutation %r no longer applies; update the test" % label)
    if not check(text.replace(old, new, 1)):
        missed.append(label)
if missed:
    sys.exit("not caught: %s" % missed)
print("provenance static checks: ok, %d mutations caught" % len(mutations))
PY

if command -v actionlint >/dev/null 2>&1; then
  actionlint "$repo_root/examples/assurance/github/provenance.yml" || fail "actionlint"
else
  echo "actionlint: not installed, skipped"
fi

if find "$repo_root/examples/assurance" "$repo_root/tests/assurance" -name '__pycache__' | grep -q .; then
  fail "__pycache__ written into the repository"
fi

echo "evidence-test: ok"
