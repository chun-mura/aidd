"""Static checks for the example GitHub workflows under examples/assurance/github (#156, #157).

Python standard library only, so the contract tests need no PyYAML or actionlint. `parse` reads
the block-style YAML subset the examples use (mappings, lists, block scalars, flow lists and `{}`)
and raises on anything else, so a construct it does not understand fails the test instead of
passing unchecked. It is not a general YAML parser.
"""

import re

SHA_PIN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$")
# Events that run with a write token or secrets while the code or text comes from a pull request.
PRIVILEGED_EVENTS = {"pull_request_target", "workflow_run", "issue_comment", "pull_request_review_comment"}
# Attacker-controlled event fields that must not be expanded into the workflow (script injection).
INJECTABLE = re.compile(
    r"github\.(head_ref|event\.(pull_request\.(title|body|head\.ref|head\.label)|comment\.body|"
    r"issue\.(title|body)|review\.body|commits|head_commit\.message))"
)


def _strip_comment(s):
    quote = None
    for i, ch in enumerate(s):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (i == 0 or s[i - 1] in " \t"):
            return s[:i].rstrip()
    return s.rstrip()


def _tokens(text):
    raw = text.splitlines()
    out, i = [], 0
    while i < len(raw):
        line = raw[i]
        if "\t" in line[: len(line) - len(line.lstrip())]:
            raise ValueError("tab indentation on line %d" % (i + 1))
        content = _strip_comment(line.strip())
        if not content:
            i += 1
            continue
        indent = len(line) - len(line.lstrip(" "))
        block = None
        if re.search(r"(^|:\s|^-\s)[|>][-+]?$", content):
            body, j = [], i + 1
            while j < len(raw) and (not raw[j].strip() or len(raw[j]) - len(raw[j].lstrip(" ")) > indent):
                body.append(raw[j])
                j += 1
            pad = min((len(b) - len(b.lstrip(" ")) for b in body if b.strip()), default=0)
            block = "\n".join(b[pad:] for b in body).rstrip("\n") + "\n"
            content = re.sub(r"\s*[|>][-+]?$", "", content)
            i = j
        else:
            i += 1
        out.append([indent, content, block])
    return out


def _scalar(s):
    s = s.strip()
    if s in ("", "~", "null"):
        return None
    if s[0] in "'\"":
        if len(s) < 2 or s[-1] != s[0]:
            raise ValueError("unterminated quote: %s" % s)
        return s[1:-1]
    if s == "{}":
        return {}
    if s.startswith("["):
        if not s.endswith("]"):
            raise ValueError("unsupported flow list: %s" % s)
        inner = s[1:-1].strip()
        return [_scalar(x) for x in inner.split(",")] if inner else []
    if s.startswith("{"):
        raise ValueError("unsupported flow mapping: %s" % s)
    if s in ("true", "false"):
        return s == "true"
    if re.fullmatch(r"-?[0-9]+", s):
        return int(s)
    return s


def _split_key(content):
    quote = None
    for i, ch in enumerate(content):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == ":" and (i + 1 == len(content) or content[i + 1] == " "):
            return _scalar(content[:i]), content[i + 1 :].strip()
    return None, None


def _parse(toks, i, indent):
    if toks[i][1].startswith("- ") or toks[i][1] == "-":
        items = []
        while i < len(toks) and toks[i][0] == indent and (toks[i][1].startswith("- ") or toks[i][1] == "-"):
            rest = toks[i][1][1:].strip()
            if toks[i][2] is not None and not rest:
                value = toks[i][2]
                i += 1
            elif not rest:
                value, i = _parse(toks, i + 1, toks[i + 1][0])
            elif _split_key(rest)[0] is not None and not rest.startswith(("'", '"', "[")):
                toks[i] = [indent + 2, rest, toks[i][2]]
                value, i = _parse(toks, i, indent + 2)
            else:
                value = _scalar(rest)
                i += 1
            items.append(value)
        return items, i
    mapping = {}
    while i < len(toks) and toks[i][0] == indent:
        key, rest = _split_key(toks[i][1])
        if key is None:
            raise ValueError("expected 'key:' at %r" % toks[i][1])
        if key in mapping:
            raise ValueError("duplicate key %r" % key)
        block = toks[i][2]
        i += 1
        if block is not None:
            mapping[key] = block
        elif rest:
            mapping[key] = _scalar(rest)
        elif i < len(toks) and (toks[i][0] > indent or (toks[i][0] == indent and toks[i][1].startswith("-"))):
            mapping[key], i = _parse(toks, i, toks[i][0])
        else:
            mapping[key] = None
    return mapping, i


def parse(text):
    toks = _tokens(text)
    if not toks:
        return {}
    doc, i = _parse(toks, 0, toks[0][0])
    if i != len(toks):
        raise ValueError("could not parse from %r" % toks[i][1])
    return doc


def lint_workflow(doc, text, allowed_events, write_scopes=None):
    """Problems shared by every example workflow. write_scopes: {job id: {scope: 'write'}} allowed."""
    write_scopes = write_scopes or {}
    problems = []
    events = doc.get("on")
    if isinstance(events, list):
        events = {e: None for e in events}
    if not isinstance(events, dict) or not events:
        return ["no 'on' triggers"]
    for event, conf in events.items():
        if event in PRIVILEGED_EVENTS or event not in allowed_events:
            problems.append("trigger %s is not allowed" % event)
        if isinstance(conf, dict) and ({"paths", "paths-ignore"} & conf.keys()):
            problems.append("trigger %s filters paths (a required check that never starts blocks, one that is skipped passes)" % event)
    if doc.get("permissions") != {}:
        problems.append("top-level permissions must be {} (each job asks for its own)")
    if re.search(r"\bsecrets\.\w", text):
        problems.append("the workflow references secrets")
    if INJECTABLE.search(text):
        problems.append("the workflow expands attacker-controlled event text: %s" % INJECTABLE.search(text).group(0))
    for job_id, job in (doc.get("jobs") or {}).items():
        perms = job.get("permissions")
        if not isinstance(perms, dict) or not perms:
            problems.append("%s: job permissions must be an explicit mapping" % job_id)
            perms = {}
        allowed = write_scopes.get(job_id, {})
        for scope, level in perms.items():
            if level != "read" and allowed.get(scope) != level:
                problems.append("%s: %s: %s is not allowed" % (job_id, scope, level))
        if not isinstance(job.get("timeout-minutes"), int):
            problems.append("%s: timeout-minutes is not set" % job_id)
        if "container" in job or "services" in job:
            problems.append("%s: containers and services are outside this example" % job_id)
        for step in job.get("steps") or []:
            uses = step.get("uses")
            if uses is None:
                continue
            if not SHA_PIN.match(uses):
                problems.append("%s: %s is not pinned to a full commit SHA" % (job_id, uses))
            if uses.startswith("actions/checkout@") and (step.get("with") or {}).get("persist-credentials") is not False:
                problems.append("%s: checkout keeps the token in .git/config (persist-credentials)" % job_id)
    return problems
