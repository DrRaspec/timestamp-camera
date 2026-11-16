import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'camera_screen_controller.dart';

/// Viewer over [CameraScreenController.shots]; deletions go straight to that list.
class PhotoViewController extends GetxController {
  PhotoViewController({required this.camera, required int initialIndex})
      : index = initialIndex.obs;

  final RxInt index;
  late final PageController pageController =
      PageController(initialPage: index.value);
  final stripController = ScrollController();

  final CameraScreenController camera;

  RxList<String> get shots => camera.shots;

  static const double thumbWidth = 30;
  static const double activeThumbWidth = 56;
  static const double thumbGap = 4;

  @override
  void onReady() {
    super.onReady();
    _centerStrip(animate: false);
  }

  @override
  void onClose() {
    pageController.dispose();
    stripController.dispose();
    super.onClose();
  }

  void onPageChanged(int i) {
    index.value = i;
    _centerStrip();
  }

  void jumpTo(int i) {
    if (i == index.value) return;
    pageController.jumpToPage(i);
  }

  Future<void> deleteCurrent() async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete photo?'),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    camera.deleteShot(index.value);
    if (shots.isEmpty) {
      Get.back();
      return;
    }
    if (index.value >= shots.length) index.value = shots.length - 1;
    _centerStrip();
  }

  // Keep the active thumbnail centred in the strip, like Telegram.
  void _centerStrip({bool animate = true}) {
    if (!stripController.hasClients) return;
    final pos = stripController.position;
    final target = index.value * (thumbWidth + thumbGap) +
        activeThumbWidth / 2 -
        pos.viewportDimension / 2;
    final clamped = target.clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      stripController.animateTo(clamped,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      stripController.jumpTo(clamped);
    }
  }
}
