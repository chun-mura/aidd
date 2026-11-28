#!/usr/bin/env python3
"""Check a run record bundle without starting the runner (AC-PROC-003, AC-PRIV-001..005).

Inputs are files that a run leaves behind: limits.json (the effective HostConfig of each
stage plus the teardown leftover counts) and, optionally, the squid.conf of a stage. Nothing
is started and nothing is read from Docker. The check is stdlib only.

Prints one line of JSON, {"verdict": "pass" | "fail", "reasons": [...]}, and exits 0 on pass
and 1 on fail. An input that cannot be read or parsed fails closed with an invalid-input
reason. A usage error (argparse) exits 2 and prints no verdict.
"""
import argparse
import json
import re
import sys

SUPPORTED_SCHEMA = 1
STAGES = ("seed", "deps", "agent", "ingest", "publish")
NO_NETWORK_STAGES = ("seed", "ingest")
AGENT_CAPABILITIES = {"SETUID", "SETGID"}
PRIVATE_RANGES = ("10.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16", "192.168.0.0/16", "172.16.0.0/12")
TMPFS_SIZE_RE = re.compile(r"[1-9][0-9]*[kKmMgG]?")


def is_positive_int(value):
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def tmpfs_is_sized(options):
    if not isinstance(options, str):
        return False
    for part in options.split(","):
        if part.startswith("size="):
            return TMPFS_SIZE_RE.fullmatch(part[len("size="):]) is not None
    return False


def contains_key(value, key):
    if isinstance(value, dict):
        return key in value or any(contains_key(v, key) for v in value.values())
    if isinstance(value, list):
        return any(contains_key(v, key) for v in value)
    return False


def check_stage(name, stage, reasons):
    if not isinstance(stage, dict) or not isinstance(stage.get("host_config"), dict):
        reasons.append("invalid-input:host-config:%s" % name)
        return
    host = stage["host_config"]
    if contains_key(stage, "Env") or contains_key(stage, "Config"):
        reasons.append("env-recorded:%s" % name)
    if host.get("ReadonlyRootfs") is not True:
        reasons.append("rootfs-writable:%s" % name)
    if host.get("CapDrop") != ["ALL"]:
        reasons.append("cap-drop-not-all:%s" % name)
    security = host.get("SecurityOpt") or []
    if not any(opt in ("no-new-privileges", "no-new-privileges:true") for opt in security):
        reasons.append("no-new-privileges-missing:%s" % name)
    memory = host.get("Memory")
    if not is_positive_int(memory) or host.get("MemorySwap") != memory:
        reasons.append("memory-unbounded:%s" % name)
    if not is_positive_int(host.get("NanoCpus")):
        reasons.append("cpu-unbounded:%s" % name)
    if not is_positive_int(host.get("PidsLimit")):
        reasons.append("pids-unbounded:%s" % name)
    tmpfs = host.get("Tmpfs") or {}
    if not isinstance(tmpfs, dict) or not all(tmpfs_is_sized(opts) for opts in tmpfs.values()):
        reasons.append("tmpfs-unsized:%s" % name)
    mode = host.get("NetworkMode")
    if name in NO_NETWORK_STAGES:
        if mode != "none":
            reasons.append("network-not-none:%s" % name)
    elif mode in (None, "", "host", "bridge", "default"):
        reasons.append("network-not-isolated:%s" % name)
    allowed = AGENT_CAPABILITIES if name == "agent" else set()
    for capability in host.get("CapAdd") or []:
        if capability not in allowed:
            reasons.append("capability-added:%s:%s" % (name, capability))


def check_limits(record, reasons):
    if not isinstance(record, dict):
        reasons.append("invalid-input:limits-not-object")
        return
    if record.get("schema_version") != SUPPORTED_SCHEMA:
        reasons.append("schema-version-unsupported")
    stages = record.get("stages")
    if not isinstance(stages, dict) or not stages:
        reasons.append("invalid-input:stages-missing")
    else:
        for name in sorted(stages):
            if name not in STAGES:
                reasons.append("stage-unknown:%s" % name)
            else:
                check_stage(name, stages[name], reasons)
    teardown = record.get("teardown")
    if not isinstance(teardown, dict):
        reasons.append("teardown-not-recorded")
        return
    for kind in ("containers", "volumes", "networks"):
        count = teardown.get(kind)
        if not isinstance(count, int) or isinstance(count, bool):
            reasons.append("teardown-count-invalid:%s" % kind)
        elif count != 0:
            reasons.append("leftover:%s" % kind)


def first_index(lines, predicate):
    for index, line in enumerate(lines):
        if predicate(line):
            return index
    return None


def check_squid(text, reasons):
    lines = []
    for raw in text.splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            lines.append(line)
    exact = set(lines)
    if "acl CONNECT method CONNECT" not in exact:
        reasons.append("squid:connect-acl-missing")
    if "acl SSL_ports port 443" not in exact:
        reasons.append("squid:port-not-443")
    for line in lines:
        if re.match(r"acl \S+ dstdomain\b", line) and "-n" not in line.split():
            reasons.append("squid:dstdomain-not-anchored")
            break
    allows = [i for i, line in enumerate(lines) if line.startswith("http_access allow")]
    if not allows:
        reasons.append("squid:no-allow")
    if any(lines[i] != "http_access allow allowed_dst" for i in allows):
        reasons.append("squid:unscoped-allow")
    first_allow = allows[0] if allows else len(lines)
    required_denies = [
        ("http_access deny !CONNECT", "squid:non-connect-not-denied"),
        ("http_access deny !SSL_ports", "squid:port-not-denied"),
        ("http_access deny ip_literal_host", "squid:ip-literal-not-denied-before-allow"),
        ("http_access deny private_dst", "squid:private-dst-not-denied-before-allow"),
    ]
    for line, reason in required_denies:
        index = first_index(lines, lambda candidate: candidate == line)
        if index is None or index > first_allow:
            reasons.append(reason)
    private = " ".join(line for line in lines if line.startswith("acl private_dst dst "))
    if any(item not in private.split() for item in PRIVATE_RANGES):
        reasons.append("squid:private-ranges-incomplete")
    http_access = [line for line in lines if line.startswith("http_access ")]
    if not http_access or http_access[-1] != "http_access deny all":
        reasons.append("squid:default-not-deny")
    for line in ("via off", "forwarded_for delete"):
        if line not in exact:
            reasons.append("squid:proxy-headers-not-stripped")


def load_json(path, reasons, label):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        reasons.append("invalid-input:%s" % label)
        return None


def main(argv=None):
    parser = argparse.ArgumentParser(description="Check a runtime run record bundle.")
    parser.add_argument("--limits", required=True, help="path to limits.json")
    parser.add_argument("--squid-conf", help="path to a stage squid.conf (optional)")
    args = parser.parse_args(argv)

    reasons = []
    record = load_json(args.limits, reasons, "limits-json-unreadable")
    if record is not None:
        check_limits(record, reasons)
    if args.squid_conf is not None:
        try:
            with open(args.squid_conf, encoding="utf-8") as handle:
                text = handle.read()
        except (OSError, UnicodeDecodeError):
            reasons.append("invalid-input:squid-conf-unreadable")
        else:
            check_squid(text, reasons)

    verdict = "fail" if reasons else "pass"
    print(json.dumps({"verdict": verdict, "reasons": reasons}, separators=(",", ":")))
    return 0 if verdict == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
