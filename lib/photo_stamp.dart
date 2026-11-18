import 'package:flutter/services.dart';

class PhotoStamp {
  static const _ch = MethodChannel('photo_stamp');

  static Future<void> setText(
    List<String> lines, {
    int quality = defaultQuality,
    int sampleSize = 1,
  }) => _ch.invokeMethod('setStampText', {
    'lines': lines,
    'quality': quality,
    'sampleSize': sampleSize,
  });

  /// JPEG quality of the saved photo, in percent. 60 gives files about half
  /// the size of 85 with little visible loss (measured on a PLF110 at
  /// 1080x1920).
  static const int defaultQuality = 60;

  /// Range offered to the user. Below [minQuality] photos get visibly blocky.
  static const int minQuality = 20;
  static const int maxQuality = 100;

  static Future<void> clear() => _ch.invokeMethod('clearStampText');

  /// Completes once the photo at [path] is stamped and fully written, or
  /// throws if stamping failed.
  ///
  /// On Android `takePicture()` returns the path while the file is still being
  /// written in the background, so wait for this before reading the file.
  static Future<void> waitUntilWritten(String path) =>
      _ch.invokeMethod('awaitStamp', {'path': path});
}

String formatStamp(DateTime t) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${t.year} ${m[t.month - 1]} ${t.day} $h:${t.minute.toString().padLeft(2, '0')}'
      '${t.hour < 12 ? 'AM' : 'PM'}';
}
