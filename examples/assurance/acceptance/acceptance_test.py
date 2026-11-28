"""Acceptance tests for the fictional expense API, one function per row of criteria.md.

Expected values come from requirements.md / criteria.md, never from an implementation.
The implementation is loaded by name, so this file imports nothing but api from it.

Usage: python3 acceptance_test.py [--impl module:factory] [--json] [--list]
Exit 0 only when every criterion passes.
"""

import argparse
import importlib
import json
import random
import sys
import traceback

from api import (
    ACCOUNTANT,
    APPROVER,
    MEMBER,
    Actor,
    Conflict,
    Forbidden,
    GatewayError,
    Invalid,
    NotFound,
)

# Fixed seeds: a property row is a finite sample, reproducible from the seed in a failure message.
PROPERTY_SEEDS = range(30)
PROPERTY_STEPS = 80

CRITERIA = {}


def criterion(criterion_id):
    def register(func):
        CRITERIA[criterion_id] = func
        return func

    return register


class FakeGateway:
    """Counts successful transfers outside the implementation; fail_next makes the next N calls fail."""

    def __init__(self, rng=None, failure_rate=0.0):
        self.transfers = []
        self.fail_next = 0
        self._rng = rng
        self._failure_rate = failure_rate

    def transfer(self, expense_id, amount):
        if self.fail_next > 0:
            self.fail_next -= 1
            raise GatewayError(expense_id)
        if self._rng is not None and self._rng.random() < self._failure_rate:
            raise GatewayError(expense_id)
        self.transfers.append((expense_id, amount))
        return "T%d" % len(self.transfers)

    def count(self, expense_id):
        return sum(1 for e, _ in self.transfers if e == expense_id)


def people(org):
    return {
        "m1": Actor("%s-m1" % org, org, MEMBER),
        "m2": Actor("%s-m2" % org, org, MEMBER),
        "a1": Actor("%s-a1" % org, org, APPROVER),
        "c1": Actor("%s-c1" % org, org, ACCOUNTANT),
    }


ORG1 = people("org1")
ORG2 = people("org2")


def expect_raises(exc_type, func, *args):
    try:
        func(*args)
    except exc_type:
        return
    except Exception as other:  # a different exception is a failed criterion, not a crash
        raise AssertionError("expected %s, got %r" % (exc_type.__name__, other))
    raise AssertionError("expected %s, nothing was raised" % exc_type.__name__)


def approved_expense(svc, amount=5000):
    expense_id = svc.submit(ORG1["m1"], amount)
    svc.approve(ORG1["a1"], expense_id)
    return expense_id


@criterion("AT-FLOW-01")
def flow_01(make):
    gw = FakeGateway()
    svc = make(gw)
    e = svc.submit(ORG1["m1"], 5000)
    assert svc.get(ORG1["m1"], e)["status"] == "submitted"
    svc.approve(ORG1["a1"], e)
    assert svc.get(ORG1["m1"], e)["status"] == "approved"
    payment = svc.pay(ORG1["c1"], e, "k1")
    assert payment["amount"] == 5000, payment
    assert svc.get(ORG1["m1"], e)["status"] == "paid"
    assert gw.transfers == [(e, 5000)], gw.transfers


@criterion("AT-FLOW-02")
def flow_02(make):
    gw = FakeGateway()
    svc = make(gw)
    e = svc.submit(ORG1["m1"], 5000)
    expect_raises(Invalid, svc.pay, ORG1["c1"], e, "k1")
    assert gw.transfers == []
    assert svc.get(ORG1["m1"], e)["status"] == "submitted"


@criterion("AT-AMT-01")
def amount_01(make):
    svc = make(FakeGateway())
    for ok in (1, 1_000_000):
        e = svc.submit(ORG1["m1"], ok)
        assert svc.get(ORG1["m1"], e)["amount"] == ok
    for bad in (0, -1, 1_000_001, 1.5, "100", True):
        expect_raises(Invalid, svc.submit, ORG1["m1"], bad)


@criterion("AT-AUTHZ-01")
def authz_01(make):
    svc = make(FakeGateway())
    e = svc.submit(ORG1["m1"], 5000)
    for who in ("m1", "a1", "c1"):
        expect_raises(NotFound, svc.get, ORG2[who], e)
    expect_raises(NotFound, svc.get, ORG1["a1"], "no-such-id")


@criterion("AT-AUTHZ-02")
def authz_02(make):
    svc = make(FakeGateway())
    e = svc.submit(ORG1["m1"], 5000)
    expect_raises(NotFound, svc.get, ORG1["m2"], e)


@criterion("AT-AUTHZ-03")
def authz_03(make):
    svc = make(FakeGateway())
    e = svc.submit(ORG1["m1"], 5000)
    expect_raises(NotFound, svc.approve, ORG2["a1"], e)
    assert svc.get(ORG1["m1"], e)["status"] == "submitted"


@criterion("AT-AUTHZ-04")
def authz_04(make):
    svc = make(FakeGateway())
    own = svc.submit(ORG1["a1"], 5000)
    expect_raises(Forbidden, svc.approve, ORG1["a1"], own)
    assert svc.get(ORG1["a1"], own)["status"] == "submitted"
    mine = svc.submit(ORG1["m1"], 5000)
    expect_raises(Forbidden, svc.approve, ORG1["m1"], mine)
    assert svc.get(ORG1["m1"], mine)["status"] == "submitted"


@criterion("AT-AUTHZ-05")
def authz_05(make):
    gw = FakeGateway()
    svc = make(gw)
    e = approved_expense(svc)
    expect_raises(NotFound, svc.pay, ORG2["c1"], e, "k1")
    expect_raises(Forbidden, svc.pay, ORG1["a1"], e, "k2")
    assert gw.transfers == []


def random_amount(rng):
    return rng.randint(1, 1_000_000)


@criterion("AT-AUTHZ-P")
def authz_property(make):
    everyone = list(ORG1.values()) + list(ORG2.values())
    for seed in PROPERTY_SEEDS:
        rng = random.Random(seed)
        gw = FakeGateway()
        svc = make(gw)
        org_of = {}
        for step in range(PROPERTY_STEPS):
            actor = rng.choice(everyone)
            if not org_of or rng.random() < 0.3:
                org_of[svc.submit(actor, random_amount(rng))] = actor.org_id
                continue
            e = rng.choice(sorted(org_of))
            op = rng.choice(("get", "approve", "pay"))
            before = (len(gw.transfers), svc_status(svc, e, org_of[e]))
            try:
                if op == "get":
                    svc.get(actor, e)
                elif op == "approve":
                    svc.approve(actor, e)
                else:
                    svc.pay(actor, e, "k%d" % rng.randint(0, 5))
                outcome = "ok"
            except (NotFound, Forbidden, Invalid, Conflict) as exc:
                outcome = type(exc).__name__
            if actor.org_id != org_of[e]:
                after = (len(gw.transfers), svc_status(svc, e, org_of[e]))
                assert outcome == "NotFound" and after == before, (
                    "seed=%d step=%d: %s by %s on %s of %s gave %s, state %s -> %s"
                    % (seed, step, op, actor.user_id, e, org_of[e], outcome, before, after)
                )


def svc_status(svc, expense_id, org_id):
    """Read the status as the organization's own approver, who may see it under R-3."""
    return svc.get(Actor("%s-a1" % org_id, org_id, APPROVER), expense_id)["status"]


@criterion("AT-PAY-01")
def pay_01(make):
    gw = FakeGateway()
    svc = make(gw)
    e = approved_expense(svc)
    first = svc.pay(ORG1["c1"], e, "k1")
    second = svc.pay(ORG1["c1"], e, "k1")
    assert (first["amount"], first["transfer_id"]) == (second["amount"], second["transfer_id"]), (first, second)
    assert gw.count(e) == 1, gw.transfers


@criterion("AT-PAY-02")
def pay_02(make):
    gw = FakeGateway()
    svc = make(gw)
    e = approved_expense(svc)
    first = svc.pay(ORG1["c1"], e, "k1")
    again = svc.pay(ORG1["c1"], e, "k2")
    assert again["transfer_id"] == first["transfer_id"], (first, again)
    assert gw.count(e) == 1, gw.transfers


@criterion("AT-PAY-03")
def pay_03(make):
    gw = FakeGateway()
    svc = make(gw)
    e1 = approved_expense(svc)
    e2 = approved_expense(svc)
    svc.pay(ORG1["c1"], e1, "k1")
    expect_raises(Conflict, svc.pay, ORG1["c1"], e2, "k1")
    assert svc.get(ORG1["m1"], e2)["status"] == "approved"
    assert len(gw.transfers) == 1, gw.transfers


@criterion("AT-PAY-P")
def pay_property(make):
    for seed in PROPERTY_SEEDS:
        rng = random.Random(seed)
        gw = FakeGateway(rng=rng, failure_rate=0.2)
        svc = make(gw)
        expenses = [approved_expense(svc, random_amount(rng)) for _ in range(rng.randint(1, 6))]
        last_key = {}
        for step in range(PROPERTY_STEPS):
            e = rng.choice(expenses)
            # Resend the previous key (a retry) or start with a fresh one (a second click).
            key = last_key.get(e) if e in last_key and rng.random() < 0.5 else "%s-s%d" % (e, step)
            last_key[e] = key
            try:
                svc.pay(ORG1["c1"], e, key)
            except GatewayError:
                pass
            context = "seed=%d step=%d" % (seed, step)
            for x in expenses:
                assert gw.count(x) <= 1, "%s: %s transferred %d times" % (context, x, gw.count(x))
                paid = svc.get(ORG1["m1"], x)["status"] == "paid"
                assert paid == (gw.count(x) == 1), "%s: %s status/transfer mismatch" % (context, x)
            recorded = sorted((p["expense_id"], p["amount"]) for p in svc.payouts())
            assert recorded == sorted(gw.transfers), "%s: payouts() %s != transfers %s" % (
                context,
                recorded,
                gw.transfers,
            )


@criterion("AT-FAULT-01")
def fault_01(make):
    gw = FakeGateway()
    svc = make(gw)
    e = approved_expense(svc)
    gw.fail_next = 1
    expect_raises(GatewayError, svc.pay, ORG1["c1"], e, "k1")
    assert svc.get(ORG1["m1"], e)["status"] == "approved"
    assert svc.payouts() == []
    svc.pay(ORG1["c1"], e, "k1")
    assert svc.get(ORG1["m1"], e)["status"] == "paid"
    assert gw.count(e) == 1, gw.transfers


def load(spec):
    module_name, _, factory = spec.partition(":")
    return getattr(importlib.import_module(module_name), factory or "make_service")


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--impl", default="impl_correct:make_service")
    parser.add_argument("--json", action="store_true", help="print one JSON object instead of lines")
    parser.add_argument("--list", action="store_true", help="print the criterion IDs and exit")
    args = parser.parse_args(argv)
    if args.list:
        print("\n".join(CRITERIA))
        return 0
    make = load(args.impl)
    passed, failed = [], {}
    for criterion_id, func in CRITERIA.items():
        try:
            func(make)
            passed.append(criterion_id)
        except Exception:
            failed[criterion_id] = traceback.format_exc(limit=1).strip().splitlines()[-1]
    if args.json:
        print(json.dumps({"impl": args.impl, "passed": passed, "failed": sorted(failed)}))
    else:
        for criterion_id in CRITERIA:
            print("%s %s %s" % ("FAIL" if criterion_id in failed else "ok  ", criterion_id, failed.get(criterion_id, "")))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
