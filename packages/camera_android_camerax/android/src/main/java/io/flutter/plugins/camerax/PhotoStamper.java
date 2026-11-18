package io.flutter.plugins.camerax;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ImageFormat;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
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
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Burns the stamp text into a captured photo and writes it as a JPEG.
 *
 * <p>Done as a post-capture step instead of a CameraX effect: OverlayEffect cannot target
 * IMAGE_CAPTURE alone, and applying it to the preview breaks the plugin's preview rotation.
 *
 * <p>Dart configures it over the {@code photo_stamp} method channel ({@code setStampText}, {@code
 * clearStampText}, {@code awaitStamp}); see docs/NATIVE_INTEGRATION.md.
 */
final class PhotoStamper {
  private static final String TAG = "PhotoStamper";
  private static final long NANOS_PER_MS = 1_000_000L;

  static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

  private static volatile String[] lines = new String[0];
  // JPEG quality in percent. 60 gives files about half the size of 85 with little visible loss
  // (measured on a PLF110). Dart sends the user's choice with every setStampText call.
  private static volatile int quality = 60;
  // Power of 2; 1 = full size, 2 = half width/height (decoding downscaled is faster).
  private static volatile int sampleSize = 1;

  // Stamp thread only. Kept between shots so each decode doesn't allocate a full-size bitmap.
  private static Bitmap reusable;

  // Main thread only: files still being written, failures nobody has asked about yet, and
  // awaitStamp calls waiting for a file.
  private static final Set<String> pending = new HashSet<>();
  private static final Map<String, String> failed = new HashMap<>();
  private static final Map<String, List<MethodChannel.Result>> waiters = new HashMap<>();

  static final class Settings {
    final String[] lines;
    final int quality;
    final int sampleSize;

    Settings(String[] lines, int quality, int sampleSize) {
      this.lines = lines;
      this.quality = quality;
      this.sampleSize = sampleSize;
    }
  }

  static final class Capture {
    @Nullable final byte[] jpeg;
    @Nullable final Bitmap bitmap;
    final int rotation;

    Capture(@Nullable byte[] jpeg, @Nullable Bitmap bitmap, int rotation) {
      this.jpeg = jpeg;
      this.bitmap = bitmap;
      this.rotation = rotation;
    }
  }

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
                  EXECUTOR.execute(PhotoStamper::releaseBitmap);
                  result.success(null);
                  break;
                case "awaitStamp":
                  awaitStamp(call.argument("path"), result);
                  break;
                default:
                  result.notImplemented();
              }
            });
  }

  static boolean isEnabled() {
    return lines.length > 0;
  }

  static Settings snapshot() {
    return new Settings(lines, quality, sampleSize);
  }

  static void markPending(@NonNull String path) {
    pending.add(path);
  }

  static void finish(@NonNull String path, @Nullable String error) {
    pending.remove(path);
    final List<MethodChannel.Result> waiting = waiters.remove(path);
    if (waiting == null) {
      if (error != null) failed.put(path, error);
      return;
    }
    for (MethodChannel.Result result : waiting) {
      reply(result, error);
    }
  }

  private static void awaitStamp(@Nullable String path, @NonNull MethodChannel.Result result) {
    final String error = failed.remove(path);
    if (error != null || !pending.contains(path)) {
      reply(result, error);
      return;
    }
    List<MethodChannel.Result> waiting = waiters.get(path);
    if (waiting == null) {
      waiting = new ArrayList<>();
      waiters.put(path, waiting);
    }
    waiting.add(result);
  }

  private static void reply(MethodChannel.Result result, @Nullable String error) {
    if (error == null) {
      result.success(null);
    } else {
      result.error("stampFailed", error, null);
    }
  }

  private static void releaseBitmap() {
    if (reusable != null) reusable.recycle();
    reusable = null;
  }

  static Capture read(@NonNull ImageProxy image) {
    final int rotation = image.getImageInfo().getRotationDegrees();
    final int format = image.getFormat();
    if (format == ImageFormat.JPEG || format == ImageFormat.JPEG_R) {
      final ByteBuffer buffer = image.getPlanes()[0].getBuffer();
      final byte[] bytes = new byte[buffer.remaining()];
      buffer.get(bytes);
      return new Capture(bytes, null, rotation);
    }
    return new Capture(null, image.toBitmap(), rotation);
  }

  /**
   * Stamps a capture and writes it to {@code out} as an upright JPEG. Capturing to memory means
   * the photo is written to disk once, instead of saved, read back and rewritten. Call on {@link
   * #EXECUTOR}.
   */
  static void stamp(@NonNull Capture capture, @NonNull Settings settings, @NonNull File out)
      throws IOException {
    final long start = System.nanoTime();
    Bitmap bitmap = capture.bitmap != null ? capture.bitmap : decode(capture.jpeg, settings);

    if (capture.rotation != 0) {
      final Matrix m = new Matrix();
      m.postRotate(capture.rotation);
      final Bitmap upright =
          Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), m, true);
      if (upright != bitmap) recycleUnlessReusable(bitmap);
      bitmap = upright;
    }
    if (!bitmap.isMutable()) {
      final Bitmap copy = bitmap.copy(Bitmap.Config.ARGB_8888, true);
      recycleUnlessReusable(bitmap);
      bitmap = copy;
    }

    try {
      if (settings.lines.length > 0) {
        draw(new Canvas(bitmap), bitmap.getWidth(), bitmap.getHeight(), settings.lines);
      }
      final long encodeStart = System.nanoTime();
      try (OutputStream stream = new BufferedOutputStream(new FileOutputStream(out), 1 << 16)) {
        bitmap.compress(Bitmap.CompressFormat.JPEG, settings.quality, stream);
      }
      final long end = System.nanoTime();
      Log.i(
          TAG,
          String.format(
              Locale.US,
              "Saved %dx%d, %.1f KB, quality %d, encode %d ms, total %d ms",
              bitmap.getWidth(),
              bitmap.getHeight(),
              out.length() / 1024f,
              settings.quality,
              (end - encodeStart) / NANOS_PER_MS,
              (end - start) / NANOS_PER_MS));
    } finally {
      recycleUnlessReusable(bitmap);
    }
  }

  // Decodes into the bitmap kept from the previous shot when it fits, and keeps the result for
  // the next shot.
  private static Bitmap decode(byte[] jpeg, Settings settings) throws IOException {
    final BitmapFactory.Options opts = new BitmapFactory.Options();
    opts.inMutable = true;
    opts.inSampleSize = settings.sampleSize;
    opts.inBitmap = reusable;
    Bitmap bitmap;
    try {
      bitmap = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.length, opts);
    } catch (IllegalArgumentException e) {
      // The kept bitmap is too small for this photo.
      opts.inBitmap = null;
      bitmap = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.length, opts);
    }
    if (bitmap == null) throw new IOException("Failed to decode captured image");
    if (bitmap != reusable) {
      releaseBitmap();
      reusable = bitmap;
    }
    return bitmap;
  }

  private static void recycleUnlessReusable(Bitmap bitmap) {
    if (bitmap != reusable) bitmap.recycle();
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
