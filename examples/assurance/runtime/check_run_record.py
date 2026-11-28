#!/usr/bin/env python3
"""Check a run record bundle without starting the runner (AC-PROC-003, AC-PRIV-001..005).

Inputs are files that a run leaves behind: limits.json (the effective HostConfig of each
stage plus the teardown leftover counts) and, optionally, the squid.conf of a stage. Nothing
is started and nothing is read from Docker. The check is stdlib only.

Prints one line of JSON, {"verdict": "pass" | "fail", "reasons": [...], "info": [...]}, and exits
0 on pass and 1 on fail. "reasons" decide the verdict. "info" is informational only: a stage that
timed out, was OOM-killed or exited non-zero, reported with the teardown state. It never changes
the verdict. An input that cannot be read or parsed fails closed with an invalid-input reason.
A usage error (argparse) exits 2 and prints no verdict.
"""
import argparse
import json
import re
import sys

SUPPORTED_SCHEMA = 1
STAGES = ("seed", "deps", "agent", "ingest", "publish")
NO_NETWORK_STAGES = ("seed", "ingest")
AGENT_CAPABILITIES = {"SETUID", "SETGID"}
OUTCOMES = ("succeeded", "blocked", "failed")
INCOMPLETE_OUTCOMES = ("blocked", "failed")
TMPFS_SIZE_RE = re.compile(r"[1-9][0-9]*[kKmMgG]?")
MEMORY_RE = re.compile(r"([1-9][0-9]*)([bBkKmMgG]?)")
MEMORY_UNITS = {"": 1, "b": 1, "k": 1024, "m": 1024 ** 2, "g": 1024 ** 3}
MIB = 1024 ** 2
NANO_PER_CPU = 1000000000
ALLOWED_HOST_RE = re.compile(r"\.([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}")

# The squid ACL definitions that aidd-autopilot image/proxy/generate-squid-conf.sh emits, exactly.
# Only allowed_dst varies with the configured domains, so it is checked by pattern, not by value.
SQUID_FIXED_ACLS = {
    "SSL_ports": ["acl SSL_ports port 443"],
    "CONNECT": ["acl CONNECT method CONNECT"],
    "manager": ["acl manager proto cache_object"],
    "connect_authority": [r"acl connect_authority url_regex -i ^[a-z0-9.-]+:443$"],
    "ip_literal_host": [r"acl ip_literal_host url_regex -i (^|\.)(0x[0-9a-f]*|[0-9]+)\.?:443$"],
    "private_dst": [
        "acl private_dst dst 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8",
        "acl private_dst dst 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16",
        "acl private_dst dst 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4",
        "acl private_dst dst ::/128 ::1/128 ::ffff:0:0/96 fc00::/7 fe80::/10",
    ],
}


def is_positive_int(value):
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def tmpfs_is_sized(options):
    if not isinstance(options, str):
        return False
    for part in options.split(","):
        if part.startswith("size="):
            return TMPFS_SIZE_RE.fullmatch(part[len("size="):]) is not None
    return False


def parse_memory(value):
    """Docker memory size (binary units) in bytes, or None when the value is not a size."""
    if not isinstance(value, str):
        return None
    match = MEMORY_RE.fullmatch(value)
    if match is None:
        return None
    return int(match.group(1)) * MEMORY_UNITS[match.group(2).lower()]


def parse_tmpfs(options):
    """Splits a tmpfs option string into (bare flags, key=value pairs), independent of order."""
    flags, values = set(), {}
    for part in options.split(","):
        if "=" in part:
            key, _, value = part.partition("=")
            values[key] = value
        else:
            flags.add(part)
    return flags, values


def effective_values(record, reasons):
    """The effective limits as the values HostConfig must carry, or None (reason recorded)."""
    effective = record.get("effective")
    derived = None
    if isinstance(effective, dict):
        cpus = effective.get("cpus")
        memory = parse_memory(effective.get("memory"))
        tmp = effective.get("tmp_size")
        artifact = effective.get("max_artifact_bytes")
        bundle = effective.get("max_bundle_bytes")
        if (
            isinstance(cpus, (int, float)) and not isinstance(cpus, bool) and cpus > 0
            and memory is not None
            and is_positive_int(effective.get("pids_limit"))
            and isinstance(tmp, str) and TMPFS_SIZE_RE.fullmatch(tmp) is not None
            and is_positive_int(artifact) and is_positive_int(bundle)
        ):
            derived = {
                "nano_cpus": round(cpus * NANO_PER_CPU),
                "memory": memory,
                "pids": effective["pids_limit"],
                "tmp_size": tmp,
                "artifact": artifact,
                "bundle": bundle,
            }
    if derived is None:
        reasons.append("invalid-input:effective")
    return derived


def expected_tmpfs(stage, eff):
    """Per stage, the tmpfs mounts staged-runner.ts creates: path -> (flags, key=value pairs)."""
    tmp = eff["tmp_size"]
    expected = {
        "/tmp": ({"rw", "noexec", "nosuid", "nodev"}, {"size": tmp}),
    }
    if stage in ("seed", "deps", "agent"):
        expected["/home/workflow"] = (
            {"rw", "nosuid", "nodev"}, {"size": tmp, "uid": "10001", "gid": "10001", "mode": "0700"},
        )
    if stage == "agent":
        expected["/claude-config"] = (
            {"rw", "nosuid", "nodev"}, {"size": tmp, "uid": "0", "gid": "10001", "mode": "2770"},
        )
    if stage == "ingest":
        scratch_mib = -(-(2 * eff["bundle"] + eff["artifact"]) // MIB)
        expected["/scratch"] = ({"rw", "noexec", "nosuid", "nodev"}, {"size": "%dm" % scratch_mib})
    if stage == "publish":
        expected["/home/coordinator"] = (
            {"rw", "nosuid", "nodev"}, {"size": tmp, "uid": "10000", "gid": "10000", "mode": "0700"},
        )
    return expected


def check_tmpfs(name, tmpfs, eff, reasons):
    expected = expected_tmpfs(name, eff)
    for path in sorted(expected):
        if path not in tmpfs:
            reasons.append("tmpfs-missing:%s:%s" % (name, path))
            continue
        if not tmpfs_is_sized(tmpfs[path]):
            continue  # already reported as tmpfs-unsized
        flags, values = parse_tmpfs(tmpfs[path])
        want_flags, want_values = expected[path]
        if flags != want_flags or values != want_values:
            reasons.append("tmpfs-mismatch:%s:%s" % (name, path))
    for path in sorted(set(tmpfs) - set(expected)):
        reasons.append("tmpfs-unexpected:%s:%s" % (name, path))


def contains_key(value, key):
    if isinstance(value, dict):
        return key in value or any(contains_key(v, key) for v in value.values())
    if isinstance(value, list):
        return any(contains_key(v, key) for v in value)
    return False


def check_stage(name, stage, eff, reasons):
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
    if host.get("Privileged") not in (None, False):
        reasons.append("privileged:%s" % name)
    for key in ("PidMode", "IpcMode", "UsernsMode"):
        value = host.get(key)
        if isinstance(value, str) and value.strip().lower() == "host":
            reasons.append("host-namespace:%s:%s" % (name, key))
    memory = host.get("Memory")
    if not is_positive_int(memory) or host.get("MemorySwap") != memory:
        reasons.append("memory-unbounded:%s" % name)
    elif eff is not None and memory != eff["memory"]:
        reasons.append("limits-mismatch:%s:memory" % name)
    nano_cpus = host.get("NanoCpus")
    if not is_positive_int(nano_cpus):
        reasons.append("cpu-unbounded:%s" % name)
    elif eff is not None and nano_cpus != eff["nano_cpus"]:
        reasons.append("limits-mismatch:%s:cpus" % name)
    pids = host.get("PidsLimit")
    if not is_positive_int(pids):
        reasons.append("pids-unbounded:%s" % name)
    elif eff is not None and pids != eff["pids"]:
        reasons.append("limits-mismatch:%s:pids" % name)
    tmpfs = host.get("Tmpfs") or {}
    if not isinstance(tmpfs, dict) or not all(tmpfs_is_sized(opts) for opts in tmpfs.values()):
        reasons.append("tmpfs-unsized:%s" % name)
    if isinstance(tmpfs, dict) and eff is not None:
        check_tmpfs(name, tmpfs, eff, reasons)
    mode = host.get("NetworkMode")
    normalized = mode.strip().lower() if isinstance(mode, str) else None
    if name in NO_NETWORK_STAGES:
        if normalized != "none":
            reasons.append("network-not-none:%s" % name)
    elif normalized in (None, "", "host", "bridge", "default") or normalized.startswith("container:"):
        reasons.append("network-not-isolated:%s" % name)
    allowed = AGENT_CAPABILITIES if name == "agent" else set()
    for capability in host.get("CapAdd") or []:
        if capability not in allowed:
            reasons.append("capability-added:%s:%s" % (name, capability))


def check_stage_sequence(outcome, stages, reasons):
    """A succeeded run (or an outcome this checker does not know) needs all five stages.

    A blocked or failed run stops where it stopped, so its recorded stages must be a prefix of
    STAGES with no gap. A missing agent gets its own code, because nothing after it can have run.
    """
    if outcome not in INCOMPLETE_OUTCOMES:
        for name in STAGES:
            if name not in stages:
                reasons.append("stage-agent-missing" if name == "agent" else "stage-missing:%s" % name)
        return
    prefix = 0
    while prefix < len(STAGES) and STAGES[prefix] in stages:
        prefix += 1
    if any(name in stages for name in STAGES[prefix:]):
        missing = STAGES[prefix]
        reasons.append("stage-agent-missing" if missing == "agent" else "stage-gap:%s" % missing)


def stage_info(name, stage, info):
    if not isinstance(stage, dict):
        return
    if stage.get("timed_out") is True:
        info.append("stage-timed-out:%s" % name)
    if stage.get("oom_killed") is True:
        info.append("stage-oom-killed:%s" % name)
    code = stage.get("exit_code")
    if isinstance(code, int) and not isinstance(code, bool) and code != 0:
        info.append("stage-exit-nonzero:%s:%d" % (name, code))


def teardown_info(teardown, info):
    if not isinstance(teardown, dict):
        info.append("teardown:not-recorded")
        return
    counts = [teardown.get(kind) for kind in ("containers", "volumes", "networks")]
    if not all(isinstance(count, int) and not isinstance(count, bool) for count in counts):
        info.append("teardown:invalid")
    elif any(count != 0 for count in counts):
        info.append("teardown:leftovers")
    else:
        info.append("teardown:clean")


def check_limits(record, reasons, info):
    if not isinstance(record, dict):
        reasons.append("invalid-input:limits-not-object")
        return
    if record.get("schema_version") != SUPPORTED_SCHEMA:
        reasons.append("schema-version-unsupported")
    outcome = record.get("outcome")
    if outcome not in OUTCOMES:
        reasons.append("invalid-input:outcome")
    eff = effective_values(record, reasons)
    stages = record.get("stages")
    if not isinstance(stages, dict) or not stages:
        reasons.append("invalid-input:stages-missing")
    else:
        for name in sorted(stages):
            if name not in STAGES:
                reasons.append("stage-unknown:%s" % name)
            else:
                check_stage(name, stages[name], eff, reasons)
                stage_info(name, stages[name], info)
        check_stage_sequence(outcome, stages, reasons)
    teardown = record.get("teardown")
    teardown_info(teardown, info)
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
    acl_lines = [line for line in lines if line.startswith("acl ")]

    def named(name):
        return [line for line in acl_lines if acl_name(line) == name]

    if named("SSL_ports") != SQUID_FIXED_ACLS["SSL_ports"]:
        reasons.append("squid:port-not-443")
    if named("CONNECT") != SQUID_FIXED_ACLS["CONNECT"]:
        reasons.append("squid:connect-acl-missing")
    for name in ("manager", "connect_authority", "ip_literal_host"):
        if named(name) != SQUID_FIXED_ACLS[name]:
            reasons.append("squid:acl-definition-mismatch:%s" % name)
    if sorted(named("private_dst")) != sorted(SQUID_FIXED_ACLS["private_dst"]):
        reasons.append("squid:private-ranges-incomplete")
    known = set(SQUID_FIXED_ACLS) | {"allowed_dst"}
    if any(acl_name(line) not in known for line in acl_lines):
        reasons.append("squid:unexpected-acl")
    allowed = named("allowed_dst")
    if not allowed:
        reasons.append("squid:allowed-dst-missing")
    for line in allowed:
        tokens = line.split()
        if len(tokens) < 3 or tokens[2] != "dstdomain":
            reasons.append("squid:allowed-dst-type")
        elif "-n" not in tokens:
            continue  # reported as dstdomain-not-anchored below
        elif tokens != ["acl", "allowed_dst", "dstdomain", "-n", tokens[-1]] or ALLOWED_HOST_RE.fullmatch(tokens[-1]) is None:
            reasons.append("squid:allowed-dst-invalid")
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
        ("http_access deny !connect_authority", "squid:connect-authority-not-denied"),
        ("http_access deny ip_literal_host", "squid:ip-literal-not-denied-before-allow"),
        ("http_access deny private_dst", "squid:private-dst-not-denied-before-allow"),
    ]
    for line, reason in required_denies:
        index = first_index(lines, lambda candidate: candidate == line)
        if index is None or index > first_allow:
            reasons.append(reason)
    http_access = [line for line in lines if line.startswith("http_access ")]
    if not http_access or http_access[-1] != "http_access deny all":
        reasons.append("squid:default-not-deny")
    for line in ("via off", "forwarded_for delete"):
        if line not in exact:
            reasons.append("squid:proxy-headers-not-stripped")


def acl_name(line):
    parts = line.split()
    return parts[1] if len(parts) > 1 else ""


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
    info = []
    record = load_json(args.limits, reasons, "limits-json-unreadable")
    if record is not None:
        check_limits(record, reasons, info)
    if args.squid_conf is not None:
        try:
            with open(args.squid_conf, encoding="utf-8") as handle:
                text = handle.read()
        except (OSError, UnicodeDecodeError):
            reasons.append("invalid-input:squid-conf-unreadable")
        else:
            check_squid(text, reasons)

    verdict = "fail" if reasons else "pass"
    print(json.dumps({"verdict": verdict, "reasons": reasons, "info": info}, separators=(",", ":")))
    return 0 if verdict == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
