/// Dart mirrors of the PostgreSQL enumerated types.
///
/// Values must match `supabase/migrations/*.sql` and
/// `backend/app/domain/enums.py`. `backend/tests/test_schema_consistency.py`
/// fails if they drift apart, so change all three together. Keep each value on
/// its own line in the form `name('api_value')`; that test reads this file.
abstract interface class ApiEnum {
  /// The exact string used by the database and the REST API.
  String get apiValue;
}

/// Finds the member of [values] whose `apiValue` equals [raw].
T parseApiEnum<T extends ApiEnum>(List<T> values, String raw) {
  for (final value in values) {
    if (value.apiValue == raw) {
      return value;
    }
  }
  throw FormatException('Unknown $T value: $raw');
}

enum UserRole implements ApiEnum {
  customer('customer'),
  driver('driver'),
  admin('admin');

  const UserRole(this.apiValue);

  @override
  final String apiValue;

  static UserRole fromApiValue(String raw) => parseApiEnum(values, raw);
}

enum VehicleType implements ApiEnum {
  bike('bike'),
  scooter('scooter');

  const VehicleType(this.apiValue);

  @override
  final String apiValue;

  static VehicleType fromApiValue(String raw) => parseApiEnum(values, raw);
}

enum ExtraChargeType implements ApiEnum {
  sparePart('spare_part'),
  engineOil('engine_oil'),
  other('other');

  const ExtraChargeType(this.apiValue);

  @override
  final String apiValue;

  static ExtraChargeType fromApiValue(String raw) =>
      parseApiEnum(values, raw);
}

/// The four tabs of the customer's service screen.
enum CatalogTab implements ApiEnum {
  mechanic('mechanic', 'Book a Mechanic'),
  package('package', 'Service Packages'),
  repair('repair', 'Specific Repair'),
  engine('engine', 'Engine Repair');

  const CatalogTab(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static CatalogTab fromApiValue(String raw) => parseApiEnum(values, raw);
}

/// Whether spare parts are in the price.
enum PartsPolicy implements ApiEnum {
  serviceOnly('service_only', 'Labour only. Parts are extra and need your approval.'),
  partsIncluded('parts_included', 'Parts included in the price.'),
  partsExtra('parts_extra', 'Parts are charged extra, after your approval.');

  const PartsPolicy(this.apiValue, this.description);

  @override
  final String apiValue;
  final String description;

  static PartsPolicy fromApiValue(String raw) => parseApiEnum(values, raw);
}

/// An extra charge request: it is only billed once the customer approves it.
enum ExtraStatus implements ApiEnum {
  proposed('proposed', 'Waiting for you'),
  approved('approved', 'Approved'),
  declined('declined', 'Declined'),
  withdrawn('withdrawn', 'Withdrawn');

  const ExtraStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static ExtraStatus fromApiValue(String raw) => parseApiEnum(values, raw);
}

enum BookingStatus implements ApiEnum {
  pendingPayment('pending_payment'),
  confirmed('confirmed'),
  assigned('assigned'),
  onTheWay('on_the_way'),
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled');

  const BookingStatus(this.apiValue);

  @override
  final String apiValue;

  static BookingStatus fromApiValue(String raw) => parseApiEnum(values, raw);
}

enum PaymentStatus implements ApiEnum {
  pending('pending'),
  successful('successful'),
  failed('failed'),
  cancelled('cancelled');

  const PaymentStatus(this.apiValue);

  @override
  final String apiValue;

  static PaymentStatus fromApiValue(String raw) => parseApiEnum(values, raw);
}

/// Which part of the bill a payment settles.
enum PaymentKind implements ApiEnum {
  advance('advance', 'Advance'),
  balance('balance', 'Balance');

  const PaymentKind(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static PaymentKind fromApiValue(String raw) => parseApiEnum(values, raw);
}
