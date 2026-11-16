import 'package:camera/camera.dart';
import 'package:get/get.dart';

import '../camera_screen.dart';

class StartController extends GetxController {
  final checking = false.obs;
  final message = RxnString();

  bool _permissionGranted = false;
  bool _cameraOpen = false;

  Future<void> requestAndOpen() async {
    // Guards against a double tap opening two camera screens, which would
    // fight over the camera.
    if (checking.value || _cameraOpen) return;
    checking.value = true;
    message.value = null;
    try {
      if (!_permissionGranted && !await _requestPermission()) return;
    } finally {
      checking.value = false;
    }

    _cameraOpen = true;
    try {
      final shots = await CameraTestScreen.open();
      if (shots is List<String>) {
        Get.snackbar('Done', '${shots.length} photo(s) captured',
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      _cameraOpen = false;
    }
  }

  // The camera plugin shows the system permission prompt on initialize(), so
  // a throwaway controller asks for it here. Only done until it is granted:
  // opening and closing the camera right before the real camera screen opens
  // it again adds delay and can glitch on some devices.
  Future<bool> _requestPermission() async {
    CameraController? probe;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        message.value = 'No camera found on this device.';
        return false;
      }
      probe = CameraController(cameras.first, ResolutionPreset.low,
          enableAudio: false);
      await probe.initialize();
      _permissionGranted = true;
      return true;
    } on CameraException catch (e) {
      message.value = e.code.startsWith('CameraAccessDenied')
          ? 'Camera permission denied. Enable it in Settings > Apps > this app > Permissions, then try again.'
          : '${e.code}: ${e.description}';
      return false;
    } catch (e) {
      message.value = e.toString();
      return false;
    } finally {
      await probe?.dispose();
    }
  }
}
