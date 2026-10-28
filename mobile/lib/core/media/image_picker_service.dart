import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;

/// Where a picture comes from.
enum PickSource { gallery, camera }

/// The most the server accepts for one picture.
const int maxPictureBytes = 5 * 1024 * 1024;

/// A picture chosen on the device, already read into memory.
class PickedImage {
  const PickedImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;

  /// Worked out from the bytes (never from the file name), or null when it is
  /// not a JPG, PNG or WebP picture.
  String? get contentType => sniffImageType(bytes);
}

/// `image/jpeg`, `image/png` or `image/webp` from the file's first bytes.
String? sniffImageType(Uint8List b) {
  bool starts(List<int> sig) =>
      b.length >= sig.length &&
      [for (var i = 0; i < sig.length; i++) b[i] == sig[i]].every((x) => x);
  if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (b.length > 12 &&
      starts([0x52, 0x49, 0x46, 0x46]) &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// Why a picture cannot be used, or null when it is fine. The server checks
/// again; this just saves a slow upload that is sure to fail.
String? checkPicture(PickedImage image) {
  if (image.bytes.isEmpty) return 'That picture is empty.';
  if (image.bytes.length > maxPictureBytes) {
    return 'That picture is too large. Use one under 5 MB.';
  }
  if (image.contentType == null) return 'Use a JPG, PNG or WebP picture.';
  return null;
}

/// Picks a picture from the gallery or takes one with the camera.
abstract class ImagePickerService {
  /// Null when the person backed out without choosing.
  Future<PickedImage?> pick(PickSource source);
}

class DeviceImagePickerService implements ImagePickerService {
  final picker.ImagePicker _picker = picker.ImagePicker();

  @override
  Future<PickedImage?> pick(PickSource source) async {
    final file = await _picker.pickImage(
      source: source == PickSource.camera
          ? picker.ImageSource.camera
          : picker.ImageSource.gallery,
      // Phone photos are huge; this keeps them well under the upload limit.
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 88,
    );
    if (file == null) return null;
    return PickedImage(bytes: await file.readAsBytes(), name: file.name);
  }
}

final imagePickerServiceProvider = Provider<ImagePickerService>(
  (ref) => DeviceImagePickerService(),
);
