"""Money rules for a booking: the advance, coupon discounts and the final balance.

Pure functions, no I/O. All amounts are `Decimal` rupees with two places.

  estimated total = package price + add-ons chosen when booking - coupon discount
  advance         = `advance_percent` of the estimated total, collected when booking
  final bill      = estimated total + extra charges the customer approved
  balance         = final bill - everything already paid (collected after the service)

Example: estimated 1000, advance 200, approved extras 200 -> final 1200, balance 1000.
"""

from decimal import ROUND_HALF_UP, Decimal

CENT = Decimal("0.01")
ZERO = Decimal("0.00")
_HUNDRED = Decimal(100)


def money(value: Decimal | int | str) -> Decimal:
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


def advance_for(total: Decimal, percent: Decimal) -> Decimal:
    """The advance for an estimated `total`, rounded to the paisa and never above the total."""
    return min(money(total * percent / _HUNDRED), money(total))


def advance_due(advance_amount: Decimal, total: Decimal) -> Decimal:
    """What is collected when booking. Bookings made before the advance rule existed carry
    an advance of 0 and were paid in full up front, so for them the whole total is due."""
    return advance_amount if advance_amount > 0 else total


def percent_discount(subtotal: Decimal, percent: Decimal, cap: Decimal | None) -> Decimal:
    discount = money(subtotal * percent / _HUNDRED)
    if cap is not None:
        discount = min(discount, money(cap))
    return min(discount, money(subtotal))


def flat_discount(subtotal: Decimal, amount: Decimal) -> Decimal:
    return min(money(amount), money(subtotal))


def balance_remaining(final_total: Decimal, paid: Decimal) -> Decimal:
    """What is still to pay, never negative."""
    return max(money(final_total) - money(paid), ZERO)
