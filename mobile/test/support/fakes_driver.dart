import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/availability.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/driver.dart';
import 'package:ff_garage/data/models/driver_job.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/repositories/admin_booking_repository.dart';
import 'package:ff_garage/data/repositories/admin_driver_repository.dart';
import 'package:ff_garage/data/repositories/driver_work_repository.dart';

import 'fakes_booking.dart';

const ApiException notFoundError = ApiException(
  type: ApiErrorType.notFound,
  message: 'Booking not found',
  statusCode: 404,
);

const ApiException conflictError = ApiException(
  type: ApiErrorType.conflict,
  message: 'That driver already has a visit at that time',
  statusCode: 409,
);

DriverAccount driverAccount({
  String id = 'd1',
  String loginId = 'ravi01',
  String? name = 'Ravi Kumar',
  String? phone = '+919876500001',
  bool active = true,
  int open = 0,
}) =>
    DriverAccount(
      id: id,
      loginId: loginId,
      fullName: name,
      phone: phone,
      isActive: active,
      openBookings: open,
      createdAt: DateTime(2026, 10, 1),
    );

AdminAssignment assignmentFor(
  DriverAccount driver, {
  bool? driverIsActive,
}) =>
    AdminAssignment(
      driverId: driver.id,
      driverName: driver.fullName,
      driverLoginId: driver.loginId,
      driverPhone: driver.phone,
      driverIsActive: driverIsActive ?? driver.isActive,
      assignedAt: DateTime(2026, 10, 19, 10),
    );

DriverJob driverJob({
  String id = 'b1',
  int number = 1,
  BookingStatus status = BookingStatus.assigned,
  BookingStatus? next = BookingStatus.onTheWay,
}) =>
    DriverJob(
      id: id,
      code: 'FF-${number.toString().padLeft(6, '0')}',
      status: status,
      vehicleType: VehicleType.scooter,
      serviceName: 'General Service',
      packageName: 'Basic',
      inclusions: const ['Wash'],
      customerName: 'Test User',
      customerPhone: '+919876543210',
      addressLine: '12 MG Road',
      city: 'Bengaluru',
      pincode: '560001',
      date: DateTime(2026, 10, 21),
      slotStart: const ClockTime(9, 0),
      slotEnd: const ClockTime(11, 0),
      charges: const [],
      nextStatus: next,
    );

/// In-memory drivers. Set [error] to fail every call.
class FakeAdminDriverRepository implements AdminDriverRepository {
  FakeAdminDriverRepository({List<DriverAccount>? drivers})
      : drivers = drivers ?? [];

  List<DriverAccount> drivers;
  ApiException? error;
  ApiException? createError;
  final List<Map<String, dynamic>> created = [];
  final List<({String id, Map<String, dynamic> changes})> updates = [];
  final List<({String id, String password})> resets = [];

  void _check([ApiException? specific]) {
    if (error != null) throw error!;
    if (specific != null) throw specific;
  }

  @override
  Future<List<DriverAccount>> list() async {
    _check();
    return List.of(drivers);
  }

  @override
  Future<DriverAccount> get(String id) async {
    _check();
    return drivers.firstWhere((d) => d.id == id, orElse: () => throw notFoundError);
  }

  @override
  Future<DriverAccount> create({
    required String driverId,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    created.add({
      'driver_id': driverId,
      'password': password,
      'full_name': fullName,
      'phone': phone,
    });
    _check(createError);
    final driver = driverAccount(
      id: 'new-${created.length}',
      loginId: driverId,
      name: fullName,
      phone: phone,
    );
    drivers = [...drivers, driver];
    return driver;
  }

  @override
  Future<DriverAccount> update(String id, Map<String, dynamic> changes) async {
    updates.add((id: id, changes: changes));
    _check();
    final old = await get(id);
    final next = driverAccount(
      id: old.id,
      loginId: old.loginId,
      name: (changes['full_name'] as String?) ?? old.fullName,
      phone: (changes['phone'] as String?) ?? old.phone,
      active: (changes['is_active'] as bool?) ?? old.isActive,
      open: old.openBookings,
    );
    drivers = [for (final d in drivers) d.id == id ? next : d];
    return next;
  }

  @override
  Future<void> resetPassword(String id, String newPassword) async {
    resets.add((id: id, password: newPassword));
    _check();
  }
}

/// In-memory admin bookings with the same assignment rules the server applies
/// (paid, assignable status, no repeat of the same driver).
class FakeAdminBookingRepository implements AdminBookingRepository {
  FakeAdminBookingRepository({List<Booking>? bookings, List<DriverAccount>? drivers})
      : bookings = bookings ?? [],
        drivers = drivers ?? [];

  List<Booking> bookings;
  List<DriverAccount> drivers;
  ApiException? error;
  ApiException? assignError;
  final List<({String bookingId, String driverId})> assigns = [];
  final List<String> unassigns = [];
  final List<({List<BookingStatus>? statuses, String? query, int offset})> lists = [];

  void _check([ApiException? specific]) {
    if (error != null) throw error!;
    if (specific != null) throw specific;
  }

  Booking _find(String id) =>
      bookings.firstWhere((b) => b.id == id, orElse: () => throw notFoundError);

  void _replace(Booking next) {
    bookings = [for (final b in bookings) b.id == next.id ? next : b];
  }

  @override
  Future<BookingPage> list({
    List<BookingStatus>? statuses,
    String? query,
    int limit = 25,
    int offset = 0,
  }) async {
    lists.add((statuses: statuses, query: query, offset: offset));
    _check();
    final text = query?.trim().toLowerCase() ?? '';
    final matching = bookings.where((b) {
      if (statuses != null && !statuses.contains(b.status)) return false;
      if (text.isEmpty) return true;
      return b.code.toLowerCase().contains(text) ||
          b.customerName.toLowerCase().contains(text);
    }).toList();
    return BookingPage(
      items: matching.skip(offset).take(limit).toList(),
      total: matching.length,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<Booking> get(String id) async {
    _check();
    return _find(id);
  }

  @override
  Future<Booking> assign(String bookingId, String driverId) async {
    assigns.add((bookingId: bookingId, driverId: driverId));
    _check(assignError);
    final old = _find(bookingId);
    final driver = drivers.firstWhere((d) => d.id == driverId);
    final status = old.status == BookingStatus.confirmed
        ? BookingStatus.assigned
        : old.status;
    final next = booking(
      id: old.id,
      number: old.number,
      status: status,
      isPaid: true,
      assignment: assignmentFor(driver),
      canAssign: true,
      canUnassign: status == BookingStatus.assigned,
    );
    _replace(next);
    return next;
  }

  @override
  Future<Booking> unassign(String bookingId) async {
    unassigns.add(bookingId);
    _check();
    final old = _find(bookingId);
    final next = booking(
      id: old.id,
      number: old.number,
      status: BookingStatus.confirmed,
      isPaid: true,
      canAssign: true,
    );
    _replace(next);
    return next;
  }

  @override
  Future<List<AssignmentHistoryItem>> history(String bookingId) async {
    _check();
    final current = _find(bookingId).assignment;
    return [
      if (current != null)
        AssignmentHistoryItem(
          id: 'h-${current.driverId}',
          driverId: current.driverId,
          driverName: current.driverName,
          driverLoginId: current.driverLoginId,
          assignedAt: current.assignedAt,
          isActive: true,
        ),
    ];
  }

  @override
  Future<BookingPage> driverBookings(
    String driverId, {
    String scope = 'open',
    int limit = 25,
    int offset = 0,
  }) async {
    _check();
    final mine = bookings.where((b) => b.assignment?.driverId == driverId).toList();
    return BookingPage(
      items: mine,
      total: mine.length,
      limit: limit,
      offset: offset,
    );
  }
}

/// The signed-in driver's jobs. [updateError] fails the next status change.
class FakeDriverWorkRepository implements DriverWorkRepository {
  FakeDriverWorkRepository({List<DriverJob>? jobs}) : jobs = jobs ?? [];

  List<DriverJob> jobs;
  ApiException? error;
  ApiException? updateError;
  final List<String> scopes = [];
  final List<({String id, BookingStatus status})> updates = [];

  void _check([ApiException? specific]) {
    if (error != null) throw error!;
    if (specific != null) throw specific;
  }

  static const _open = {
    BookingStatus.assigned,
    BookingStatus.onTheWay,
    BookingStatus.inProgress,
  };

  @override
  Future<DriverJobPage> list({
    String scope = 'open',
    int limit = 25,
    int offset = 0,
  }) async {
    scopes.add(scope);
    _check();
    final matching = jobs.where((j) => (scope == 'open') == _open.contains(j.status)).toList();
    return DriverJobPage(
      items: matching.skip(offset).take(limit).toList(),
      total: matching.length,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<DriverJob> get(String id) async {
    _check();
    return jobs.firstWhere((j) => j.id == id, orElse: () => throw notFoundError);
  }

  @override
  Future<DriverJob> updateStatus(String id, BookingStatus status) async {
    updates.add((id: id, status: status));
    _check(updateError);
    final old = await get(id);
    final next = driverJob(
      id: old.id,
      status: status,
      next: switch (status) {
        BookingStatus.onTheWay => BookingStatus.inProgress,
        BookingStatus.inProgress => BookingStatus.completed,
        _ => null,
      },
    );
    jobs = [for (final j in jobs) j.id == id ? next : j];
    return next;
  }
}
