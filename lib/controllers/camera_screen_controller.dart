import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../photo_stamp.dart';

/// State for [CameraTestScreen]. Named to avoid clashing with the camera
/// package's own `CameraController`.
///
/// One instance per opened camera screen (registered with a unique tag), so a
/// closing screen can never dispose the camera of a newly opened one.
class CameraScreenController extends GetxController
    with WidgetsBindingObserver {
  static const String name = 'Luo Mao';

  final camera = Rxn<CameraController>();
  final error = RxnString();

  /// True while a photo is being captured, stamped and compressed.
  final busy = false.obs;
  final showGrid = false.obs;
  final flash = FlashMode.off.obs;
  final shots = <String>[].obs;
  final now = DateTime.now().obs;

  Timer? _clock;
  bool _initializing = false;
  bool _inBackground = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final t = DateTime.now();
      if (t.minute != now.value.minute) now.value = t;
    });
    initCamera();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _releaseCamera();
    super.onClose();
  }

  // The camera must be released when the app leaves the foreground and
  // re-created on return, otherwise the preview freezes or goes black.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_inBackground) return;
        _inBackground = true;
        _releaseCamera();
      case AppLifecycleState.resumed:
        if (!_inBackground) return;
        _inBackground = false;
        // Also retries after the user granted permission in Settings.
        if (camera.value == null) initCamera();
      default:
        break;
    }
  }

  Future<void> initCamera() async {
    if (_initializing || isClosed) return;
    _initializing = true;
    error.value = null;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      await PhotoStamp.setText([name, formatStamp(DateTime.now())]);

      // veryHigh (1080p) matches the 16:9 preview and is much faster to
      // capture and stamp than max (12MP).
      controller =
          CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await controller.initialize();
      await controller.setFlashMode(flash.value);
      // Speed: ZSL takes the photo from already-buffered frames, and a lower
      // camera JPEG quality is fine because the stamper re-encodes anyway.
      if (await controller.isZeroShutterLagSupported()) {
        await controller.setZeroShutterLagEnabled(true);
      }
      await controller.setJpegImageQuality(85);

      // The screen closed or the app went to the background meanwhile.
      if (isClosed || _inBackground) {
        await controller.dispose();
        return;
      }
      camera.value = controller;
    } on CameraException catch (e) {
      await controller?.dispose();
      final denied = e.code.startsWith('CameraAccessDenied');
      error.value = denied
          ? 'Camera permission denied.\nGrant it in Settings > Apps > this app > Permissions, then tap Retry.'
          : '${e.code}: ${e.description}';
    } catch (e) {
      await controller?.dispose();
      error.value = e.toString();
    } finally {
      _initializing = false;
    }
  }

  Future<void> _releaseCamera() async {
    final controller = camera.value;
    if (controller == null) return;
    // Remove it from the UI first so CameraPreview never builds with a
    // disposed controller.
    camera.value = null;
    await controller.dispose();
  }

  Future<void> takePhoto() async {
    final controller = camera.value;
    if (controller == null || !controller.value.isInitialized || busy.value) {
      return;
    }
    busy.value = true;
    try {
      await PhotoStamp.setText([name, formatStamp(DateTime.now())]);
      final shot = await controller.takePicture();
      if (!isClosed) shots.add(shot.path);
    } catch (e) {
      if (!isClosed && camera.value != null) {
        Get.snackbar('Capture failed', '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      busy.value = false;
    }
  }

  Future<void> cycleFlash() async {
    final controller = camera.value;
    if (controller == null || busy.value) return;
    final next = switch (flash.value) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
      flash.value = next;
    } on CameraException catch (e) {
      Get.snackbar('Flash not available', '${e.description}',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void toggleGrid() => showGrid.toggle();

  void deleteShot(int index) {
    final path = shots.removeAt(index);
    File(path).delete().ignore();
  }

  /// Leaving is blocked while a photo is still being stamped.
  bool get canLeave => !busy.value;

  void close() {
    if (canLeave) Get.back();
  }

  void done() {
    if (canLeave) Get.back(result: shots.toList());
  }
}
