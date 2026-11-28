"""A correct implementation of the fictional expense API (single process, in memory).

Written by the "implementer". The acceptance tests never read values from here.
"""

from api import (
    ACCOUNTANT,
    APPROVER,
    Conflict,
    Forbidden,
    Invalid,
    NotFound,
)

MIN_AMOUNT = 1
MAX_AMOUNT = 1_000_000


class ExpenseService:
    def __init__(self, gateway):
        self._gateway = gateway
        self._expenses = {}
        self._payments = {}  # expense_id -> payment
        self._keys = {}  # idempotency key -> expense_id
        self._next = 0

    def submit(self, actor, amount):
        if type(amount) is not int or not MIN_AMOUNT <= amount <= MAX_AMOUNT:
            raise Invalid("amount")
        self._next += 1
        expense_id = "E%d" % self._next
        self._expenses[expense_id] = {
            "id": expense_id,
            "org_id": actor.org_id,
            "owner": actor.user_id,
            "amount": amount,
            "status": "submitted",
        }
        return expense_id

    def _visible(self, actor, expense_id):
        expense = self._expenses.get(expense_id)
        if expense is None or expense["org_id"] != actor.org_id:
            raise NotFound(expense_id)
        if expense["owner"] != actor.user_id and actor.role not in (APPROVER, ACCOUNTANT):
            raise NotFound(expense_id)
        return expense

    def get(self, actor, expense_id):
        return dict(self._visible(actor, expense_id))

    def approve(self, actor, expense_id):
        expense = self._visible(actor, expense_id)
        if actor.role != APPROVER or expense["owner"] == actor.user_id:
            raise Forbidden(expense_id)
        if expense["status"] != "submitted":
            raise Invalid("status")
        expense["status"] = "approved"

    def pay(self, actor, expense_id, idempotency_key):
        expense = self._visible(actor, expense_id)
        if actor.role != ACCOUNTANT:
            raise Forbidden(expense_id)
        used_for = self._keys.get(idempotency_key)
        if used_for is not None and used_for != expense_id:
            raise Conflict(idempotency_key)
        if expense_id in self._payments:
            return dict(self._payments[expense_id])
        if expense["status"] != "approved":
            raise Invalid("status")
        # The transfer runs before any state change, so a GatewayError leaves nothing behind (R-5).
        transfer_id = self._gateway.transfer(expense_id, expense["amount"])
        payment = {"expense_id": expense_id, "amount": expense["amount"], "transfer_id": transfer_id}
        self._payments[expense_id] = payment
        self._keys[idempotency_key] = expense_id
        expense["status"] = "paid"
        return dict(payment)

    def payouts(self):
        return [dict(p) for p in self._payments.values()]


def make_service(gateway):
    return ExpenseService(gateway)
