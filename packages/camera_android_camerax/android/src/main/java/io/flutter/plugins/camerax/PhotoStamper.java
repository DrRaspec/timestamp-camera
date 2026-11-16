package io.flutter.plugins.camerax;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.ImageFormat;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import androidx.annotation.NonNull;
import androidx.camera.core.ImageProxy;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

/**
 * Burns the stamp text into a captured JPEG file.
 *
 * <p>Done as a post-capture step instead of a CameraX effect: OverlayEffect cannot target
 * IMAGE_CAPTURE alone, and applying it to the preview breaks the plugin's preview rotation.
 */
final class PhotoStamper {
  private static volatile String[] lines = new String[0];
  private static volatile int quality = 85;
  // Power of 2; 1 = full size, 2 = half width/height (decoding downscaled is faster).
  private static volatile int sampleSize = 1;

  private PhotoStamper() {}

  static void register(@NonNull BinaryMessenger messenger) {
    new MethodChannel(messenger, "photo_stamp")
        .setMethodCallHandler(
            (call, result) -> {
              switch (call.method) {
                case "setStampText":
                  final List<String> list = call.argument("lines");
                  final List<String> clean = new ArrayList<>();
                  if (list != null) {
                    for (String s : list) {
                      if (s != null && !s.isEmpty()) clean.add(s);
                    }
                  }
                  final Integer q = call.argument("quality");
                  if (q != null) quality = Math.max(1, Math.min(100, q));
                  final Integer ss = call.argument("sampleSize");
                  if (ss != null) sampleSize = Math.max(1, ss);
                  lines = clean.toArray(new String[0]);
                  result.success(null);
                  break;
                case "clearStampText":
                  lines = new String[0];
                  result.success(null);
                  break;
                default:
                  result.notImplemented();
              }
            });
  }

  static boolean isEnabled() {
    return lines.length > 0;
  }

  /**
   * Stamps an in-memory capture and writes it to {@code out} as an upright JPEG. Capturing to
   * memory means the photo is written to disk once, instead of saved, read back and rewritten.
   * Call off the main thread; the caller closes {@code image}.
   */
  static void stampImage(@NonNull ImageProxy image, @NonNull File out) throws IOException {
    Bitmap bitmap;
    final int format = image.getFormat();
    if (format == ImageFormat.JPEG || format == ImageFormat.JPEG_R) {
      final ByteBuffer buffer = image.getPlanes()[0].getBuffer();
      final byte[] bytes = new byte[buffer.remaining()];
      buffer.get(bytes);
      final BitmapFactory.Options opts = new BitmapFactory.Options();
      opts.inMutable = true;
      opts.inSampleSize = sampleSize;
      bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, opts);
    } else {
      bitmap = image.toBitmap();
    }
    if (bitmap == null) throw new IOException("Failed to decode captured image");

    final int rotation = image.getImageInfo().getRotationDegrees();
    if (rotation != 0) {
      final Matrix m = new Matrix();
      m.postRotate(rotation);
      final Bitmap upright =
          Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), m, true);
      if (upright != bitmap) bitmap.recycle();
      bitmap = upright;
    }
    if (!bitmap.isMutable()) {
      final Bitmap copy = bitmap.copy(Bitmap.Config.ARGB_8888, true);
      bitmap.recycle();
      bitmap = copy;
    }

    final String[] current = lines;
    if (current.length > 0) {
      draw(new Canvas(bitmap), bitmap.getWidth(), bitmap.getHeight(), current);
    }

    try (OutputStream stream = new BufferedOutputStream(new FileOutputStream(out), 1 << 16)) {
      bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream);
    } finally {
      bitmap.recycle();
    }
  }

  private static void draw(Canvas canvas, int w, int h, String[] current) {
    final float shortSide = Math.min(w, h);
    final float textSize = shortSide * 0.035f;
    final float margin = shortSide * 0.03f;

    final TextPaint paint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    paint.setColor(Color.WHITE);
    paint.setTextSize(textSize);
    paint.setShadowLayer(textSize * 0.2f, 0f, 0f, Color.argb(217, 0, 0, 0));

    final String text = String.join("\n", current);
    final int width = Math.max(1, Math.round(w - 2 * margin));
    final StaticLayout layout =
        StaticLayout.Builder.obtain(text, 0, text.length(), paint, width)
            .setAlignment(Layout.Alignment.ALIGN_OPPOSITE)
            .build();

    canvas.save();
    canvas.translate(margin, h - margin - layout.getHeight());
    layout.draw(canvas);
    canvas.restore();
  }
}
