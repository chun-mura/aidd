#!/usr/bin/env python3
"""Release gate: decide whether the required checks really passed for one commit (AC-PROC-001).

Usage:
  python3 gate.py --policy gate-policy.json --target-sha SHA --check-runs RUNS
                  [--suite-id ID] [--report REPORT] [--approved approved.sha256]

RUNS is the check runs of the target commit, either the REST response of
GET /repos/{owner}/{repo}/commits/{sha}/check-runs or one check run object per line
(the output of `gh api --paginate ... --jq '.check_runs[]'`).
REPORT is the verification report the verify job uploaded; a missing file means no evidence.
APPROVED is the owner-approved digest list read from the protected base, not from the change;
the criteria.md beside it lists the criterion IDs that must all appear in the report as passed.

Prints one JSON object and exits 0 only when every rule passed. Anything else, including
input it cannot read, is a failure (exit 1). Python standard library only.
"""

import argparse
import hashlib
import json
import os
import re
import sys

SHA_RE = re.compile(r"^[0-9a-f]{40}([0-9a-f]{24})?$")
# A criterion row of criteria.md (docs/assurance/acceptance.md): | AT-PAY-01 | origin | ...
CRITERION_RE = re.compile(r"^\| (AT-[A-Z]+-[0-9P]+) \|")
REPORT_SCHEMA = "aidd-verify-report/v1"


class InvalidInput(Exception):
    pass


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def load_check_runs(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if not text.strip():
        return []
    try:
        data = json.loads(text)
    except ValueError:
        # One check run per line; a bad line raises and fails the gate.
        data = [json.loads(line) for line in text.splitlines() if line.strip()]
    if isinstance(data, dict):
        data = data["check_runs"] if "check_runs" in data else [data]
    if not isinstance(data, list) or not all(isinstance(r, dict) for r in data):
        raise InvalidInput("check runs are not a list of objects")
    return data


def run_key(run):
    # GitHub reports the most recent check run of a name. Ids grow with creation time; a queued
    # re-run has no started_at yet, so ordering by start time would let an older success win.
    return (run.get("id") or 0, run.get("started_at") or "")


def judge_check(spec, runs, target_sha, suite_id):
    """Return the reasons the required check `spec` does not count as passed (empty = passed)."""
    name = spec["name"]
    named = [r for r in runs if r.get("name") == name]
    on_target = [r for r in named if r.get("head_sha") == target_sha]
    from_app = [r for r in on_target if (r.get("app") or {}).get("id") == spec["app_id"]]
    if spec.get("same_run"):
        candidates = [r for r in from_app if (r.get("check_suite") or {}).get("id") == suite_id]
    else:
        candidates = from_app
    if not candidates:
        if not named:
            return ["missing-check:%s" % name]
        if not on_target:
            return ["stale-sha:%s" % name]
        if not from_app:
            return ["untrusted-app:%s" % name]
        return ["other-run:%s" % name]
    latest = max(candidates, key=run_key)
    if latest.get("status") != "completed":
        return ["not-completed:%s:%s" % (name, latest.get("status"))]
    if latest.get("conclusion") != "success":
        return ["not-success:%s:%s" % (name, latest.get("conclusion"))]
    return []


def trusted_criteria(approved_path):
    """The approved digest and the criterion IDs of criteria.md next to it, both from the protected base."""
    with open(approved_path, "rb") as fh:
        digest = "sha256:" + hashlib.sha256(fh.read()).hexdigest()
    criteria_path = os.path.join(os.path.dirname(approved_path), "criteria.md")
    with open(criteria_path, encoding="utf-8") as fh:
        ids = {m.group(1) for m in (CRITERION_RE.match(line) for line in fh) if m}
    if not ids:
        raise InvalidInput("no criteria rows in %s" % criteria_path)
    return digest, ids


def judge_report(report_path, target_sha, trusted_digest, criterion_ids):
    try:
        report = load_json(report_path)
    except FileNotFoundError:
        return ["missing-report"]
    except (OSError, ValueError):
        return ["report-invalid"]
    if not isinstance(report, dict) or report.get("schema") != REPORT_SCHEMA:
        return ["report-invalid"]
    passed, failed = report.get("passed"), report.get("failed")
    if not isinstance(passed, list) or not isinstance(failed, list) or not passed:
        return ["report-invalid"]
    reasons = []
    if report.get("target_sha") != target_sha:
        reasons.append("report-sha-mismatch")
    if report.get("criteria_digest") != trusted_digest:
        reasons.append("report-criteria-mismatch")
    if failed:
        reasons.append("report-failed")
    # Every approved criterion must have passed: one passing test is not the acceptance run.
    if not criterion_ids <= set(passed):
        reasons.append("report-incomplete")
    return reasons


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", required=True)
    parser.add_argument("--target-sha", required=True)
    parser.add_argument("--check-runs", required=True)
    parser.add_argument("--suite-id", type=int)
    parser.add_argument("--report")
    parser.add_argument("--approved")
    args = parser.parse_args(argv)

    result = {"verdict": "fail", "target_sha": args.target_sha, "reasons": []}
    try:
        if not SHA_RE.match(args.target_sha):
            raise InvalidInput("target sha is not a full commit SHA")
        policy = load_json(args.policy)
        required = policy.get("required_checks")
        if not isinstance(required, list) or not required:
            raise InvalidInput("policy has no required_checks")
        for spec in required:
            if not isinstance(spec.get("name"), str) or not isinstance(spec.get("app_id"), int):
                raise InvalidInput("required check needs a name and an integer app_id")
            if spec.get("same_run") and args.suite_id is None:
                raise InvalidInput("%s needs --suite-id" % spec["name"])
        runs = load_check_runs(args.check_runs)
        reasons = []
        for spec in required:
            reasons += judge_check(spec, runs, args.target_sha, args.suite_id)
        if policy.get("require_report", True):
            if not args.report or not args.approved:
                raise InvalidInput("the policy requires --report and --approved")
            digest, criterion_ids = trusted_criteria(args.approved)
            reasons += judge_report(args.report, args.target_sha, digest, criterion_ids)
        result["reasons"] = reasons
        result["verdict"] = "pass" if not reasons else "fail"
    except (InvalidInput, OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        result["reasons"] = ["invalid-input:%s" % exc]
    print(json.dumps(result, sort_keys=True))
    return 0 if result["verdict"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
