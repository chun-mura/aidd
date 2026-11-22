#!/usr/bin/env python3
"""Learnings ledger: check, write and count observations under .aidd/learnings/.

Run with `python3 -I` (standard library only). The same check_document() backs the write
(`add`, called by /aidd:incident-retro) and the commit-time check in hooks/scripts/tool-reminder.sh.
A finding is rejected, never masked, and its reason never repeats the offending value.
Design: docs/superpowers/specs/2026-11-22-learnings-ledger-design.md
"""
import argparse, hashlib, json, math, os, re, secrets, subprocess, sys, time

LEDGER_DIR = ".aidd/learnings"
SCHEMA_VERSION = 1
MAX_BYTES = 4096
MAX_FACT = 200
MAX_EVIDENCE = 10
ENUMS = {
    "source": ("incident-retro", "auto-memory", "autonomous-review"),
    "scope": ("project", "tool", "aidd"),
    "status": ("observed", "applied", "declined"),
}
KEYS = ("schema_version", "source", "scope", "status", "signature", "fact", "evidence", "session")
FILE_NAME = re.compile(r"^\.aidd/learnings/\d{8}T\d{6}Z-[0-9a-f]{8}\.json$")
SESSION = re.compile(r"^[0-9a-f]{12}$")
SIGNATURE_HEAD = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]*$")
SIGNATURE_WORD = re.compile(r"^(?:[a-z][a-z0-9-]*|-[A-Za-z0-9]+|--[A-Za-z0-9][A-Za-z0-9-]*)$")
MAX_SIGNATURE = 80
MAX_SIGNATURE_WORDS = 8
EVIDENCE_FORMS = (
    re.compile(r"^[0-9a-f]{7,40}$"),  # commit SHA
    re.compile(r"^#[0-9]+$"),  # PR / issue number
    re.compile(r"^(?!.*(?:^|/)\.\.(?:/|$))(?!.*//)[A-Za-z0-9_.][A-Za-z0-9_./-]*$"),  # repo-relative path
)
CONTROL = re.compile(r"[\x00-\x1f\x7f]")

# TLDs that do not double as common file extensions (ts, py, sh, md, rs, js are left out).
TLDS = ("com|net|org|edu|gov|mil|int|io|dev|app|cloud|ai|co|jp|us|uk|de|fr|cn|kr|tw|in|info|biz"
        "|me|tech|online|site|xyz|local|localdomain|internal|intranet|corp|lan|home|example|invalid")
PATTERNS = [
    ("absolute path", re.compile(r"(?<![\w.~:/-])/[\w.-]+/[\w./-]*|(?<![A-Za-z0-9])[A-Za-z]:[\\/]")),
    ("email address", re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")),
    ("URL", re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://|(?<![\w.])www\.", re.I)),
    ("IP address", re.compile(
        r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.]*\w)"
        r"|(?<![\w:])(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}(?![\w:])"
        r"|(?<![\w:])(?:[0-9a-f]{1,4}:)+:(?:[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*)?(?![\w:])", re.I)),
    ("host name (FQDN)", re.compile(r"(?<![\w.-])(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:" + TLDS + r")(?![\w-]|\.\w)", re.I)),
    ("token prefix", re.compile(
        r"(?<![A-Za-z0-9])(?:gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9_-]{16,}"
        r"|(?:AKIA|ASIA)[A-Z0-9]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{16,}|AIza[A-Za-z0-9_-]{30,})"
        r"|-----BEGIN [A-Z ]+-----")),
    ("ID (UUID)", re.compile(r"(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])", re.I)),
    ("long hex string", re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{41,}(?![0-9a-fA-F])")),
    ("company name hint", re.compile(
        r"株式会社|有限会社|合同会社|[（(]株[）)]|㈱|\bInc\.|\bCorp\.|\bCorporation\b|\bLtd\b|\bLLC\b|\bGmbH\b|\bK\.K\.")),
]
ALLOWED_PATHS = re.compile(r"/dev/(?:null|stdout|stderr)\b")
# Runs are cut at - _ . / so identifiers, versions and paths fall apart into short words.
ENTROPY_RUN = re.compile(r"[A-Za-z0-9+=]{16,}")
ENTROPY_LIMIT = 3.5


def _entropy(text):
    counts = {}
    for ch in text:
        counts[ch] = counts.get(ch, 0) + 1
    return -sum(n / len(text) * math.log2(n / len(text)) for n in counts.values())


def _high_entropy(text):
    for run in ENTROPY_RUN.findall(text):
        if re.fullmatch(r"[0-9a-fA-F]{1,40}", run):
            continue  # commit SHA
        digits = sum(ch.isdigit() for ch in run)
        if re.search(r"[A-Za-z]", run) and digits >= 2 and _entropy(run) >= ENTROPY_LIMIT:
            return True
    return False


def scan_text(field, text):
    """Return the rules a string breaks. Reasons name the field and rule, never the value."""
    text_for_paths = ALLOWED_PATHS.sub(" ", text)
    found = []
    for rule, pattern in PATTERNS:
        if pattern.search(text_for_paths if rule == "absolute path" else text):
            found.append(f"{field}: contains a {rule}")
    if _high_entropy(text):
        found.append(f"{field}: contains a high-entropy string (token or ID)")
    return found


def _no_duplicates(pairs):
    keys = [k for k, _ in pairs]
    duplicated = sorted({k for k in keys if keys.count(k) > 1})
    if duplicated:
        raise ValueError("duplicate key: " + ", ".join(duplicated))
    return dict(pairs)


def check_signature(value):
    errors = []
    words = value.split(" ")
    if not value or len(value) > MAX_SIGNATURE or len(words) > MAX_SIGNATURE_WORDS:
        errors.append(f"signature: must be 1-{MAX_SIGNATURE} chars and at most {MAX_SIGNATURE_WORDS} words")
    elif not SIGNATURE_HEAD.match(words[0]) or not all(SIGNATURE_WORD.match(w) for w in words[1:]):
        errors.append("signature: only a command or tool name, lowercase subcommands and flags without values")
    return errors


def check_object(data):
    """Schema and pattern check of a parsed observation."""
    if not isinstance(data, dict):
        return ["not a JSON object"]
    errors = []
    extra = sorted(set(data) - set(KEYS))
    missing = [k for k in KEYS if k not in data]
    if extra:
        errors.append("unknown keys: " + ", ".join(extra))
    if missing:
        errors.append("missing keys: " + ", ".join(missing))
    version = data.get("schema_version")
    if "schema_version" in data and (type(version) is not int or version != SCHEMA_VERSION):
        errors.append(f"schema_version: must be {SCHEMA_VERSION}")
    for key, allowed in ENUMS.items():
        if key in data and data[key] not in allowed:
            errors.append(f"{key}: must be one of " + ", ".join(allowed))
    strings = []
    if "fact" in data:
        fact = data["fact"]
        if not isinstance(fact, str) or not fact.strip() or len(fact) > MAX_FACT or CONTROL.search(fact):
            errors.append(f"fact: must be 1-{MAX_FACT} chars on one line")
        else:
            strings.append(("fact", fact))
    if "signature" in data:
        signature = data["signature"]
        if not isinstance(signature, str):
            errors.append("signature: must be a string")
        else:
            errors += check_signature(signature)
            strings.append(("signature", signature))
    if "evidence" in data:
        evidence = data["evidence"]
        if not isinstance(evidence, list) or len(evidence) > MAX_EVIDENCE:
            errors.append(f"evidence: must be a list of at most {MAX_EVIDENCE} items")
        else:
            for i, item in enumerate(evidence):
                field = f"evidence[{i}]"
                if not isinstance(item, str) or not any(f.match(item) for f in EVIDENCE_FORMS):
                    errors.append(f"{field}: must be a commit SHA, #number or repository-relative path")
                else:
                    strings.append((field, item))
    if "session" in data and not (isinstance(data["session"], str) and SESSION.match(data["session"])):
        errors.append("session: must be 12 lowercase hex chars (hashed session ID)")
    for field, text in strings:
        errors += scan_text(field, text)
    return errors


def check_document(name, raw):
    """Check one ledger file. name is repository-relative; raw is its bytes."""
    errors = []
    if not FILE_NAME.match(name):
        errors.append("file name: must be .aidd/learnings/<YYYYMMDDTHHMMSSZ>-<8 hex>.json")
    if len(raw) > MAX_BYTES:
        return errors + [f"file: larger than {MAX_BYTES} bytes"]
    try:
        data = json.loads(raw.decode("utf-8"), object_pairs_hook=_no_duplicates)
    except ValueError as exc:
        reason = str(exc) if str(exc).startswith("duplicate key") else "not valid UTF-8 JSON"
        return errors + [reason]
    return errors + check_object(data)


# --- repository helpers ----------------------------------------------------------------------

def _git(repo, *args, binary=False):
    try:
        result = subprocess.run(["git", "-C", repo, *args], capture_output=True, timeout=10)
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return result.stdout if binary else result.stdout.decode("utf-8", "replace").strip()


def toplevel(repo):
    return _git(repo, "rev-parse", "--show-toplevel")


def enabled(repo):
    return _git(repo, "config", "--bool", "--get", "aidd.learnings") == "true"


def hash_session(raw):
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]


def default_ref(repo):
    head = _git(repo, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    for ref in ([head] if head else []) + ["refs/remotes/origin/main", "refs/heads/main"]:
        if _git(repo, "rev-parse", "--verify", "--quiet", ref + "^{commit}"):
            return ref
    return None


def observations(top):
    """Yield (file name, parsed observation) for every observation that passes the check, from
    the default branch and the working tree. The same file name counts once."""
    seen = {}
    ref = default_ref(top)
    if ref:
        listing = _git(top, "ls-tree", "-r", "--name-only", ref, "--", LEDGER_DIR + "/") or ""
        for name in listing.splitlines():
            raw = _git(top, "cat-file", "blob", f"{ref}:{name}", binary=True)
            if raw is not None:
                seen[name] = raw
    directory = os.path.join(top, LEDGER_DIR)
    if os.path.isdir(directory):
        for entry in sorted(os.listdir(directory)):
            path = os.path.join(directory, entry)
            if os.path.isfile(path):
                with open(path, "rb") as f:
                    seen[f"{LEDGER_DIR}/{entry}"] = f.read(MAX_BYTES + 1)
    for name in sorted(seen):
        if not check_document(name, seen[name]):
            yield name, json.loads(seen[name].decode("utf-8"))


# --- commands --------------------------------------------------------------------------------

def cmd_check(args):
    top = toplevel(args.repo) or os.path.abspath(args.repo)
    failed = False
    for path in args.files:
        name = os.path.relpath(os.path.abspath(path), top).replace(os.sep, "/")
        with open(path, "rb") as f:
            errors = check_document(name, f.read(MAX_BYTES + 1))
        for error in errors:
            print(f"{name}: {error}")
        failed = failed or bool(errors)
    return 1 if failed else 0


def cmd_add(args):
    top = toplevel(args.repo)
    if not top:
        print("not inside a git repository", file=sys.stderr)
        return 2
    if not enabled(top):
        print("the learnings ledger is disabled here (enable per clone: git config aidd.learnings true)",
              file=sys.stderr)
        return 3
    try:
        data = json.loads(sys.stdin.read(), object_pairs_hook=_no_duplicates)
    except ValueError as exc:
        print(f"input: {exc}" if str(exc).startswith("duplicate key") else "input: not valid JSON",
              file=sys.stderr)
        return 1
    if not isinstance(data, dict) or {"schema_version", "session"} & set(data):
        print("input: a JSON object without schema_version and session (the script sets them)",
              file=sys.stderr)
        return 1
    data = {"schema_version": SCHEMA_VERSION, **data, "session": hash_session(args.session_id)}
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    name = f"{LEDGER_DIR}/{stamp}-{secrets.token_hex(4)}.json"
    body = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    errors = check_document(name, body)
    if errors:
        print("rejected (rewrite the observation; do not mask it):", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1
    os.makedirs(os.path.join(top, LEDGER_DIR), exist_ok=True)
    with open(os.path.join(top, name), "xb") as f:
        f.write(body)
    print(name)
    return 0


def cmd_candidates(args):
    top = toplevel(args.repo)
    if not top:
        print("not inside a git repository", file=sys.stderr)
        return 2
    groups = {}
    for name, data in observations(top):
        group = groups.setdefault(data["signature"], {"sessions": set(), "files": [], "facts": []})
        group["sessions"].add(data["session"])
        group["files"].append(name)
        group["facts"].append(data["fact"])
    if args.session_id:
        current = hash_session(args.session_id)
        for signature in args.signature:
            group = groups.setdefault(signature, {"sessions": set(), "files": [], "facts": []})
            group["sessions"].add(current)
    for signature in sorted(groups):
        group = groups[signature]
        if len(group["sessions"]) >= 2:
            print(json.dumps({"signature": signature, "sessions": len(group["sessions"]),
                              "files": group["files"], "facts": group["facts"]}, ensure_ascii=False))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check", help="check ledger files; exit 1 if any is rejected")
    check.add_argument("--repo", default=".")
    check.add_argument("files", nargs="+")
    add = sub.add_parser("add", help="check one observation from stdin and write it if it passes")
    add.add_argument("--repo", default=".")
    add.add_argument("--session-id", required=True)
    cand = sub.add_parser("candidates", help="print signatures seen in two or more sessions")
    cand.add_argument("--repo", default=".")
    cand.add_argument("--session-id")
    cand.add_argument("--signature", action="append", default=[])
    args = parser.parse_args(argv)
    return {"check": cmd_check, "add": cmd_add, "candidates": cmd_candidates}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
