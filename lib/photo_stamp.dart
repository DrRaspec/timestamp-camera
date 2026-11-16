import 'package:flutter/services.dart';

class PhotoStamp {
  static const _ch = MethodChannel('photo_stamp');

  static Future<void> setText(
    List<String> lines, {
    int quality = 85,
    int sampleSize = 1,
  }) => _ch.invokeMethod('setStampText', {
    'lines': lines,
    'quality': quality,
    'sampleSize': sampleSize,
  });

  static Future<void> clear() => _ch.invokeMethod('clearStampText');
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
