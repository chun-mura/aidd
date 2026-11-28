"""Two deliberately wrong implementations, each one plausible-looking change away from impl_correct.

The acceptance tests must fail on each of them, and only on the criteria the defect breaks
(tests/assurance/acceptance-test.sh checks the exact set).
"""

from api import ACCOUNTANT, APPROVER, Forbidden, Invalid, NotFound
from impl_correct import ExpenseService


class CrossTenantService(ExpenseService):
    """Defect: approvers and accountants see every organization (missing tenant check)."""

    def _visible(self, actor, expense_id):
        expense = self._expenses.get(expense_id)
        if expense is None:
            raise NotFound(expense_id)
        if expense["owner"] != actor.user_id and actor.role not in (APPROVER, ACCOUNTANT):
            raise NotFound(expense_id)
        return expense


class DoublePayService(ExpenseService):
    """Defect: every pay call transfers again; the idempotency key and the paid state are ignored."""

    def pay(self, actor, expense_id, idempotency_key):
        expense = self._visible(actor, expense_id)
        if actor.role != ACCOUNTANT:
            raise Forbidden(expense_id)
        if expense["status"] not in ("approved", "paid"):
            raise Invalid("status")
        transfer_id = self._gateway.transfer(expense_id, expense["amount"])
        payment = {"expense_id": expense_id, "amount": expense["amount"], "transfer_id": transfer_id}
        self._payments[expense_id] = payment
        expense["status"] = "paid"
        return dict(payment)


def make_cross_tenant(gateway):
    return CrossTenantService(gateway)


def make_double_pay(gateway):
    return DoublePayService(gateway)
