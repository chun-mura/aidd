#!/usr/bin/env python3
"""A small fictional implementation of the Publish model, and its trace recorder.

The service code (ArtifactStore, Publisher) is written as ordinary code; it does
not import or mirror the model. The recorder maps the implementation state to
the model variables after every operation and writes TraceData.tla, which
TraceCheck.tla replays against Publish.tla.

Usage:
  publish_service.py random --seed N --steps M --out DIR [--defect no-recheck]
  publish_service.py race --out DIR [--defect no-recheck]
"""
import argparse
import os
import random
import threading
from dataclasses import dataclass

ARTIFACTS = ("a1", "a2")
PUBLISHERS = ("p1", "p2")


class Rejected(Exception):
    """The store refused an operation; nothing changed."""


@dataclass
class Record:
    revision: int = 0
    verified_revision: int | None = None
    approved_revision: int | None = None
    published_revision: int | None = None


class ArtifactStore:
    """Every public method runs under one lock, so each call is atomic."""

    def __init__(self, ids, recheck_on_publish=True):
        self._lock = threading.Lock()
        self._records = {i: Record() for i in ids}
        self._recheck = recheck_on_publish

    def _ready(self, rec):
        return (rec.verified_revision == rec.revision
                and rec.approved_revision == rec.revision)

    def verify(self, artifact_id):
        with self._lock:
            rec = self._records[artifact_id]
            if rec.verified_revision == rec.revision:
                raise Rejected("already verified")
            rec.verified_revision = rec.revision

    def approve(self, artifact_id):
        with self._lock:
            rec = self._records[artifact_id]
            if rec.verified_revision != rec.revision:
                raise Rejected("not verified")
            if rec.approved_revision == rec.revision:
                raise Rejected("already approved")
            rec.approved_revision = rec.revision

    def revoke(self, artifact_id):
        with self._lock:
            rec = self._records[artifact_id]
            if rec.approved_revision != rec.revision:
                raise Rejected("no approval in force")
            rec.approved_revision = None
            rec.published_revision = None

    def modify(self, artifact_id):
        with self._lock:
            rec = self._records[artifact_id]
            rec.revision += 1
            rec.published_revision = None

    def check_ready(self, artifact_id):
        """Raise unless the current revision may be published now."""
        with self._lock:
            rec = self._records[artifact_id]
            if not self._ready(rec) or rec.published_revision == rec.revision:
                raise Rejected("not ready")

    def publish(self, artifact_id):
        """Publish the current revision. Returns False when the recheck refuses it."""
        with self._lock:
            rec = self._records[artifact_id]
            if self._recheck and not self._ready(rec):
                return False
            rec.published_revision = rec.revision
            return True

    def snapshot(self):
        with self._lock:
            return {i: Record(**vars(r)) for i, r in self._records.items()}


class Publisher:
    """Checks an artifact, then publishes it in a later, separate call."""

    def __init__(self, store):
        self._store = store
        self.pending = None  # artifact_id between check and publish

    def check(self, artifact_id):
        if self.pending is not None:
            raise Rejected("busy")
        self._store.check_ready(artifact_id)
        self.pending = artifact_id

    def publish(self):
        if self.pending is None:
            raise Rejected("nothing checked")
        artifact_id, self.pending = self.pending, None
        self._store.publish(artifact_id)

    def crash(self):
        """Lose the in-memory pending work, as a restart would."""
        if self.pending is None:
            raise Rejected("nothing to lose")
        self.pending = None


# ---- refinement mapping: implementation state -> model variables ----

def abstract_state(store, publishers):
    snap = store.snapshot()
    return {
        "verified": {i: r.verified_revision == r.revision for i, r in snap.items()},
        "approved": {i: r.approved_revision == r.revision for i, r in snap.items()},
        "published": {i: r.published_revision == r.revision for i, r in snap.items()},
        "pending": {p: (pub.pending or "none")
                    for p, pub in publishers.items()},
    }


def apply(store, publishers, op):
    name, arg = op
    if name == "Check":
        publishers[arg[0]].check(arg[1])
    elif name == "Publish":
        publishers[arg].publish()
    elif name == "Crash":
        publishers[arg].crash()
    else:
        getattr(store, name.lower())(arg)


def candidate_ops():
    ops = []
    for a in ARTIFACTS:
        ops += [("Verify", a), ("Approve", a), ("Revoke", a), ("Modify", a)]
    for p in PUBLISHERS:
        ops += [("Publish", p), ("Crash", p)]
        ops += [("Check", (p, a)) for a in ARTIFACTS]
    return ops


def run(rounds, recheck):
    """Each round lists operations to try in order; the first one the
    implementation accepts is applied and recorded. Rejected ones change nothing."""
    store = ArtifactStore(ARTIFACTS, recheck_on_publish=recheck)
    publishers = {p: Publisher(store) for p in PUBLISHERS}
    initial = abstract_state(store, publishers)
    steps = []
    for ops in rounds:
        for op in ops:
            try:
                apply(store, publishers, op)
            except Rejected:
                continue
            steps.append((op, abstract_state(store, publishers)))
            break
    return initial, steps


def random_rounds(seed, count):
    rng = random.Random(seed)
    for _ in range(count):
        ops = candidate_ops()
        if rng.random() < 0.9:  # Modify is always accepted; keep it rare
            ops = [op for op in ops if op[0] != "Modify"]
        rng.shuffle(ops)
        yield ops


# The interleaving TLC found for the defective model.
RACE = [("Verify", "a1"), ("Approve", "a1"), ("Check", ("p1", "a1")),
        ("Revoke", "a1"), ("Publish", "p1")]


# ---- TLA+ output ----

def tla_value(v):
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, tuple):
        return "<<%s>>" % ", ".join(tla_value(x) for x in v)
    if isinstance(v, dict):
        return "(%s)" % " @@ ".join(
            "%s :> %s" % (tla_value(k), tla_value(x)) for k, x in sorted(v.items()))
    raise TypeError(type(v))


def tla_state(s):
    return "[%s]" % ", ".join("%s |-> %s" % (k, tla_value(s[k]))
                              for k in ("verified", "approved", "published", "pending"))


def write_trace(out_dir, initial, steps):
    elems = ['[op |-> <<"Init", "none">>, state |-> %s]' % tla_state(initial)]
    elems += ["[op |-> %s, state |-> %s]" % (tla_value(op), tla_state(s))
              for op, s in steps]
    body = ",\n    ".join(elems)
    text = ("---- MODULE TraceData ----\nEXTENDS TLC\n"
            "\\* Generated by impl/publish_service.py. Do not edit.\n"
            "Trace == <<\n    %s\n>>\n====\n" % body)
    with open(os.path.join(out_dir, "TraceData.tla"), "w", encoding="utf-8") as f:
        f.write(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", choices=["random", "race"])
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--steps", type=int, default=60)
    ap.add_argument("--out", required=True)
    ap.add_argument("--defect", choices=["no-recheck"])
    args = ap.parse_args()
    if args.scenario == "random":
        rounds = random_rounds(args.seed, args.steps)
    else:
        rounds = [[op] for op in RACE]
    initial, steps = run(rounds, recheck=args.defect != "no-recheck")
    write_trace(args.out, initial, steps)
    print("trace: %d accepted operations" % len(steps))


if __name__ == "__main__":
    main()
