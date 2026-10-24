"""Booking statuses, transitions and the cancellation/change rules.

Pure functions, no I/O, so every rule is unit-tested. The transition table mirrors
`public.booking_status_transition_allowed` in migration 8 (the database enforces it
too); `tests/test_booking_rules.py` checks the two cannot drift apart.

Lifecycle:  pending_payment -> confirmed -> assigned -> on_the_way -> in_progress
            -> completed,   with `cancelled` reachable from any non-final state.
Phase 4 sets pending_payment (on creation), confirmed and cancelled. Verified payments
(Phase 5) confirm bookings; admins assign drivers (confirmed -> assigned) and drivers move
their own bookings through on_the_way, in_progress and completed (Phase 6). The driver
steps mirror `public.driver_update_status` in migration 10; `tests/test_driver_rules.py`
checks the two cannot drift apart.
"""

from datetime import datetime, timedelta

from app.domain.enums import BookingStatus

S = BookingStatus

TRANSITIONS: dict[BookingStatus, frozenset[BookingStatus]] = {
    S.PENDING_PAYMENT: frozenset({S.CONFIRMED, S.CANCELLED}),
    S.CONFIRMED: frozenset({S.ASSIGNED, S.CANCELLED}),
    S.ASSIGNED: frozenset({S.CONFIRMED, S.ON_THE_WAY, S.CANCELLED}),
    S.ON_THE_WAY: frozenset({S.IN_PROGRESS, S.CANCELLED}),
    S.IN_PROGRESS: frozenset({S.COMPLETED, S.CANCELLED}),
    S.COMPLETED: frozenset(),
    S.CANCELLED: frozenset(),
}

FINAL_STATUSES = frozenset({S.COMPLETED, S.CANCELLED})

# Statuses that hold a place in a time slot.
ACTIVE_STATUSES = frozenset(set(S) - {S.CANCELLED})

# What an admin may set by hand. Confirming is NOT here: a booking is confirmed only by a
# payment the backend has verified (Phase 5). The driver steps come with the driver workflow.
ADMIN_MANUAL_TARGETS = frozenset({S.CANCELLED})

# The only steps a driver may take, each from exactly one status (never backwards, never
# skipping one, never cancelling).
DRIVER_STEPS: dict[BookingStatus, BookingStatus] = {
    S.ASSIGNED: S.ON_THE_WAY,
    S.ON_THE_WAY: S.IN_PROGRESS,
    S.IN_PROGRESS: S.COMPLETED,
}
DRIVER_TARGETS = frozenset(DRIVER_STEPS.values())

# Statuses in which a driver has work to do, and in which an admin may still change driver.
DRIVER_OPEN_STATUSES = frozenset(DRIVER_STEPS)
ADMIN_ASSIGNABLE_STATUSES = frozenset({S.CONFIRMED, S.ASSIGNED, S.ON_THE_WAY})

# A customer may change the address, notes or date/slot only before a driver is assigned.
CUSTOMER_EDITABLE_STATUSES = frozenset({S.PENDING_PAYMENT, S.CONFIRMED})

# A customer may cancel until the driver is on the way.
CUSTOMER_CANCELLABLE_STATUSES = frozenset({S.PENDING_PAYMENT, S.CONFIRMED, S.ASSIGNED})


def can_transition(current: BookingStatus, target: BookingStatus) -> bool:
    return target in TRANSITIONS[current]


def admin_next_statuses(current: BookingStatus) -> list[BookingStatus]:
    """The manual status changes an admin may make from `current` right now."""
    return sorted(TRANSITIONS[current] & ADMIN_MANUAL_TARGETS)


def driver_next_status(current: BookingStatus) -> BookingStatus | None:
    """The one step the driver may take now, or None."""
    return DRIVER_STEPS.get(current)


def booking_code(booking_number: int) -> str:
    """The reference customers quote, e.g. FF-000123."""
    return f"FF-{booking_number:06d}"


def customer_cancel_block(
    status: BookingStatus, slot_start: datetime, now: datetime, cutoff_hours: int
) -> str | None:
    """None when the customer may cancel, otherwise the reason they may not."""
    if status == S.CANCELLED:
        return "This booking is already cancelled"
    if status == S.COMPLETED:
        return "This booking is already completed"
    if status not in CUSTOMER_CANCELLABLE_STATUSES:
        return "The driver is already on the way, so this booking can no longer be cancelled online"
    if status != S.PENDING_PAYMENT and now > slot_start - timedelta(hours=cutoff_hours):
        return (
            f"Bookings can be cancelled online until {cutoff_hours} hour(s) before the visit. "
            "Please contact us."
        )
    return None


def customer_edit_block(
    status: BookingStatus, slot_start: datetime, now: datetime, cutoff_hours: int
) -> str | None:
    """None when the customer may change address/notes/schedule, otherwise why not."""
    if status not in CUSTOMER_EDITABLE_STATUSES:
        return "This booking can no longer be changed"
    if now > slot_start - timedelta(hours=cutoff_hours):
        return (
            f"Bookings can be changed until {cutoff_hours} hour(s) before the visit. "
            "Please contact us."
        )
    return None
