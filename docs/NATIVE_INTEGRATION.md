# Native integration guide

This guide is for moving the photo stamp from this demo into a production
Flutter app. It covers the native side: what the forked camera plugins do,
how to bring them into another repo, the platform configuration, and what to
test.

Status at the time of writing:

- **Android:** tested on a PLF110 (Android 16, API 36).
- **iOS:** the code builds into the fork but has **not been run on a device**.
  Test it before relying on it.

## 1. How it works

The app uses the `camera` package. Behind it, `camera` uses
`camera_android_camerax` on Android and `camera_avfoundation` on iOS. This
repo forks both plugins under `packages/` and points the app at them with
`dependency_overrides`:

```yaml
# pubspec.yaml
dependencies:
  camera: ^0.12.2

dependency_overrides:
  camera_android_camerax:
    path: packages/camera_android_camerax   # fork of 0.7.6+1
  camera_avfoundation:
    path: packages/camera_avfoundation      # fork of 0.11.1
```

Each fork adds a method channel called `photo_stamp`. Dart sets the stamp
text before each shot, and the plugin burns it into the JPEG inside
`takePicture()`, before the file path goes back to Dart. The stamp text is
never drawn on the preview natively; the preview overlay is a Flutter widget.

```text
Dart                               Native (inside the camera plugin)
PhotoStamp.setText(lines) ───────► PhotoStamper stores lines, quality, sampleSize
controller.takePicture()  ───────► capture → decode → draw text → encode JPEG
                          ◄─────── file path of the stamped JPEG
```

### Channel contract

Channel name: `photo_stamp` (`MethodChannel`, standard codec). Dart side:
`lib/photo_stamp.dart`.

| Method | Arguments | Effect |
| --- | --- | --- |
| `setStampText` | `lines: List<String>`, `quality: int` (1–100, default 85), `sampleSize: int` (default 1) | Stores the stamp. Empty strings are dropped. |
| `clearStampText` | none | Clears the lines, so later captures are not stamped. |

Things to know about this contract:

- **Global state:** the stamp is stored in a static or singleton for the whole
  process. Once set, **every** `takePicture()` call in the app is stamped,
  including from other screens, until `clearStampText` is called. In a real
  app, clear it when leaving the stamping screen, or set it right before each
  shot (as this demo does).
- **`sampleSize`** works on both platforms (1 = full size, 2 = half width and
  height).
- **`quality`** works on both platforms (iOS converts it to 0–1). The default
  is 85 on both.

## 2. Android (`packages/camera_android_camerax`)

Files changed from upstream 0.7.6+1, all in
`android/src/main/java/io/flutter/plugins/camerax/`:

| File | Change |
| --- | --- |
| `PhotoStamper.java` | **New.** Registers the channel, holds the stamp settings, and stamps an in-memory capture (`stampImage`). |
| `ImageCaptureProxyApi.java` | `takePicture()`: if a stamp is set, captures to memory with `OnImageCapturedCallback` and calls `PhotoStamper.stampImage` on a single background thread. Without a stamp, it saves the file the stock way. |
| `CameraAndroidCameraxPlugin.java` | Calls `PhotoStamper.register(binding.getBinaryMessenger())` in `onAttachedToEngine`. |
| `ProcessCameraProviderProxyApi.java` | Back to upstream behaviour; no changes remain. |

### Capture pipeline (stamp set)

1. `ImageCapture.takePicture(executor, OnImageCapturedCallback)`: the camera
   returns a JPEG `ImageProxy` in memory. Nothing is written to disk yet.
2. `BitmapFactory.decodeByteArray` with `inMutable = true` and
   `inSampleSize = sampleSize`.
3. Rotate by `ImageInfo.getRotationDegrees()` when it isn't 0 (on the test
   device it was always 0).
4. Draw the text with a `StaticLayout`: right-aligned, text size 3.5% and
   margin 3% of the short side, white with a dark shadow.
5. `Bitmap.compress(JPEG, quality)` into a temporary file in `getCacheDir()`,
   named `CAP*.jpg`. `ImageProxy.close()` is called in `finally`.

### Measured on the PLF110 (`ResolutionPreset.veryHigh`, 1080×1920)

| Step | Time |
| --- | --- |
| Camera capture (hardware) | ~330 ms |
| Decode | ~25–50 ms |
| Draw | ~1–3 ms |
| Encode + write | ~90–105 ms |
| **Whole `takePicture()`** | **~460–540 ms** (first shot after opening ~650 ms) |

A capture with no stamp takes ~390 ms on the same device, so stamping adds
about 110 ms.

### Android caveats

- **EXIF is not kept.** The stamped file is a freshly encoded JPEG with no
  EXIF (no camera model, GPS or timestamp). If the real app needs metadata,
  write it with `androidx.exifinterface` after encoding. That is a new
  dependency, so it needs approval.
- **Memory:** the decoded bitmap is ARGB_8888, about 8 MB at 1080×1920 and
  about 48 MB at 12MP (`ResolutionPreset.max`), plus a second copy if
  rotation is needed. On low-RAM devices use `veryHigh`, or `sampleSize: 2`
  with `max`. `OutOfMemoryError` is caught and returned to Dart as a capture
  error.
- **Don't use CameraX effects for this.** An `OverlayEffect` cannot target
  `IMAGE_CAPTURE` alone in CameraX 1.6.2. Targeting the preview as well
  breaks the plugin's preview rotation and size. This was tried and removed.
- **Unused dependency:** `android/build.gradle.kts` still declares
  `androidx.camera:camera-effects`. Nothing uses it, so it can be removed.
- **R8/ProGuard:** the stamp code is registered directly in code, with no
  reflection, so it needs no keep rules.

### Android app configuration

| Item | Value in this repo | Production note |
| --- | --- | --- |
| `minSdk` | 23 (required by the plugin and CameraX) | Keep ≥ 23. |
| Java | 17 (plugin `compileOptions`) | Match your AGP setup. |
| CameraX | 1.6.2 (`cameraxVersion` in the plugin's Gradle file) | All CameraX artifacts must use the same version. |
| `CAMERA` permission | declared | Required. |
| `RECORD_AUDIO` | declared | Not needed: the app uses `enableAudio: false`. Remove it unless you record video with sound. |
| `READ/WRITE_EXTERNAL_STORAGE` | declared | Not needed: files go to the app cache directory. Remove them. |

## 3. iOS (`packages/camera_avfoundation`)

Files changed from upstream 0.11.1, in
`darwin/camera_avfoundation/Sources/camera_avfoundation/`:

| File | Change |
| --- | --- |
| `PhotoStamper.swift` | **New.** Channel handler, thread-safe settings (`NSLock`), and `stampedJPEG(from: AVCapturePhoto)`. Defaults, `sampleSize` and text style match Android. |
| `SavePhotoDelegate.swift` | In `photoOutput(_:didFinishProcessingPhoto:error:)`, returns the stamped JPEG when the target path ends in `.jpg`. Otherwise it falls back to `photo.fileDataRepresentation()`. |
| `CameraPlugin.swift` | Calls `PhotoStamper.register(messenger:)` in `register(with:)`. |
| `DefaultCamera.swift` | In `captureToFile`, sets `photoQualityPrioritization = .speed` when a stamp is set. The default `.balanced` runs Smart HDR or Deep Fusion processing, which made each capture noticeably slower. |

### iOS pipeline

Get an upright image:

- `sampleSize` 1: `AVCapturePhoto.cgImageRepresentation()` plus the EXIF
  orientation.
- `sampleSize` > 1: ImageIO `CGImageSourceCreateThumbnailAtIndex` decodes
  straight to the smaller size with the orientation applied. This is the iOS
  equivalent of `inSampleSize` on Android.

Then draw with `UIGraphicsImageRenderer` (scale 1, `preferredRange = .standard` so
wide-colour devices don't get a slower 16-bit context, regular system font, same
3.5% / 3% proportions and shadow as Android), and encode with
`CGImageDestination` at `quality`. The JPEG is
encoded once, and it runs on the plugin's `ioQueue`, not the main thread.

### iOS caveats

- **Untested on a device.** The code compiles (`flutter build ios
  --no-codesign`) but has not run on an iPhone. Test orientation, timing and
  memory first.
- **JPEG only.** If the plugin is set to HEIF (the path ends in `.heic`), the
  photo is saved without a stamp.
- **Metadata is kept, unlike Android.** The original metadata is copied,
  orientation is reset to 1 because the pixels are already upright, and the
  EXIF pixel dimensions are updated to the real output size.
- **SwiftPM and CocoaPods:** the fork has both `Package.swift` and
  `camera_avfoundation.podspec`. Keep the new file listed in whichever one
  your app uses. SwiftPM picks up every file in `Sources/` automatically. The
  podspec's `source_files` is
  `camera_avfoundation/Sources/camera_avfoundation/**/*.swift`, which already
  includes `PhotoStamper.swift`.
- **`Info.plist`:** `NSCameraUsageDescription` is required.
  `NSMicrophoneUsageDescription` is only needed if audio is enabled.

## 4. Bringing it into a production repo

### Option A: copy the forks (what this repo does)

1. Copy `packages/camera_android_camerax` and `packages/camera_avfoundation`
   into the production repo, for example under `packages/`.
2. Add the `dependency_overrides` block shown in section 1, with paths
   relative to the app's `pubspec.yaml`.
3. Copy `lib/photo_stamp.dart`, which is the channel wrapper and the
   `formatStamp` date formatter.
4. Fix the include line in
   `packages/camera_android_camerax/analysis_options.yaml` so it points at
   the production repo's root `analysis_options.yaml`. Upstream it points to
   the flutter/packages repo root, which doesn't exist here.
5. Exclude the forks' `test/`, `pigeons/` and `example/` folders in the root
   `analysis_options.yaml`. They need `mockito` and `pigeon`, which the app
   doesn't install:

   ```yaml
   analyzer:
     exclude:
       - packages/*/test/**
       - packages/*/pigeons/**
       - packages/*/example/**
   ```

6. Run `flutter pub get`. The `! … (overridden)` warnings are expected.
7. Do a full native rebuild (`flutter clean` and then `flutter run`). Hot
   reload never picks up Java or Swift changes.

### Option B: host the forks in their own repo

Push each fork to an internal git repo and use a git `dependency_overrides`
entry pinned to a commit or tag. This keeps the forks out of the app repo and
lets several apps share them. Pin a commit hash, not a branch, so builds are
reproducible.

### Option C: drop the forks later

If the extra ~100 ms of a Dart-side or app-level post-process is acceptable,
stamping could move into the app: decode, draw and encode after
`takePicture()`, in an isolate or a small app-owned plugin. The app could
then use the stock pub.dev plugins with no overrides. That is slower than the
in-plugin approach because the JPEG is encoded twice, but it removes the
upgrade burden.

## 5. Upgrading `camera` or the plugins

`camera 0.12.2` requires `camera_android_camerax ^0.7.6` and
`camera_avfoundation ^0.11.1`, which matches the forks. An override hides
version mismatches, so a mismatch only appears as a build or runtime error.

To upgrade:

1. Check on pub.dev which plugin versions the new `camera` release requires.
2. Download those plugin releases.
3. Re-apply the changes from the tables in sections 2 and 3. Search for
   `PhotoStamper` to find each hook point: three on Android, four on iOS.
4. Don't edit generated Pigeon files (`*.g.kt`, `*.g.dart`, `*.g.swift`).
   Upstream regenerates them, and the stamp code doesn't need them.
5. Run the test checklist below on both platforms.

## 6. Test checklist (real devices)

- [ ] Permission flow: allow; deny, then allow from Settings and retry.
- [ ] Stamp text is correct, bottom-right, and readable on a light background.
- [ ] Device held in portrait, landscape left and landscape right. The app
      UI is locked to portrait in `main.dart`, so check that the saved photo's
      orientation matches how the device was held.
- [ ] Flash off, auto and on.
- [ ] Back and front camera, if the production app uses both.
- [ ] 20+ shots in a row, watching memory, with no `OutOfMemoryError`.
- [ ] Capture time is acceptable on your lowest-spec target device.
- [ ] `clearStampText`: later photos have no stamp.
- [ ] Leave and reopen the camera screen: the camera is released, with no
      "camera in use" errors.
- [ ] iOS: everything above, since iOS hasn't been tested yet.
