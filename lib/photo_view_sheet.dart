import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/camera_screen_controller.dart';
import 'controllers/photo_view_controller.dart';

class PhotoViewSheet extends GetView<PhotoViewController> {
  const PhotoViewSheet(this._tag, {super.key});

  @override
  String get tag => _tag;
  final String _tag;

  static Future<void> open(CameraScreenController camera, int index) {
    final tag = 'viewer-${DateTime.now().microsecondsSinceEpoch}';
    Get.put(
      PhotoViewController(camera: camera, initialIndex: index),
      tag: tag,
    );
    return Get.bottomSheet(
      PhotoViewSheet(tag),
      isScrollControlled: true,
      enableDrag: true,
      ignoreSafeArea: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
    ).whenComplete(() => Get.delete<PhotoViewController>(tag: tag));
  }

  @override
  Widget build(BuildContext context) {
    // Photos are 9:16 portrait (1080x1920), so the sheet is sized to fit one
    // across the full width instead of leaving blank space around it.
    final screen = MediaQuery.sizeOf(context);
    final height = min(
      screen.height * 0.9,
      screen.width * 16 / 9,
    );
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(
            // The buttons and strip float over the photo to give it more room.
            child: Stack(
              children: [
                Positioned.fill(
                  child: Obx(
                    () => PageView.builder(
                      controller: controller.pageController,
                      itemCount: controller.shots.length,
                      onPageChanged: controller.onPageChanged,
                      itemBuilder: (_, i) =>
                          _ZoomablePhoto(controller.shots[i]),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 20,
                  child: _CircleButton(icon: Icons.close, onTap: Get.back),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Row(
                    children: [
                      // Same width as the delete button, so the strip stays
                      // centred.
                      const SizedBox(width: _CircleButton.size),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: Obx(
                            () => controller.shots.length > 1
                                ? _strip()
                                : const SizedBox(),
                          ),
                        ),
                      ),
                      _CircleButton(
                        icon: Icons.delete_outline,
                        onTap: controller.deleteCurrent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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

/// Pinch to zoom. At normal size, dragging the photo down closes the sheet;
/// the zoom gesture would otherwise swallow the sheet's own drag.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto(this.path);
  final String path;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  static const _closeDistance = 120.0;
  static const _closeVelocity = 700.0;

  final _transform = TransformationController();
  bool _zoomed = false;
  double _dragY = 0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (_zoomed || details.pointerCount != 1) return;
    setState(() => _dragY = max(0, _dragY + details.focalPointDelta.dy));
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    if (!_zoomed &&
        (_dragY > _closeDistance ||
            details.velocity.pixelsPerSecond.dy > _closeVelocity)) {
      Get.back();
      return;
    }
    setState(() {
      _zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      _dragY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, _dragY),
      child: InteractiveViewer(
        transformationController: _transform,
        panEnabled: _zoomed,
        onInteractionUpdate: _onInteractionUpdate,
        onInteractionEnd: _onInteractionEnd,
        child: SizedBox.expand(
          child: Image.file(File(widget.path), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  static const double size = 46;

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF9E9E9E),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}
