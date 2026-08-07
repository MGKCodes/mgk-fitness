import 'package:image_picker/image_picker.dart';

import '../domain/progress_photo.dart';

/// The real camera and gallery, via `image_picker`.
///
/// Shoots at a capped resolution rather than whatever the sensor gives. A modern
/// phone camera produces 8–12 MB per frame; at one photo a week across two poses
/// that is half a gigabyte in a couple of years, on a device, for images only
/// ever viewed at phone size. 1440 on the long edge is more than a screen can
/// show and about a tenth of the bytes.
class CameraPhotoSource implements PhotoSource {
  CameraPhotoSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const double _maxEdge = 1440;
  static const int _quality = 88;

  @override
  Future<String?> capture() => _take(ImageSource.camera);

  @override
  Future<String?> pickFromGallery() => _take(ImageSource.gallery);

  Future<String?> _take(ImageSource source) async {
    // A declined permission or a cancelled picker both surface here. Neither is
    // an error worth showing — the lifter changed their mind, or said no, and
    // the screen should simply stay where it was.
    final file = await _picker.pickImage(
      source: source,
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _quality,
      preferredCameraDevice: CameraDevice.front,
    );
    return file?.path;
  }
}
