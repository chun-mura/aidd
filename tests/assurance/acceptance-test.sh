#!/bin/bash
# Checks the acceptance example (#155): criteria tell the correct implementation from the wrong ones.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
example="$repo_root/examples/assurance/acceptance"
work=$(mktemp -d "${TMPDIR:-/tmp}/aidd-acceptance.XXXXXX")
trap 'rm -rf "$work"' EXIT
export PYTHONDONTWRITEBYTECODE=1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Runs the acceptance tests in $1 against implementation $2; prints the sorted failed IDs, one per line.
failed_ids() {
  local status=0 out ids
  out=$(cd "$1" && python3 -B acceptance_test.py --impl "$2" --json) || status=$?
  [ "$status" -le 1 ] || fail "acceptance_test.py crashed for $2 (exit $status)"
  ids=$(python3 -c 'import json, sys; print("\n".join(json.loads(sys.argv[1])["failed"]))' "$out")
  # The exit code must agree with the report: 0 exactly when nothing failed.
  if { [ "$status" -eq 0 ] && [ -n "$ids" ]; } || { [ "$status" -eq 1 ] && [ -z "$ids" ]; }; then
    fail "exit $status does not match the failed criteria [$ids] for $2"
  fi
  [ -z "$ids" ] || printf '%s\n' "$ids"
}

# Verifies $1/approved.sha256: the owner-approved files, unchanged, and no more or fewer of them.
check_approved() {
  python3 - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
expected = {"requirements.md", "criteria.md", "api.py", "acceptance_test.py"}
seen = set()
with open(os.path.join(root, "approved.sha256"), encoding="utf-8") as fh:
    for line in fh:
        digest, name = line.rstrip("\n").split("  ", 1)
        with open(os.path.join(root, name), "rb") as f:
            actual = hashlib.sha256(f.read()).hexdigest()
        if actual != digest:
            sys.exit("approved digest mismatch: %s" % name)
        seen.add(name)
if seen != expected:
    sys.exit("approved.sha256 covers %s, expected %s" % (sorted(seen), sorted(expected)))
PY
}

# 1. The approved criteria are the ones in the repository, and a change to them is detected.
check_approved "$example" || fail "approved.sha256 does not match the criteria files"
cp -R "$example" "$work/tampered"
printf '\n| AT-X-99 | R-1 | 例 | added without approval | - |\n' >>"$work/tampered/criteria.md"
if check_approved "$work/tampered" 2>/dev/null; then
  fail "a changed criteria.md passed the approved digest check"
fi

# 2. Independence: the criteria side imports nothing from an implementation.
if grep -En '^[[:space:]]*(from|import)[[:space:]]+impl_' "$example/acceptance_test.py" "$example/api.py"; then
  fail "the acceptance tests or api.py import an implementation"
fi

# 3. Traceability: criteria.md rows == test functions, and every origin ID exists in requirements.md.
python3 - "$example" <<'PY' || fail "traceability check"
import os, re, subprocess, sys
root = sys.argv[1]
def rows(name, pattern):
    with open(os.path.join(root, name), encoding="utf-8") as fh:
        return [m.groups() for m in (re.match(pattern, line) for line in fh) if m]
criteria = rows("criteria.md", r"^\| (AT-[A-Z]+-[0-9P]+) \| ([^|]+) \|")
requirement_ids = {r[0] for r in rows("requirements.md", r"^\| ([RDX]-[0-9]+) \|")}
tests = subprocess.run([sys.executable, "-B", "acceptance_test.py", "--list"], cwd=root,
                       check=True, capture_output=True, text=True).stdout.split()
ids = [c[0] for c in criteria]
if len(ids) != len(set(ids)) or sorted(ids) != sorted(tests):
    sys.exit("criteria %s != tests %s" % (sorted(ids), sorted(tests)))
covered = set()
for cid, origin in criteria:
    for ref in [x.strip() for x in origin.split(",")]:
        if ref not in requirement_ids or ref.startswith("X-"):
            sys.exit("%s cites %r, not a requirement or owner decision" % (cid, ref))
        covered.add(ref)
missing = sorted(r for r in requirement_ids if not r.startswith("X-") and r not in covered)
if missing:
    sys.exit("requirements without a criterion: %s" % missing)
PY

# 4. The correct implementation passes every criterion.
got=$(failed_ids "$example" impl_correct:make_service)
[ -z "$got" ] || fail "impl_correct failed: $got"

# 5. Each wrong implementation fails exactly the criteria its defect breaks.
expect_failed() {
  local impl=$1 want got
  want=$(printf '%s\n' "${@:2}" | sort)
  got=$(failed_ids "$example" "$impl" | sort)
  [ "$got" = "$want" ] || fail "$impl failed [${got//$'\n'/ }], expected [${want//$'\n'/ }]"
}
expect_failed impl_broken:make_cross_tenant AT-AUTHZ-01 AT-AUTHZ-03 AT-AUTHZ-05 AT-AUTHZ-P
expect_failed impl_broken:make_double_pay AT-PAY-01 AT-PAY-02 AT-PAY-03 AT-PAY-P

# 6. No bytecode was left behind in the example directory.
if find "$example" -name '__pycache__' | grep -q .; then
  fail "__pycache__ written into examples/"
fi

echo "acceptance-test: ok"
