#!/usr/bin/env python3
"""Distribution-side evidence check (AC-PROC-002): decide whether an artifact may be distributed.

Run it after `gh attestation verify` has checked the signatures, certificates and transparency
log entries, on that command's `--format json` output (one file per predicate type):

  python3 verify_evidence.py --policy policy.json --artifact dist/app.tar.gz \
      --source-digest <release commit> --source-ref refs/tags/v1.2.3 \
      --default-branch-compare compare.json \
      --attestations provenance.json test-result.json [--now 2026-11-28T00:00:00Z]

gh checks each attestation on its own. This script checks what binds them together: the artifact
on disk is the subject of both, both come from the same workflow run of the pinned signer commit,
the source and ref are the release's and the commit is on the default branch, the tests passed on
the owner-approved criteria, the evidence is recent, and nothing beyond test IDs and digests was
stored. It does not verify signatures,
so never run it on attestations that gh has not verified.

Prints one JSON object and exits 0 only when some workflow run's attestations pass every rule.
Anything else, including input it cannot read, is a failure (exit 1). Python standard library only.
"""

import argparse
import datetime
import hashlib
import json
import re
import sys

TEST_RESULT_KEYS = {"result", "configuration", "url", "passedTests", "warnedTests", "failedTests"}


class InvalidInput(Exception):
    pass


def parse_time(value):
    if not isinstance(value, str):
        raise InvalidInput("timestamp is not a string")
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


def load_entries(paths):
    entries = []
    for path in paths:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, list):
            raise InvalidInput("%s is not the list gh attestation verify --format json prints" % path)
        for item in data:
            result = item["verificationResult"]
            entries.append({
                "statement": result["statement"],
                "cert": result["signature"]["certificate"],
                "times": [parse_time(t["timestamp"]) for t in result.get("verifiedTimestamps") or []],
            })
    return entries


def judge_group(entries, policy, artifact_digest, source_digest, source_ref, now):
    reasons = set()
    by_label = {}
    wanted = {v: k for k, v in policy["required_predicates"].items()}
    for entry in entries:
        label = wanted.get(entry["statement"].get("predicateType"))
        if label:
            by_label.setdefault(label, []).append(entry)
    for label in policy["required_predicates"]:
        if label not in by_label:
            reasons.add("missing-attestation:%s" % label)
    signer = "https://github.com/%s@" % policy["signer_workflow"]
    source_uri = "https://github.com/%s" % policy["source_repository"]
    max_age = datetime.timedelta(days=policy["max_age_days"])
    for label, group in by_label.items():
        for entry in group:
            cert, statement = entry["cert"], entry["statement"]
            subjects = {(s.get("digest") or {}).get("sha256") for s in statement.get("subject") or []}
            if artifact_digest not in subjects:
                reasons.add("digest-mismatch:%s" % label)
            if cert.get("issuer") != policy["oidc_issuer"]:
                reasons.add("issuer-mismatch")
            # The path alone is not enough: any ref of the policy repository (an unreviewed branch)
            # has the same path. The digest pins the approved commit of the signing workflow.
            if not str(cert.get("buildSignerURI", "")).startswith(signer) or \
                    cert.get("buildSignerDigest") != policy["signer_digest"]:
                reasons.add("signer-mismatch")
            if cert.get("runnerEnvironment") != policy["runner_environment"]:
                reasons.add("environment-mismatch")
            if cert.get("sourceRepositoryURI") != source_uri or cert.get("sourceRepositoryDigest") != source_digest:
                reasons.add("source-mismatch")
            ref = cert.get("sourceRepositoryRef")
            if ref != source_ref or not re.fullmatch(policy["source_ref_pattern"], ref or ""):
                reasons.add("ref-mismatch")
            if not entry["times"]:
                reasons.add("missing-timestamp")
            elif now - min(entry["times"]) > max_age or max(entry["times"]) > now:
                reasons.add("stale-evidence")
    for entry in by_label.get("test-result", []):
        reasons.update(judge_test_result(entry["statement"].get("predicate"), policy, artifact_digest))
    return sorted(reasons)


def judge_test_result(predicate, policy, artifact_digest):
    if not isinstance(predicate, dict) or set(predicate) - TEST_RESULT_KEYS:
        return ["unexpected-content"]
    reasons = []
    test_id = re.compile(policy["test_id_pattern"])
    names = [n for key in ("passedTests", "warnedTests", "failedTests") for n in predicate.get(key) or []]
    run_url = r"https://github\.com/%s/actions/runs/[0-9]+" % re.escape(policy["source_repository"])
    config_names = sorted(str(c.get("name")) for c in predicate.get("configuration") or [])
    if (not all(isinstance(n, str) and test_id.fullmatch(n) for n in names)
            or not re.fullmatch(run_url, str(predicate.get("url")))
            or config_names != sorted([policy["subject_name"], "approved.sha256"])):
        reasons.append("unexpected-content")
    if predicate.get("result") != "PASSED" or predicate.get("failedTests") or not predicate.get("passedTests"):
        reasons.append("tests-not-passed")
    config = {(c.get("digest") or {}).get("sha256") for c in predicate.get("configuration") or []}
    if policy["criteria_digest"].split(":", 1)[1] not in config or artifact_digest not in config:
        reasons.append("input-mismatch")
    return reasons


def judge_default_branch(compare_path, source_digest):
    """The release commit must already be on the protected default branch (merged through the gate).

    compare_path is `gh api repos/<owner>/<repo>/compare/<default branch>...<source digest>`: the
    commit is on the branch exactly when it is its own merge base with the branch tip.
    """
    with open(compare_path, encoding="utf-8") as fh:
        compare = json.load(fh)
    on_branch = compare["status"] in ("behind", "identical") and \
        compare["merge_base_commit"]["sha"] == source_digest
    return [] if on_branch else ["not-on-default-branch"]


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", required=True)
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--source-digest", required=True)
    parser.add_argument("--source-ref", required=True)
    parser.add_argument("--default-branch-compare", required=True)
    parser.add_argument("--attestations", nargs="+", required=True)
    parser.add_argument("--now")
    args = parser.parse_args(argv)

    result = {"verdict": "fail", "reasons": []}
    try:
        with open(args.policy, encoding="utf-8") as fh:
            policy = json.load(fh)
        if policy.get("schema") != "aidd-evidence-policy/v1":
            raise InvalidInput("unknown policy schema")
        if not re.fullmatch(r"[0-9a-f]{40}", args.source_digest):
            raise InvalidInput("source digest is not a full commit SHA")
        now = parse_time(args.now) if args.now else datetime.datetime.now(datetime.timezone.utc)
        with open(args.artifact, "rb") as fh:
            artifact_digest = hashlib.sha256(fh.read()).hexdigest()
        result["artifact_digest"] = "sha256:" + artifact_digest
        branch_reasons = judge_default_branch(args.default_branch_compare, args.source_digest)
        entries = load_entries(args.attestations)
        groups = {}
        for entry in entries:
            groups.setdefault(entry["cert"].get("runInvocationURI"), []).append(entry)
        if not groups:
            groups = {None: []}
        verdicts = []
        for run, group in groups.items():
            latest = max((t for e in group for t in e["times"]), default=None)
            reasons = judge_group(group, policy, artifact_digest, args.source_digest, args.source_ref, now)
            reasons = sorted(set(reasons) | set(branch_reasons))
            if run is None and group:
                reasons = sorted(set(reasons) | {"missing-run"})
            verdicts.append((latest or datetime.datetime.min.replace(tzinfo=datetime.timezone.utc), run, reasons))
        passing = [v for v in verdicts if not v[2]]
        if passing:
            result.update(verdict="pass", run=passing[-1][1])
        else:
            # Report the newest run: provenance and test results from different runs never combine,
            # so a fresh provenance next to an old test result fails both runs (missing-attestation).
            _, run, reasons = max(verdicts, key=lambda v: (v[0], str(v[1])))
            result.update(run=run, reasons=reasons)
    except (InvalidInput, OSError, ValueError, KeyError, TypeError, AttributeError, re.error) as exc:
        result["reasons"] = ["invalid-input:%s" % exc]
    print(json.dumps(result, sort_keys=True))
    return 0 if result["verdict"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
