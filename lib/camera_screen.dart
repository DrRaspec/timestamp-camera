import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/camera_screen_controller.dart';
import 'photo_stamp.dart';
import 'photo_view_screen.dart';

class CameraTestScreen extends GetView<CameraScreenController> {
  const CameraTestScreen(this._tag, {super.key});

  @override
  String get tag => _tag;
  final String _tag;

  static Future<dynamic>? open() {
    final tag = 'camera-${DateTime.now().microsecondsSinceEpoch}';
    return Get.to(
      () => CameraTestScreen(tag),
      binding: BindingsBuilder(() {
        Get.put(CameraScreenController(), tag: tag);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final error = controller.error.value;
      if (error != null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Camera error:\n$error', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: controller.initCamera,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      final camera = controller.camera.value;
      if (camera == null || !camera.value.isInitialized) {
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        );
      }

      return PopScope(
        canPop: controller.canLeave,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final d = _Dims.forHeight(box.maxHeight);
                return Column(
                  children: [
                    _topBar(d),
                    Expanded(child: _preview(camera)),
                    SizedBox(height: d.gap),
                    _controls(d),
                    SizedBox(height: d.gap),
                    Obx(
                      () => AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: controller.shots.isEmpty
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: EdgeInsets.only(bottom: d.gap / 2),
                                child: _thumbnails(d),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    });
  }

  Widget _topBar(_Dims d) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: d.gap / 3),
      child: Row(
        children: [
          Obx(
            () => _RoundIconButton(
              icon: switch (controller.flash.value) {
                FlashMode.auto => Icons.flash_auto,
                FlashMode.always => Icons.flash_on,
                _ => Icons.flash_off,
              },
              size: d.topButton,
              onTap: controller.cycleFlash,
            ),
          ),
          const Spacer(),
          Obx(
            () => _RoundIconButton(
              icon: Icons.apps,
              size: d.topButton,
              active: controller.showGrid.value,
              onTap: controller.toggleGrid,
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(CameraController camera) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final previewHeight = w * camera.value.aspectRatio;
        final short = box.biggest.shortestSide;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: w,
                  height: previewHeight,
                  child: CameraPreview(camera),
                ),
              ),
              Obx(
                () => controller.showGrid.value
                    ? const _GridOverlay()
                    : const SizedBox.shrink(),
              ),
              Positioned(
                right: short * 0.03,
                bottom: short * 0.03,
                child: Obx(
                  () => _StampText(
                    text:
                        '${CameraScreenController.name}\n${formatStamp(controller.now.value)}',
                    fontSize: short * 0.035,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controls(_Dims d) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: d.sidePadding),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Obx(
                () => Opacity(
                  opacity: controller.busy.value ? 0.4 : 1,
                  child: _RoundIconButton(
                    icon: Icons.close,
                    size: d.sideButton,
                    onTap: controller.close,
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: controller.takePhoto,
            child: Container(
              width: d.shutter,
              height: d.shutter,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Obx(() {
                final busy = controller.busy.value;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: busy ? Colors.white70 : Colors.white,
                  ),
                  child: busy
                      ? Padding(
                          padding: EdgeInsets.all(d.shutter * 0.22),
                          child: const CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.black54,
                          ),
                        )
                      : null,
                );
              }),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Obx(
                () => OutlinedButton(
                  onPressed: controller.busy.value ? null : controller.done,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF2A2A2A),
                    side: const BorderSide(color: Colors.white70),
                    minimumSize: Size(d.doneWidth, d.doneHeight),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnails(_Dims d) {
    final badge = d.badge;
    final pad = badge / 3;
    final imageHeight = d.strip - 12 - pad;
    final imageWidth = imageHeight * 0.8;
    return Container(
      height: d.strip,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Obx(
        () => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          itemCount: controller.shots.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final path = controller.shots[i];
            return Padding(
              padding: EdgeInsets.only(top: pad, right: pad),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () => PhotoViewScreen.open(controller, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(path),
                        width: imageWidth,
                        height: imageHeight,
                        fit: BoxFit.cover,
                        cacheWidth: 216,
                      ),
                    ),
                  ),
                  Positioned(
                    top: -pad,
                    right: -pad,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => controller.deleteShot(i),
                      child: Container(
                        width: badge,
                        height: badge,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF111111),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.delete_outline,
                          size: badge * 0.6,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Dims {
  const _Dims._(this.k);

  final double k;

  factory _Dims.forHeight(double height) =>
      _Dims._(((height - 560) / 280).clamp(0.0, 1.0) * 0.28 + 0.72);

  double get gap => 24 * k;
  double get topButton => 40 * k;
  double get sideButton => 48 * k;
  double get sidePadding => 44 * k;
  double get shutter => 80 * k;
  double get doneWidth => 96 * k;
  double get doneHeight => 50 * k;
  double get strip => 112 * k;
  double get badge => (30 * k).clamp(26.0, 30.0);
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.size,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white : Colors.white24,
        ),
        child: Icon(
          icon,
          size: size * 0.55,
          color: active ? Colors.black : Colors.white,
        ),
      ),
    );
  }
}

class _StampText extends StatelessWidget {
  const _StampText({required this.text, required this.fontSize});
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        height: 1.2,
        shadows: [
          Shadow(color: const Color(0xD9000000), blurRadius: fontSize * 0.4),
        ],
      ),
    );
  }
}

class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _GridPainter()));
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
