import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/start_controller.dart';

class StartScreen extends GetView<StartController> {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt, size: 72),
                const SizedBox(height: 16),
                Text(
                  'Camera',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Camera access is needed to take photos with a name and time stamp.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Obx(() {
                  final msg = controller.message.value;
                  if (msg == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }),
                Obx(
                  () => FilledButton(
                    onPressed: controller.checking.value
                        ? null
                        : controller.requestAndOpen,
                    child: controller.checking.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Allow camera & open'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
