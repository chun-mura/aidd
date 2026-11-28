#!/bin/bash
# Checks the run record checker (#151, #153): verdicts and reason codes on fixtures, squid rules on the real generator's output, fail-closed inputs.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/aidd-runtime-record.XXXXXX")
trap 'rm -rf "$work"' EXIT
export PYTHONDONTWRITEBYTECODE=1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# 1. Every fixture case: the exit code, the verdict and the exact reasons. Squid cases patch a captured stage squid.conf.
python3 -B - "$repo_root" "$work" <<'PY' || fail "run record fixtures"
import copy, json, os, subprocess, sys
root, work = sys.argv[1], sys.argv[2]
checker = os.path.join(root, "examples/assurance/runtime/check_run_record.py")
with open(os.path.join(root, "tests/assurance/fixtures/runtime-record-cases.json"), encoding="utf-8") as fh:
    spec = json.load(fh)
ids = [c["id"] for c in spec["cases"]]
assert len(ids) == len(set(ids)), "duplicate case ids"

with open(os.path.join(root, "tests/assurance/fixtures/runtime-squid-stage.conf"), encoding="utf-8") as fh:
    squid_base = fh.read()
assert "http_access deny all" in squid_base, "the captured squid.conf has the expected default-deny line"

def apply_patch(record, ops):
    for op in ops:
        node = record
        for key in op["path"][:-1]:
            node = node[key]
        if "set" in op:
            node[op["path"][-1]] = copy.deepcopy(op["set"])
        else:
            del node[op["path"][-1]]

def run_checker(limits_path, squid_path=None):
    cmd = [sys.executable, "-I", "-B", checker, "--limits", limits_path]
    if squid_path is not None:
        cmd += ["--squid-conf", squid_path]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.returncode, json.loads(proc.stdout)

for n, case in enumerate(spec["cases"]):
    record = copy.deepcopy(spec["base"])
    apply_patch(record, case["patch"])
    limits_path = os.path.join(work, "limits-%d.json" % n)
    with open(limits_path, "w", encoding="utf-8") as fh:
        json.dump(record, fh)
    squid_path = None
    if case["squid"]:
        text = squid_base
        for old, new in case.get("squid_replace", []):
            if old not in text:
                sys.exit("%s: replacement target not in the generator output: %r" % (case["id"], old))
            text = text.replace(old, new, 1)
        squid_path = os.path.join(work, "squid-%d.conf" % n)
        with open(squid_path, "w", encoding="utf-8") as fh:
            fh.write(text)
    code, out = run_checker(limits_path, squid_path)
    want_code = 0 if case["verdict"] == "pass" else 1
    if (code, out["verdict"], sorted(out["reasons"])) != (want_code, case["verdict"], sorted(case["reasons"])):
        sys.exit("%s: got exit %d %s %s, want exit %d %s %s" % (
            case["id"], code, out["verdict"], sorted(out["reasons"]),
            want_code, case["verdict"], sorted(case["reasons"])))
print("run record fixtures: %d cases ok" % len(spec["cases"]))
PY

# 2. Fail closed on inputs the checker cannot read or parse. Usage errors exit 2 and print no verdict.
checker="$repo_root/examples/assurance/runtime/check_run_record.py"
good="$work/good.json"
python3 -B -c 'import json,sys; json.dump(json.load(open(sys.argv[1]))["base"], open(sys.argv[2],"w"))' \
  "$repo_root/tests/assurance/fixtures/runtime-record-cases.json" "$good"

expect_fail() {
  local label=$1 reason=$2
  shift 2
  local out code=0
  out=$(python3 -I -B "$checker" "$@" 2>/dev/null) || code=$?
  [ "$code" -eq 1 ] || fail "$label: want exit 1, got $code"
  case "$out" in
    *"\"$reason\""*) ;;
    *) fail "$label: want reason $reason, got $out" ;;
  esac
}

printf 'not json' > "$work/broken.json"
printf '[1, 2]' > "$work/list.json"
expect_fail "missing limits file" "invalid-input:limits-json-unreadable" --limits "$work/missing.json"
expect_fail "broken JSON" "invalid-input:limits-json-unreadable" --limits "$work/broken.json"
expect_fail "JSON that is not an object" "invalid-input:limits-not-object" --limits "$work/list.json"
expect_fail "missing squid.conf" "invalid-input:squid-conf-unreadable" --limits "$good" --squid-conf "$work/missing.conf"

set +e
python3 -I -B "$checker" >/dev/null 2>&1
usage_code=$?
set -e
[ "$usage_code" -eq 2 ] || fail "missing --limits should be a usage error (exit 2), got $usage_code"

if find "$repo_root/examples/assurance/runtime" "$repo_root/tests/assurance" -name '__pycache__' | grep -q .; then
  fail "__pycache__ written into the repository"
fi

echo "runtime-record-test: ok"
