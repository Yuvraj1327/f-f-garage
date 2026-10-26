import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/vehicle.dart';
import 'package:ff_garage/data/repositories/vehicle_repository.dart';

Vehicle vehicle({
  String id = 'v1',
  VehicleType type = VehicleType.scooter,
  String registration = 'MH12AB1234',
  String make = 'TVS',
  String model = 'Jupiter',
  String? nickname,
}) =>
    Vehicle(
      id: id,
      type: type,
      registration: registration,
      make: make,
      model: model,
      nickname: nickname,
    );

/// Stands in for `/vehicles`: an in-memory list that behaves like the server
/// (duplicate registrations are refused). Set [error] to make calls fail.
class FakeVehicleRepository implements VehicleRepository {
  FakeVehicleRepository([List<Vehicle>? initial]) : items = [...?initial];

  final List<Vehicle> items;
  ApiException? error;
  int _next = 100;
  int lists = 0;

  void _check() {
    if (error != null) throw error!;
  }

  void _unique(String registration, String? ignoreId) {
    if (items.any((v) => v.registration == registration && v.id != ignoreId)) {
      throw const ApiException(
        type: ApiErrorType.conflict,
        message: 'You have already saved this vehicle',
        statusCode: 409,
      );
    }
  }

  @override
  Future<List<Vehicle>> list() async {
    lists++;
    _check();
    return [...items];
  }

  @override
  Future<Vehicle> add({
    required VehicleType type,
    required String registration,
    required String make,
    required String model,
    String? nickname,
  }) async {
    _check();
    _unique(registration, null);
    final saved = Vehicle(
      id: 'v${_next++}',
      type: type,
      registration: registration,
      make: make,
      model: model,
      nickname: (nickname == null || nickname.trim().isEmpty)
          ? null
          : nickname.trim(),
    );
    items.add(saved);
    return saved;
  }

  @override
  Future<Vehicle> update(
    String id, {
    required VehicleType type,
    required String registration,
    required String make,
    required String model,
    String? nickname,
  }) async {
    _check();
    _unique(registration, id);
    final saved = Vehicle(
      id: id,
      type: type,
      registration: registration,
      make: make,
      model: model,
      nickname: (nickname == null || nickname.trim().isEmpty)
          ? null
          : nickname.trim(),
    );
    items[items.indexWhere((v) => v.id == id)] = saved;
    return saved;
  }

  @override
  Future<void> delete(String id) async {
    _check();
    items.removeWhere((v) => v.id == id);
  }
}
