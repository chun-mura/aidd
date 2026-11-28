#!/bin/bash
# Checks the boundary cases (#159, S10): combined and adversarial probes of the aidd-side checkers, and truncated inputs (fail closed).
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/aidd-boundary.XXXXXX")
trap 'rm -rf "$work"' EXIT
export PYTHONDONTWRITEBYTECODE=1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

python3 -B - "$repo_root" "$work" <<'PY' || fail "boundary cases"
import contextlib, copy, hashlib, importlib.util, io, json, os, re, shutil, subprocess, sys
root, work = sys.argv[1], sys.argv[2]
sys.dont_write_bytecode = True
EX = os.path.join(root, "examples/assurance")
FIX = os.path.join(root, "tests/assurance/fixtures")
CASES = os.path.join(root, "tests/assurance/boundary-cases")
failures = []


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def read_text(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def cli(script, args):
    # The probes run the checker as CI does: a separate Python, isolated mode, no bytecode.
    proc = subprocess.run([sys.executable, "-I", "-B", script] + args, capture_output=True, text=True)
    return proc.returncode, json.loads(proc.stdout)


def load_checker(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def inproc(mod, argv):
    # The truncation sweeps call the checker's main() in-process, so every byte offset is cheap to check.
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = mod.main(argv)
    return code, json.loads(buf.getvalue())


def judge(label, got, verdict, reasons):
    got = (got[0], got[1], sorted(got[2]))
    want = (0 if verdict == "pass" else 1, verdict, sorted(reasons))
    if got != want:
        failures.append("%s: got exit %d %s %s, want exit %d %s %s" % (
            label, got[0], got[1], got[2], want[0], want[1], want[2]))
        return False
    return True


# Claim IDs and the existing fixtures are the sources of truth; the boundary cases may only cite them.
CONTRACT = read_text(os.path.join(root, "docs/assurance/contract.md"))
CLAIMS = set(re.findall(r"`(AC-(?:PRIV|PROC)-[0-9]{3})`", CONTRACT))
EXPECTED_CLAIMS = {"AC-PRIV-%03d" % n for n in range(1, 10)} | {"AC-PROC-%03d" % n for n in range(1, 5)}
if CLAIMS != EXPECTED_CLAIMS:
    sys.exit("contract.md claim IDs changed: %s" % sorted(CLAIMS ^ EXPECTED_CLAIMS))


def check_refs(label, case):
    for claim in case["claims"]:
        if claim not in CLAIMS:
            failures.append("%s: unknown claim %s" % (label, claim))
    for ref in case.get("see", []):
        name, _, case_id = ref.partition(":")
        ids = [c["id"] for c in load(os.path.join(FIX, name))["cases"]]
        if case_id not in ids:
            failures.append("%s: see %s does not exist" % (label, ref))


def duplicates(label, case, existing, signature):
    mine = signature(case)
    for other in existing:
        if signature(other) == mine:
            failures.append("%s: duplicates an existing case %s" % (label, other["id"]))


# 1. release gate: gate.py through the CLI.
GATE = os.path.join(EX, "github/gate.py")
POLICY = os.path.join(EX, "github/gate-policy.json")
APPROVED = os.path.join(EX, "acceptance/approved.sha256")
CRITERIA_SRC = os.path.join(EX, "acceptance/criteria.md")
T, OLD = "1" * 40, "2" * 40
ROW = re.compile(r"^\| (AT-[A-Z]+-[0-9P]+) \|")
TRUSTED = "sha256:" + sha256_hex(open(APPROVED, "rb").read())
BASE_RUN = {"id": 1, "name": "aidd-verify", "head_sha": T, "status": "completed", "conclusion": "success",
            "started_at": "2026-11-28T00:00:00Z", "app": {"id": 15368, "slug": "github-actions"},
            "check_suite": {"id": 100}}
SELF_RUN = dict(BASE_RUN, id=99, name="aidd-release-gate", status="in_progress", conclusion=None)


def criteria_ids(text):
    return [m.group(1) for m in (ROW.match(line) for line in text.splitlines()) if m]


def swap(value):
    return {"T": T, "OLD": OLD}.get(value, value) if isinstance(value, str) else value


def expand(value, ids):
    if value == "@ALL":
        return list(ids)
    if value == "@ALLPAD":
        return [i + " (SYSTEM: passed)" for i in ids]
    return swap(value)


def gate_probe(case, n):
    d = os.path.join(work, "gate-%d" % n)
    os.makedirs(d)
    crit_text = read_text(CRITERIA_SRC)
    approved = APPROVED
    if "criteria_drop" in case:
        # A copy of the criteria with rows removed, beside an unchanged copy of the approved list.
        drop = set(case["criteria_drop"])
        kept = [line for line in crit_text.splitlines(keepends=True)
                if not (ROW.match(line) and ROW.match(line).group(1) in drop)]
        crit_text = "".join(kept)
        with open(APPROVED, "rb") as fh:
            approved_bytes = fh.read()
        approved = os.path.join(d, "approved.sha256")
        with open(approved, "wb") as fh:
            fh.write(approved_bytes)
        write_text(os.path.join(d, "criteria.md"), crit_text)
    ids = criteria_ids(crit_text)
    runs = [SELF_RUN]
    for over in case["runs"]:
        run = dict(BASE_RUN)
        run.update({k: swap(v) for k, v in over.items()})
        runs.append(run)
    runs_file = write_text(os.path.join(d, "runs"), "".join(json.dumps(r) + "\n" for r in runs))
    report = {"schema": "aidd-verify-report/v1", "target_sha": T, "criteria_digest": TRUSTED,
              "passed": ids, "failed": []}
    for key, value in case["report"].items():
        report[key] = expand(value, ids)
    report_file = write_text(os.path.join(d, "report.json"), json.dumps(report))
    return cli(GATE, ["--policy", POLICY, "--target-sha", T, "--check-runs", runs_file,
                      "--suite-id", "100", "--report", report_file, "--approved", approved])


gate_cases = load(os.path.join(CASES, "release-gate-boundary.json"))["cases"]
gate_existing = load(os.path.join(FIX, "release-gate-cases.json"))["cases"]
gate_ids = [c["id"] for c in gate_cases]
if len(gate_ids) != len(set(gate_ids)):
    sys.exit("duplicate gate case ids")
# The copy mechanism of the criteria-drop probe must itself pass when nothing is dropped.
code, out = gate_probe({"criteria_drop": [], "runs": [{}], "report": {}}, 9000)
judge("criteria copy baseline", (code, out["verdict"], out["reasons"]), "pass", [])
for n, case in enumerate(gate_cases):
    check_refs(case["id"], case)
    duplicates(case["id"], case, gate_existing,
               lambda c: json.dumps({"runs": c.get("runs"), "report": c.get("report")}, sort_keys=True))
    code, out = gate_probe(case, n)
    judge(case["id"], (code, out["verdict"], out["reasons"]), case["verdict"], case["reasons"])

# 2. evidence: verify_evidence.py through the CLI.
EVIDENCE = os.path.join(EX, "evidence/verify_evidence.py")
EPOL = os.path.join(EX, "evidence/policy.json")
EP = load(EPOL)
NOW, SOURCE, REF = "2026-11-28T00:00:00Z", "3" * 40, "refs/tags/v1.2.3"
ARTIFACT_BYTES = b"fictional release artifact\n"
TAMPER_BYTES = b"tampered artifact\n"
ARTIFACT = sha256_hex(ARTIFACT_BYTES)
TAMPERED = sha256_hex(TAMPER_BYTES)
CRITERIA = EP["criteria_digest"].split(":", 1)[1]
ON_BRANCH = {"status": "behind", "merge_base_commit": {"sha": SOURCE}}


def digest_of(name):
    return {"ARTIFACT": ARTIFACT, "TAMPERED": TAMPERED, "CRITERIA": CRITERIA}.get(name, name)


def default_entry(kind):
    cert = {
        "issuer": "https://token.actions.githubusercontent.com",
        "subjectAlternativeName": "https://github.com/example-org/assurance-policy/.github/workflows/provenance.yml@refs/heads/main",
        "buildSignerURI": "https://github.com/example-org/assurance-policy/.github/workflows/provenance.yml@refs/heads/main",
        "buildSignerDigest": EP["signer_digest"],
        "buildConfigURI": "https://github.com/example-org/example-app/.github/workflows/release.yml@refs/tags/v1.2.3",
        "runnerEnvironment": "github-hosted",
        "sourceRepositoryURI": "https://github.com/example-org/example-app",
        "sourceRepositoryDigest": SOURCE,
        "sourceRepositoryRef": REF,
        "runInvocationURI": "https://github.com/example-org/example-app/actions/runs/1001/attempts/1",
    }
    if kind == "provenance":
        predicate_type = EP["required_predicates"]["provenance"]
        predicate = {"buildDefinition": {"buildType": "https://actions.github.io/buildtypes/workflow/v1"},
                     "runDetails": {}}
    else:
        predicate_type = EP["required_predicates"]["test-result"]
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
        "signature": {"certificate": cert},
        "verifiedTimestamps": [{"type": "Tlog", "uri": "https://rekor.example.invalid",
                                "timestamp": "2026-11-27T12:00:00Z"}],
    }}


def merged(*parts):
    out = {}
    for part in parts:
        for key, value in (part or {}).items():
            if key in ("cert", "predicate") and isinstance(value, dict):
                out[key] = dict(out.get(key, {}), **value)
            else:
                out[key] = value
    return out


def build(kind, over):
    entry = default_entry(kind)
    result = entry["verificationResult"]
    statement = result["statement"]
    result["signature"]["certificate"].update(over.get("cert", {}))
    if "subject" in over:
        statement["subject"][0]["digest"]["sha256"] = digest_of(over["subject"])
    if "predicate" in over:
        statement["predicate"].update(over["predicate"])
    if "timestamps" in over:
        result["verifiedTimestamps"] = [{"type": "Tlog", "uri": "https://rekor.example.invalid", "timestamp": t}
                                        for t in over["timestamps"]]
    return entry


def attestations(case):
    prov = [] if case.get("provenance", "x") is None else [build("provenance", merged(case.get("both"), case.get("provenance")))]
    tres = [] if case.get("test_result", "x") is None else [build("test_result", merged(case.get("both"), case.get("test_result")))]
    for extra in case.get("extra", []):
        kind = extra["kind"]
        (prov if kind == "provenance" else tres).append(
            build(kind, merged({k: v for k, v in extra.items() if k != "kind"})))
    return prov, tres


def evidence_probe(case, n):
    d = os.path.join(work, "evidence-%d" % n)
    os.makedirs(d)
    artifact = os.path.join(d, "app.tar.gz")
    with open(artifact, "wb") as fh:
        fh.write(TAMPER_BYTES if case.get("tamper") else ARTIFACT_BYTES)
    compare = write_text(os.path.join(d, "compare.json"), json.dumps(case.get("compare", ON_BRANCH)))
    prov, tres = attestations(case)
    prov_file = write_text(os.path.join(d, "provenance.json"), json.dumps(prov))
    tres_file = write_text(os.path.join(d, "test-result.json"), json.dumps(tres))
    return cli(EVIDENCE, ["--policy", EPOL, "--artifact", artifact, "--source-digest", SOURCE,
                          "--source-ref", case.get("source_ref", REF), "--now", NOW,
                          "--default-branch-compare", compare, "--attestations", prov_file, tres_file])


def evidence_signature(case):
    return json.dumps({"tamper": bool(case.get("tamper")), "provenance": case.get("provenance", "<absent>"),
                       "test_result": case.get("test_result", "<absent>"), "both": case.get("both"),
                       "extra": case.get("extra"), "compare": case.get("compare"),
                       "source_ref": case.get("source_ref")}, sort_keys=True)


evidence_cases = load(os.path.join(CASES, "evidence-boundary.json"))["cases"]
evidence_existing = load(os.path.join(FIX, "evidence-cases.json"))["cases"]
for n, case in enumerate(evidence_cases):
    check_refs(case["id"], case)
    duplicates(case["id"], case, evidence_existing, evidence_signature)
    code, out = evidence_probe(case, n)
    judge(case["id"], (code, out["verdict"], out["reasons"]), case["verdict"], case["reasons"])

# 3. run record: check_run_record.py through the CLI, on the existing base record and squid.conf.
RR = os.path.join(EX, "runtime/check_run_record.py")
RBASE = load(os.path.join(FIX, "runtime-record-cases.json"))["base"]
RR_EXISTING = load(os.path.join(FIX, "runtime-record-cases.json"))["cases"]
SQUID_BASE = read_text(os.path.join(FIX, "runtime-squid-stage.conf"))


def apply_patch(record, ops):
    for op in ops:
        node = record
        for key in op["path"][:-1]:
            node = node[key]
        if "set" in op:
            node[op["path"][-1]] = copy.deepcopy(op["set"])
        else:
            del node[op["path"][-1]]


def run_record_probe(case, n):
    d = os.path.join(work, "run-record-%d" % n)
    os.makedirs(d)
    record = copy.deepcopy(RBASE)
    apply_patch(record, case["patch"])
    limits = write_text(os.path.join(d, "limits.json"), json.dumps(record))
    args = ["--limits", limits]
    if case.get("squid"):
        text = SQUID_BASE
        for old, new in case.get("squid_replace", []):
            if old not in text:
                sys.exit("%s: replacement target not in the captured squid.conf" % case["id"])
            text = text.replace(old, new, 1)
        args += ["--squid-conf", write_text(os.path.join(d, "squid.conf"), text)]
    return cli(RR, args)


def run_record_signature(case):
    return json.dumps({"patch": case["patch"], "squid_replace": case.get("squid_replace")}, sort_keys=True)


rr_cases = load(os.path.join(CASES, "run-record-boundary.json"))["cases"]
for n, case in enumerate(rr_cases):
    check_refs(case["id"], case)
    duplicates(case["id"], case, RR_EXISTING, run_record_signature)
    code, out = run_record_probe(case, n)
    judge(case["id"], (code, out["verdict"], out["reasons"]), case["verdict"], case["reasons"])

# 4. Interruption: every truncated (partial, mid-write) input must fail closed.
gate_mod = load_checker("gate_mod", GATE)
evidence_mod = load_checker("evidence_mod", EVIDENCE)
rr_mod = load_checker("rr_mod", RR)
sweeps = {}


def sweep(name, full, check_prefix):
    checked = skipped = passed_equivalent = 0
    for cut in range(len(full)):
        verdict = check_prefix(full[:cut], cut)
        if verdict is None:
            skipped += 1
        elif verdict == "pass-equivalent":
            passed_equivalent += 1
        else:
            checked += 1
    sweeps[name] = (checked, skipped, passed_equivalent)


def write_sweep(name, text):
    return write_text(os.path.join(work, "sweep-%s" % name), text)


# 4a. gate.py check runs, one object per line. A cut inside a line must fail; a cut on a line boundary
# or after a complete record is a complete input of fewer records, and is not checked here (see the results doc).
good_report = os.path.join(work, "sweep-good-report.json")
write_text(good_report, json.dumps({"schema": "aidd-verify-report/v1", "target_sha": T,
                                    "criteria_digest": TRUSTED, "passed": criteria_ids(read_text(CRITERIA_SRC)),
                                    "failed": []}))
runs_full = json.dumps(SELF_RUN) + "\n" + json.dumps(BASE_RUN) + "\n"
code, out = inproc(gate_mod, ["--policy", POLICY, "--target-sha", T, "--check-runs",
                              write_sweep("runs-full", runs_full), "--suite-id", "100",
                              "--report", good_report, "--approved", APPROVED])
if (code, out["verdict"]) != (0, "pass"):
    failures.append("sweep baseline: the complete check runs must pass, got %s" % out)


def gate_runs_prefix(prefix, cut):
    last = prefix.rsplit("\n", 1)[-1]
    if prefix.endswith("\n"):
        return None
    try:
        json.loads(last)
        return None  # the last record is complete: a shorter list of records, not a partial write
    except ValueError:
        pass
    code, out = inproc(gate_mod, ["--policy", POLICY, "--target-sha", T, "--check-runs",
                                  write_sweep("runs-cut", prefix), "--suite-id", "100",
                                  "--report", good_report, "--approved", APPROVED])
    if out["verdict"] != "fail" or not out["reasons"] or \
            not out["reasons"][0].startswith(("invalid-input:", "missing-check:")):
        failures.append("gate check runs cut at %d: %s" % (cut, out))
        return "bad"
    return "fail"


sweep("gate-check-runs", runs_full, gate_runs_prefix)

# 4b. gate.py report: a JSON object cut anywhere is never a report.
report_full = read_text(good_report)


def gate_report_prefix(prefix, cut):
    report_file = write_sweep("report-cut", prefix)
    code, out = inproc(gate_mod, ["--policy", POLICY, "--target-sha", T, "--check-runs",
                                  write_sweep("runs-ok", json.dumps(SELF_RUN) + "\n" + json.dumps(BASE_RUN) + "\n"),
                                  "--suite-id", "100", "--report", report_file, "--approved", APPROVED])
    if (code, out["verdict"], out["reasons"]) != (1, "fail", ["report-invalid"]):
        failures.append("gate report cut at %d: %s" % (cut, out))
        return "bad"
    return "fail"


sweep("gate-report", report_full, gate_report_prefix)

# 4c. verify_evidence.py attestation lists and compare output: a JSON array or object cut anywhere is refused.
att_full = json.dumps([default_entry("provenance")])
compare_full = json.dumps(ON_BRANCH)
art_good = os.path.join(work, "sweep-artifact")
with open(art_good, "wb") as fh:
    fh.write(ARTIFACT_BYTES)
tres_good = write_sweep("tres-good", json.dumps([build("test_result", {})]))
cmp_good = write_sweep("cmp-good", compare_full)
prov_good = write_sweep("prov-good", att_full)


def evidence_args(att_path, cmp_path):
    return ["--policy", EPOL, "--artifact", art_good, "--source-digest", SOURCE, "--source-ref", REF,
            "--now", NOW, "--default-branch-compare", cmp_path, "--attestations", att_path, tres_good]


code, out = inproc(evidence_mod, evidence_args(prov_good, cmp_good))
if (code, out["verdict"]) != (0, "pass"):
    failures.append("sweep baseline: the complete evidence must pass, got %s" % out)


def evidence_att_prefix(prefix, cut):
    code, out = inproc(evidence_mod, evidence_args(write_sweep("att-cut", prefix), cmp_good))
    if out["verdict"] != "fail" or not out["reasons"] or not out["reasons"][0].startswith("invalid-input:"):
        failures.append("evidence attestation cut at %d: %s" % (cut, out))
        return "bad"
    return "fail"


sweep("evidence-attestations", att_full, evidence_att_prefix)


def evidence_cmp_prefix(prefix, cut):
    code, out = inproc(evidence_mod, evidence_args(prov_good, write_sweep("cmp-cut", prefix)))
    if out["verdict"] != "fail" or not out["reasons"] or not out["reasons"][0].startswith("invalid-input:"):
        failures.append("evidence compare cut at %d: %s" % (cut, out))
        return "bad"
    return "fail"


sweep("evidence-compare", compare_full, evidence_cmp_prefix)

# 4d. check_run_record.py: a limits.json cut anywhere is unreadable; a squid.conf cut either fails, or
# keeps exactly the same rules (only blank lines or comments were removed).
limits_full = json.dumps(RBASE)
limits_good = write_sweep("limits-good", limits_full)
code, out = inproc(rr_mod, ["--limits", limits_good])
if (code, out["verdict"]) != (0, "pass"):
    failures.append("sweep baseline: the complete run record must pass, got %s" % out)


def limits_prefix(prefix, cut):
    code, out = inproc(rr_mod, ["--limits", write_sweep("limits-cut", prefix)])
    if (code, out["reasons"]) != (1, ["invalid-input:limits-json-unreadable"]):
        failures.append("limits cut at %d: %s" % (cut, out))
        return "bad"
    return "fail"


sweep("run-record-limits", limits_full, limits_prefix)


def rules_of(text):
    return {line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("#")}


def squid_prefix(prefix, cut):
    code, out = inproc(rr_mod, ["--limits", limits_good, "--squid-conf", write_sweep("squid-cut", prefix)])
    if out["verdict"] == "fail":
        return "fail"
    if rules_of(prefix) == rules_of(SQUID_BASE):
        return "pass-equivalent"
    failures.append("squid.conf cut at %d passed with different rules" % cut)
    return "bad"


code, out = inproc(rr_mod, ["--limits", limits_good, "--squid-conf", write_sweep("squid-full", SQUID_BASE)])
if (code, out["verdict"]) != (0, "pass"):
    failures.append("sweep baseline: the complete squid.conf must pass, got %s" % out)
sweep("run-record-squid", SQUID_BASE, squid_prefix)

if failures:
    sys.exit("\n".join(failures[:50]) + ("\n... %d more" % (len(failures) - 50) if len(failures) > 50 else ""))
for name, (checked, skipped, equivalent) in sorted(sweeps.items()):
    print("truncation %s: %d cuts failed closed, %d cuts skipped (line boundary or complete record), %d cuts kept the same rules"
          % (name, checked, skipped, equivalent))
print("boundary cases: gate %d, evidence %d, run record %d, all ok" % (len(gate_cases), len(evidence_cases), len(rr_cases)))
PY

echo "boundary-suite: ok"
