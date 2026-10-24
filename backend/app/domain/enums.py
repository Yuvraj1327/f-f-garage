"""Python mirrors of the PostgreSQL enum types.

The values must match `supabase/migrations/*.sql` and
`mobile/lib/data/models/enums.dart`. `tests/test_schema_consistency.py`
enforces this, so change all three together.
"""

from enum import StrEnum


class UserRole(StrEnum):
    CUSTOMER = "customer"
    DRIVER = "driver"
    ADMIN = "admin"


class VehicleType(StrEnum):
    BIKE = "bike"
    SCOOTER = "scooter"


class ExtraChargeType(StrEnum):
    SPARE_PART = "spare_part"
    ENGINE_OIL = "engine_oil"
    OTHER = "other"


class BookingStatus(StrEnum):
    PENDING_PAYMENT = "pending_payment"
    CONFIRMED = "confirmed"
    ASSIGNED = "assigned"
    ON_THE_WAY = "on_the_way"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class PaymentStatus(StrEnum):
    PENDING = "pending"
    SUCCESSFUL = "successful"
    FAILED = "failed"
    CANCELLED = "cancelled"
