#!/usr/bin/env bash
# Manual test for examples/assurance/formal: TLC finds the defect, passes the correct model, and replays implementation traces.
#
# Needs network on the first run (to fetch the pinned tla2tools.jar) and Java or
# Docker. Not part of CI: see docs/assurance/formal-methods.md "手動で実行する".
set -uo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
src="$repo/examples/assurance/formal"
run_tlc="$src/run-tlc.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/aidd-formal-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# Run TLC on a fresh copy of the specs; the output goes to $work/<name>.out.
# The exit code is TLC's.
tlc() {
  local name=$1 module=$2 config=$3
  local dir="$work/$name"
  mkdir -p "$dir"
  cp "$src"/*.tla "$src"/*.cfg "$dir"/
  if [ -n "${4:-}" ]; then cp "$4" "$dir/TraceData.tla"; fi
  bash "$run_tlc" "$dir" "$module" "$config" >"$work/$name.out" 2>&1
}

expect() {  # expect <name> <expected exit> <expected output line pattern>
  local name=$1 want=$2 pattern=$3 got=$4
  if [ "$got" -eq "$want" ] && grep -Eq "$pattern" "$work/$name.out"; then
    pass "$name (exit $got)"
  else
    fail "$name: exit $got (want $want), pattern '$pattern'"
    tail -n 30 "$work/$name.out"
  fi
}

# 1. The defective model has a counterexample: revoke between Check and Publish.
tlc defect Publish.tla PublishDefect.cfg; rc=$?
expect defect 12 '^Error: Invariant SafePublish is violated' "$rc"
if grep -q '<Revoke ' "$work/defect.out" && grep -q '<Publish ' "$work/defect.out"; then
  pass "defect counterexample revokes before publishing"
else
  fail "defect counterexample does not show Revoke then Publish"
fi

# 2. The correct model satisfies SafePublish in every reachable state of the instance.
tlc correct Publish.tla Publish.cfg; rc=$?
expect correct 0 '^Model checking completed\. No error has been found\.' "$rc"
grep -E '^[0-9]+ states generated, [0-9]+ distinct states found, 0 states left on queue' \
  "$work/correct.out" || fail "correct: state count line missing"

# 3. Traces of the implementation are behaviors of the correct model.
gen() { python3 -I "$src/impl/publish_service.py" "$@"; }
for seed in 1 2 3 4 5; do
  gen random --seed "$seed" --steps 60 --out "$work" >/dev/null
  tlc "trace-$seed" TraceCheck.tla TraceCheck.cfg "$work/TraceData.tla"; rc=$?
  expect "trace-$seed" 0 '^Model checking completed\. No error has been found\.' "$rc"
done
gen race --out "$work" >/dev/null
tlc trace-race TraceCheck.tla TraceCheck.cfg "$work/TraceData.tla"; rc=$?
expect trace-race 0 '^Model checking completed\. No error has been found\.' "$rc"

# 4. The implementation with the defect does not match the correct model: the trace check rejects it.
gen race --defect no-recheck --out "$work" >/dev/null
tlc trace-defect TraceCheck.tla TraceCheck.cfg "$work/TraceData.tla"; rc=$?
expect trace-defect 11 '^Error: Deadlock reached\.' "$rc"
if grep -q '/\\ i = 5$' "$work/trace-defect.out"; then
  pass "trace-defect stops at the publish step (4 of 5 operations matched)"
else
  fail "trace-defect did not stop after the 4th operation"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "formal-test: all checks passed"
  exit 0
fi
echo "formal-test: $failures check(s) failed"
exit 1
