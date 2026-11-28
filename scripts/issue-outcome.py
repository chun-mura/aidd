#!/usr/bin/env python3
"""issue-implement outcome: create the run directory, validate and write outcome.json, check it for a host.

Run with `python3 -I` (standard library only). /aidd:issue-implement calls `start` before its entry gate
and `write` at every stop; a non-interactive host calls `check`. `write` runs no git, so it may run after
an audit session that could have changed the repository; it walks the run directory without following
symlinks so it never writes outside it. A rejection names the key, never the offending value.
Exit codes: 0 ok, 1 input rejected, 2 the command itself failed.
Design: docs/superpowers/specs/2026-11-28-issue-implement-outcome-design.md
"""
import argparse, errno, json, os, re, secrets, stat, subprocess, sys, time

SCHEMA_VERSION = 1
RUN_PARENTS = (".aidd", "issue-implement")
RUN_ID = re.compile(r"^\d{8}T\d{6}Z-[0-9a-f]{8}$")
ISSUE = re.compile(r"^[1-9][0-9]*$")
STATUSES = ("done", "needs_input", "blocked")
REASONS = ("gh_unavailable", "split_proposed", "review_unconverged", "audit_session_launched",
           "verification_failed", "undecided_rows", "incomplete")
KINDS = ("spec_choice", "approval")
BODY_KEYS = ("issue", "status", "reason", "questions", "completion", "artifacts")
DOC_KEYS = ("schema_version", "run_id") + BODY_KEYS
COMPLETION = {"verification": "passed", "undecided_rows": 0, "untracked_deferred": 0}
ARTIFACT_KEYS = ("design_doc", "test_perspectives")
MAX_OPTIONS = 4
LIMITS = {"question": 1000, "label": 80, "effect": 400}
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


class Rejected(Exception):
    """The input does not match the schema or the expected location (exit 1)."""


class Failed(Exception):
    """The command could not do its work (exit 2)."""


def _no_duplicates(pairs):
    keys = [k for k, _ in pairs]
    if len(keys) != len(set(keys)):
        raise ValueError("duplicate key")
    return dict(pairs)


def parse(raw):
    try:
        data = json.loads(raw, object_pairs_hook=_no_duplicates)
    except ValueError as e:
        return None, ["not valid JSON" + (" (duplicate key)" if "duplicate key" in str(e) else "")]
    except RecursionError:
        return None, ["not valid JSON (nested too deeply)"]
    if not isinstance(data, dict):
        return None, ["top level is not an object"]
    return data, []


def _keys(obj, expected, where):
    errors = []
    if not isinstance(obj, dict):
        return [f"{where} is not an object"]
    for key in obj:
        if key not in expected:
            errors.append(f"{where}: unknown key")
    for key in expected:
        if key not in obj:
            errors.append(f"{where}: missing key {key}")
    return errors


def _encodable(value):
    try:
        value.encode("utf-8")
        return True
    except UnicodeEncodeError:
        return False


def _text(value, field, where):
    if not isinstance(value, str) or not value.strip() or not _encodable(value):
        return [f"{where}.{field} is not a non-blank UTF-8 string"]
    if len(value) > LIMITS[field]:
        return [f"{where}.{field} is longer than {LIMITS[field]} characters"]
    return []


def _artifact(value, key, top):
    if value is None:
        return []
    where = f"artifacts.{key}"
    if not isinstance(value, str) or not value or not _encodable(value) or os.path.isabs(value) \
            or "\\" in value or "\0" in value:
        return [f"{where} is not a relative path"]
    parts = value.split("/")
    if ".." in parts:
        return [f"{where} contains '..'"]
    if "" in parts or "." in parts:
        return [f"{where} is not a normalized path"]
    # Walk without following symlinks: a link could point outside the repository.
    current = top
    for i, part in enumerate(parts):
        current = os.path.join(current, part)
        try:
            mode = os.lstat(current).st_mode
        except OSError:
            return [f"{where} is not an existing regular file"]
        # lstat reports a symlink as neither a regular file nor a directory, so both checks refuse it.
        last = i == len(parts) - 1
        if (last and not stat.S_ISREG(mode)) or (not last and not stat.S_ISDIR(mode)):
            return [f"{where} is not an existing regular file (symlinks are not followed)"]
    return []


def check_body(data, top):
    """Errors for the keys the caller writes. `top` is the repository top for artifact paths."""
    errors = _keys(data, BODY_KEYS, "outcome")
    if errors:
        return errors
    issue, status, reason = data["issue"], data["status"], data["reason"]
    questions, completion, artifacts = data["questions"], data["completion"], data["artifacts"]
    if issue is not None and not (isinstance(issue, str) and ISSUE.fullmatch(issue)):
        errors.append("issue is not null or a string of digits")
    if status not in STATUSES:
        return errors + ["status is not one of " + "/".join(STATUSES)]
    if status == "blocked":
        if reason not in REASONS:
            errors.append("reason is not one of the blocked reasons")
    elif reason is not None:
        errors.append(f"reason must be null when status is {status}")
    if not isinstance(questions, list):
        errors.append("questions is not an array")
    elif status == "needs_input":
        if not questions:
            errors.append("questions is empty while status is needs_input")
        for i, q in enumerate(questions):
            errors += _question(q, f"questions[{i}]")
    elif questions:
        errors.append(f"questions must be empty when status is {status}")
    if status == "done":
        if not isinstance(completion, dict) or _keys(completion, tuple(COMPLETION), "completion"):
            errors.append("completion must be {verification, undecided_rows, untracked_deferred} when status is done")
        elif any(type(completion[k]) is not type(v) or completion[k] != v for k, v in COMPLETION.items()):
            errors.append("completion must be verification=passed, undecided_rows=0, untracked_deferred=0 for done")
    elif completion is not None:
        errors.append(f"completion must be null when status is {status}")
    key_errors = _keys(artifacts, ARTIFACT_KEYS, "artifacts")
    if key_errors:
        errors += key_errors
    else:
        for key in ARTIFACT_KEYS:
            errors += _artifact(artifacts[key], key, top)
    return errors


def _question(q, where):
    errors = _keys(q, ("question", "kind", "options"), where)
    if errors:
        return errors
    errors += _text(q["question"], "question", where)
    if q["kind"] not in KINDS:
        errors.append(f"{where}.kind is not one of " + "/".join(KINDS))
    options = q["options"]
    if not isinstance(options, list) or not 2 <= len(options) <= MAX_OPTIONS:
        return errors + [f"{where}.options is not an array of 2 to {MAX_OPTIONS}"]
    labels = []
    for j, o in enumerate(options):
        ow = f"{where}.options[{j}]"
        o_errors = _keys(o, ("label", "effect"), ow)
        if o_errors:
            errors += o_errors
            continue
        errors += _text(o["label"], "label", ow) + _text(o["effect"], "effect", ow)
        if isinstance(o["label"], str):
            labels.append(o["label"])
    if len(labels) != len(set(labels)):
        errors.append(f"{where}.options has a duplicate label")
    return errors


def check_document(data, run_id, top):
    errors = _keys(data, DOC_KEYS, "outcome")
    if errors:
        return errors
    if type(data["schema_version"]) is not int or data["schema_version"] != SCHEMA_VERSION:
        errors.append(f"schema_version is not {SCHEMA_VERSION}")
    if data["run_id"] != run_id:
        errors.append("run_id does not match the run directory name")
    body = {k: data[k] for k in BODY_KEYS}
    return errors + check_body(body, top)


def _open_dir(name, parent_fd):
    """Open a child directory without following a symlink."""
    try:
        return os.open(name, DIR_FLAGS, dir_fd=parent_fd)
    except FileNotFoundError:
        raise Failed(f"{name} does not exist")
    except OSError as e:
        if e.errno in (errno.ELOOP, errno.ENOTDIR):
            raise Rejected(f"{name} is a symlink or not a directory")
        raise Failed(f"cannot open {name} ({type(e).__name__})")


def split_run_dir(path):
    """(top, run_id) when path names <top>/.aidd/issue-implement/<run id>, else Rejected."""
    path = os.path.abspath(path)
    run_id = os.path.basename(path)
    parent = os.path.dirname(path)
    if not RUN_ID.fullmatch(run_id) or os.path.basename(parent) != RUN_PARENTS[1] \
            or os.path.basename(os.path.dirname(parent)) != RUN_PARENTS[0]:
        raise Rejected("run directory is not <top>/.aidd/issue-implement/<run id>")
    return os.path.dirname(os.path.dirname(parent)), run_id


def _open_run_dir(top, run_id):
    """A descriptor of <top>/.aidd/issue-implement/<run id>, opened without following a symlink."""
    try:
        fd = os.open(top, DIR_FLAGS)
    except OSError as e:
        raise Failed(f"cannot open the repository top ({type(e).__name__})")
    try:
        for name in RUN_PARENTS + (run_id,):
            child = _open_dir(name, fd)
            os.close(fd)
            fd = child
    except BaseException:
        os.close(fd)
        raise
    return fd


def cmd_start(_args):
    run_id = os.environ.get("AIDD_ISSUE_IMPLEMENT_RUN_ID")
    if run_id is None:
        run_id = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + secrets.token_hex(4)
    elif not RUN_ID.fullmatch(run_id):
        raise Rejected("AIDD_ISSUE_IMPLEMENT_RUN_ID is not YYYYMMDDTHHMMSSZ-<8 hex>")
    try:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                             check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        raise Failed("not inside a git work tree")
    fd = os.open(top, DIR_FLAGS)
    try:
        for name in RUN_PARENTS:
            try:
                os.mkdir(name, dir_fd=fd)
            except FileExistsError:
                pass
            try:
                child = _open_dir(name, fd)
            except Rejected as e:
                raise Failed(str(e))
            os.close(fd)
            fd = child
        try:
            os.mkdir(run_id, dir_fd=fd)
        except FileExistsError:
            raise Failed("the run directory already exists")
    finally:
        os.close(fd)
    print(os.path.join(top, *RUN_PARENTS, run_id))
    return 0


def cmd_write(args):
    top, run_id = split_run_dir(args.run_dir)
    try:
        raw = sys.stdin.buffer.read().decode("utf-8")
    except UnicodeDecodeError:
        raise Rejected("stdin is not UTF-8")
    data, errors = parse(raw)
    if not errors:
        errors = check_body(data, top)
    if errors:
        raise Rejected("\n".join(errors))
    doc = {"schema_version": SCHEMA_VERSION, "run_id": run_id, **data}
    fd = _open_run_dir(top, run_id)
    try:
        try:
            if not stat.S_ISREG(os.stat("outcome.json", dir_fd=fd, follow_symlinks=False).st_mode):
                raise Rejected("outcome.json exists and is not a regular file")
        except FileNotFoundError:
            pass
        tmp = f".outcome.{secrets.token_hex(4)}.tmp"
        replaced = False
        try:
            out = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=fd)
            with os.fdopen(out, "w", encoding="utf-8") as f:
                json.dump(doc, f, ensure_ascii=False, indent=2)
                f.write("\n")
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, "outcome.json", src_dir_fd=fd, dst_dir_fd=fd)
            replaced = True
        except OSError as e:
            raise Failed(f"cannot write outcome.json ({type(e).__name__})")
        finally:
            if not replaced:
                try:
                    os.unlink(tmp, dir_fd=fd)
                except OSError:
                    pass
    finally:
        os.close(fd)
    return 0


def cmd_check(args):
    path = os.path.abspath(args.file)
    if os.path.basename(path) != "outcome.json":
        raise Rejected("file is not <top>/.aidd/issue-implement/<run id>/outcome.json")
    top, run_id = split_run_dir(os.path.dirname(path))
    fd = _open_run_dir(top, run_id)
    try:
        try:
            # O_NONBLOCK keeps a FIFO from blocking the open; the fstat below then refuses it.
            file_fd = os.open("outcome.json", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        except FileNotFoundError:
            raise Failed("outcome.json does not exist")
        except OSError as e:
            if e.errno == errno.ELOOP:
                raise Rejected("outcome.json is a symlink")
            raise Failed(f"cannot read outcome.json ({type(e).__name__})")
        # fstat before fdopen: fdopen itself refuses a directory with IsADirectoryError.
        if not stat.S_ISREG(os.fstat(file_fd).st_mode):
            os.close(file_fd)
            raise Rejected("outcome.json is not a regular file")
        with os.fdopen(file_fd, "rb") as f:
            raw = f.read()
    finally:
        os.close(fd)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise Rejected("not UTF-8")
    data, errors = parse(text)
    if not errors:
        errors = check_document(data, run_id, top)
    if not errors and args.issue is not None and data["issue"] != args.issue:
        errors.append("issue does not match --issue")
    if errors:
        raise Rejected("\n".join(errors))
    print(data["status"])
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("start").set_defaults(func=cmd_start)
    p = sub.add_parser("write")
    p.add_argument("run_dir")
    p.set_defaults(func=cmd_write)
    p = sub.add_parser("check")
    p.add_argument("file")
    p.add_argument("--issue")
    p.set_defaults(func=cmd_check)
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except Rejected as e:
        for line in str(e).splitlines():
            print(f"issue-outcome: rejected: {line}", file=sys.stderr)
        return 1
    except Failed as e:
        print(f"issue-outcome: failed: {e}", file=sys.stderr)
        return 2
    except Exception as e:  # anything unforeseen is a failed command, never a rejected input or a traceback
        print(f"issue-outcome: failed: {type(e).__name__}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
