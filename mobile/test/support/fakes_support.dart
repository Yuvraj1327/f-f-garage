import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/support_contact.dart';
import 'package:ff_garage/data/repositories/support_repository.dart';
import 'package:ff_garage/data/services/contact_launcher.dart';

SupportContact contactDetails({
  String name = 'F&F Two Wheeler Garage',
  String phone = '+919876543210',
  String whatsapp = '919876543210',
  String email = 'help@example.com',
  String address = '12 Main Road, Pune',
  String hours = 'Mon-Sat 9am-7pm',
}) =>
    SupportContact(
      name: name,
      phone: phone,
      whatsapp: whatsapp,
      email: email,
      address: address,
      hours: hours,
    );

/// Returns [contact], or throws [error] when it is set. Counts the calls.
class FakeSupportRepository implements SupportRepository {
  FakeSupportRepository([SupportContact? contact])
      : current = contact ?? contactDetails();

  SupportContact current;
  ApiException? error;
  int calls = 0;

  @override
  Future<SupportContact> contact() async {
    calls++;
    if (error != null) throw error!;
    return current;
  }
}

/// Records what the screen asked the device to open. Set [canOpen] to false to
/// mimic a device that cannot place calls, send mail, etc.
class FakeContactLauncher implements ContactLauncher {
  bool canOpen = true;
  final List<String> opened = [];

  @override
  Future<bool> call(String phone) async {
    opened.add('call:$phone');
    return canOpen;
  }

  @override
  Future<bool> whatsapp(String phone, {String? message}) async {
    opened.add('whatsapp:$phone:${message ?? ''}');
    return canOpen;
  }

  @override
  Future<bool> email(String address, {String? subject}) async {
    opened.add('email:$address');
    return canOpen;
  }

  @override
  Future<bool> map(String address) async {
    opened.add('map:$address');
    return canOpen;
  }

  @override
  Future<bool> directions(String destination) async {
    opened.add('directions:$destination');
    return canOpen;
  }
}
