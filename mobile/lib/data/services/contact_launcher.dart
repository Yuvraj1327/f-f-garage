import 'package:url_launcher/url_launcher.dart';

/// Opens the phone dialler, WhatsApp, the mail app or a map. A narrow interface
/// so screens (and tests) never touch the plugin directly. Each method returns
/// false when nothing on the device could handle the request, so the screen can
/// show the details to copy instead of failing silently.
abstract class ContactLauncher {
  Future<bool> call(String phone);
  Future<bool> whatsapp(String phone, {String? message});
  Future<bool> email(String address, {String? subject});
  Future<bool> map(String address);

  /// Turn-by-turn directions to [destination] (an address or "lat,lng") in the
  /// device's maps app, starting from where the device is now.
  Future<bool> directions(String destination);
}

class UrlContactLauncher implements ContactLauncher {
  const UrlContactLauncher();

  @override
  Future<bool> call(String phone) => _open(Uri(scheme: 'tel', path: phone));

  @override
  Future<bool> whatsapp(String phone, {String? message}) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return _open(
      Uri.https('wa.me', '/$digits', {
        if (message != null && message.isNotEmpty) 'text': message,
      }),
    );
  }

  @override
  Future<bool> email(String address, {String? subject}) => _open(
        Uri(
          scheme: 'mailto',
          path: address,
          queryParameters: {
            if (subject != null && subject.isNotEmpty) 'subject': subject,
          },
        ),
      );

  @override
  Future<bool> map(String address) => _open(
        Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': address,
        }),
      );

  @override
  Future<bool> directions(String destination) => _open(
        Uri.https('www.google.com', '/maps/dir/', {
          'api': '1',
          'destination': destination,
          'travelmode': 'driving',
        }),
      );

  Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
