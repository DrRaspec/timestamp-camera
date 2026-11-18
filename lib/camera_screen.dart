import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/camera_screen_controller.dart';
import 'photo_stamp.dart';
import 'photo_view_sheet.dart';

class CameraTestScreen extends GetView<CameraScreenController> {
  const CameraTestScreen(this._tag, {super.key});

  @override
  String get tag => _tag;
  final String _tag;

  static Future<dynamic>? open() {
    final tag = 'camera-${DateTime.now().microsecondsSinceEpoch}';
    return Get.to(
      () => CameraTestScreen(tag),
      // A sliding/fading transition blends the white start screen with this
      // black screen and the not-yet-started preview, which looks like a
      // black-and-white flicker.
      transition: Transition.noTransition,
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
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _preview(camera),
                          Positioned(
                            top: 8,
                            left: 16,
                            right: 16,
                            child: _topBar(d),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: d.gap),
                    _controls(d),
                    SizedBox(height: d.gap),
                    // Always reserved, so the preview doesn't resize when the
                    // first photo is taken.
                    Padding(
                      padding: EdgeInsets.only(bottom: d.gap / 2),
                      child: _thumbnails(d),
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
    return Row(
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
          () => _QualityButton(
            percent: controller.quality.value,
            height: d.topButton,
            onTap: _showQualitySheet,
          ),
        ),
        const SizedBox(width: 12),
        Obx(
          () => _RoundIconButton(
            icon: Icons.apps,
            size: d.topButton,
            active: controller.showGrid.value,
            onTap: controller.toggleGrid,
          ),
        ),
      ],
    );
  }

  void _showQualitySheet() {
    Get.bottomSheet(
      _QualitySheet(controller),
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
              const ColoredBox(color: Colors.black),
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
              Obx(
                () => IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: controller.shutterBlink.value ? 0.6 : 0,
                    duration: const Duration(milliseconds: 80),
                    child: const ColoredBox(color: Colors.black),
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
                  opacity: controller.canLeave ? 1 : 0.4,
                  // Extra transparent padding enlarges the tap area; the shift
                  // keeps the circle aligned with the screen margin.
                  child: Transform.translate(
                    offset: const Offset(-10, 0),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: controller.close,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Container(
                          width: d.doneHeight,
                          height: d.doneHeight,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white24,
                          ),
                          child: Icon(
                            Icons.close,
                            size: d.doneHeight * 0.55,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
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
                  onPressed: controller.canLeave ? controller.done : null,
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
      child: Obx(() {
        final pending = controller.pending.toSet();
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          itemCount: controller.shots.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, position) {
            final i = controller.shots.length - 1 - position;
            final path = controller.shots[i];
            if (pending.contains(path)) {
              return Padding(
                padding: EdgeInsets.only(top: pad, right: pad),
                child: Container(
                  width: imageWidth,
                  height: imageHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              );
            }
            return Padding(
              padding: EdgeInsets.only(top: pad, right: pad),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (pending.isEmpty) PhotoViewSheet.open(controller, i);
                    },
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
        );
      }),
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
  double get sidePadding => 16 * k;
  double get shutter => 80 * k;
  double get doneWidth => 96 * k;
  double get doneHeight => 50 * k;
  double get strip => 112 * k;
  double get badge => (30 * k).clamp(26.0, 30.0);
}

/// Pill showing the current photo quality; tapping it opens [_QualitySheet].
class _QualityButton extends StatelessWidget {
  const _QualityButton({
    required this.percent,
    required this.height,
    required this.onTap,
  });

  final int percent;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          color: Colors.black45,
        ),
        child: Text(
          '$percent%',
          style: TextStyle(
            color: Colors.white,
            fontSize: height * 0.38,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Lets the user trade file size for detail. Takes effect on the next photo.
class _QualitySheet extends StatelessWidget {
  const _QualitySheet(this.controller);

  final CameraScreenController controller;

  static const _textColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(
              () => Text(
                'Photo quality: ${controller.quality.value}%',
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Lower quality makes smaller files with less detail. '
              'It applies to the next photo.',
              style: TextStyle(color: Colors.white70),
            ),
            Obx(
              () => Slider(
                value: controller.quality.value.toDouble(),
                min: PhotoStamp.minQuality.toDouble(),
                max: PhotoStamp.maxQuality.toDouble(),
                divisions: (PhotoStamp.maxQuality - PhotoStamp.minQuality) ~/ 5,
                label: '${controller.quality.value}%',
                onChanged: (v) => controller.setQuality(v.round()),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    controller.setQuality(PhotoStamp.defaultQuality),
                child: Text('Reset to ${PhotoStamp.defaultQuality}%'),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          color: active ? Colors.white : Colors.black45,
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
