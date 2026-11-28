"""Interface of the fictional expense API (part of the acceptance criteria, not of an implementation).

The acceptance tests and every implementation import only this module from each other.
An implementation module exposes make_service(gateway) returning an object with
submit / get / approve / pay / payouts (see criteria.md, section "API").
"""

from dataclasses import dataclass

MEMBER = "member"
APPROVER = "approver"
ACCOUNTANT = "accountant"


@dataclass(frozen=True)
class Actor:
    """An already authenticated user (authentication is out of scope, X-1)."""

    user_id: str
    org_id: str
    role: str


class Invalid(Exception):
    """The input breaks a business rule (amount range, state order)."""


class Forbidden(Exception):
    """The actor may see the expense but may not perform this operation."""


class NotFound(Exception):
    """No such expense for this actor (also used for other organizations, D-1)."""


class Conflict(Exception):
    """The idempotency key was already used for another expense (D-3)."""


class GatewayError(Exception):
    """The transfer to the payee failed (R-5)."""
