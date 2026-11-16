import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/camera_screen_controller.dart';
import 'controllers/photo_view_controller.dart';

class PhotoViewScreen extends GetView<PhotoViewController> {
  const PhotoViewScreen(this._tag, {super.key});

  @override
  String get tag => _tag;
  final String _tag;

  static void open(CameraScreenController camera, int index) {
    final tag = 'viewer-${DateTime.now().microsecondsSinceEpoch}';
    Get.to(
      () => PhotoViewScreen(tag),
      binding: BindingsBuilder(() {
        Get.put(PhotoViewController(camera: camera, initialIndex: index),
            tag: tag);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Obx(() => PageView.builder(
                    controller: controller.pageController,
                    itemCount: controller.shots.length,
                    onPageChanged: controller.onPageChanged,
                    itemBuilder: (_, i) => InteractiveViewer(
                      child: SizedBox.expand(
                        child: Image.file(
                          File(controller.shots[i]),
                          // Fill the width; fall back to fitting inside if
                          // the photo would be taller than the screen.
                          fit: BoxFit.contain,
                          width: double.infinity,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                  )),
            ),
            Positioned(
              left: 20,
              bottom: 20,
              child: _CircleButton(icon: Icons.chevron_left, onTap: Get.back),
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: _CircleButton(
                icon: Icons.delete_outline,
                onTap: controller.deleteCurrent,
              ),
            ),
            Positioned(
              left: 84,
              right: 84,
              bottom: 22,
              height: 40,
              child: Obx(() =>
                  controller.shots.length > 1 ? _strip() : const SizedBox()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strip() {
    return Center(
      child: ListView.separated(
        controller: controller.stripController,
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: controller.shots.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: PhotoViewController.thumbGap),
        itemBuilder: (_, i) => Obx(() {
          final active = i == controller.index.value;
          return GestureDetector(
            onTap: () => controller.jumpTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: active
                  ? PhotoViewController.activeThumbWidth
                  : PhotoViewController.thumbWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: active
                    ? Border.all(color: Colors.black87, width: 1.5)
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Opacity(
                opacity: active ? 1 : 0.7,
                child: Image.file(
                  File(controller.shots[i]),
                  fit: BoxFit.cover,
                  cacheWidth: 120,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          color: Color(0xFF9E9E9E),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}
