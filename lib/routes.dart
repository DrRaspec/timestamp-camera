import 'package:get/get.dart';

import 'controllers/start_controller.dart';
import 'start_screen.dart';

abstract class Routes {
  static const start = '/';
}

final appPages = [
  GetPage(
    name: Routes.start,
    page: () => const StartScreen(),
    binding: BindingsBuilder(() => Get.lazyPut(() => StartController())),
  ),
];
