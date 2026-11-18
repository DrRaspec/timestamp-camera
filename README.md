# customize_camera

Flutter camera app that takes several photos in a row and burns a name and
time stamp into each saved photo, for example:

```text
Luo Mao
2026 Nov 16 1:53PM
```

The stamp is drawn natively on the saved JPEG, not on the live preview. The
preview only shows a Flutter overlay with the same text.

## Run

```sh
flutter pub get
flutter run
```

If you change any Java, Kotlin or Swift code in `packages/`, stop the app and
run `flutter run` again. Hot reload and hot restart do not reload native code.

## App structure

GetX handles state and navigation.

| File | Purpose |
| --- | --- |
| `lib/main.dart` | `GetMaterialApp` with the routes from `routes.dart` |
| `lib/routes.dart` | Routes and the binding that creates each screen's controller |
| `lib/start_screen.dart`, `controllers/start_controller.dart` | Asks for camera permission, then opens the camera |
| `lib/camera_screen.dart`, `controllers/camera_screen_controller.dart` | Preview, flash, grid, quality, shutter, photo strip (newest first), Done/close |
| `lib/photo_view_sheet.dart`, `controllers/photo_view_controller.dart` | Photo viewer in a bottom sheet: swipe between photos, pinch to zoom, thumbnail strip, delete. Close with the round button at the top right or by dragging the sheet or the photo down |
| `lib/photo_stamp.dart` | Dart side of the `photo_stamp` method channel, including the quality range and default |

`CameraScreenController` is named that way to avoid clashing with the
`camera` package's `CameraController`.

## Dependency overrides

If you're moving the stamp into another app, see
[docs/NATIVE_INTEGRATION.md](docs/NATIVE_INTEGRATION.md). It covers the
native pipelines, the channel contract, platform configuration, integration
options and a device test checklist.

The stamp needs native code inside the camera plugins, so `pubspec.yaml`
replaces the two platform plugins with local copies:

```yaml
dependency_overrides:
  camera_android_camerax:
    path: packages/camera_android_camerax
  camera_avfoundation:
    path: packages/camera_avfoundation
```

`camera` is the package the app uses directly. Behind it, it uses
`camera_android_camerax` on Android and `camera_avfoundation` on iOS. The
overrides make Flutter build these local copies instead of the versions on
pub.dev.

### What the local copies change

Both copies are based on the current pub.dev releases.

**`camera_android_camerax` 0.7.6+1** (Android)

- `PhotoStamper.java` (new) registers the `photo_stamp` channel and draws the
  stamp. It decodes the captured JPEG from memory (optionally downscaled with
  `sampleSize`; default 1, full size), turns it upright, draws the text in
  the bottom-right and writes the file at `quality` (default 60).
- `ImageCaptureProxyApi.java`: when a stamp is set, `takePicture()` captures
  to memory and lets `PhotoStamper` write the only file on a background
  thread. The path is returned before the file is finished, so wait for
  `PhotoStamp.waitUntilWritten(path)` before using the file. Without a stamp
  it saves the file the stock way.
- `CameraAndroidCameraxPlugin.java` calls `PhotoStamper.register(...)`.
- `lib/src/android_camera_camerax.dart`: camera JPEG quality 85 at creation
  and JPEG quality 85 are the defaults and are applied when the camera is
  created. Calling `setZeroShutterLagEnabled` or `setJpegImageQuality` after
  the camera opens rebuilds the capture pipeline, which made the preview
  flicker on open and glitch on the first shot.
- `lib/src/image_reader_rotated_preview.dart` and
  `surface_texture_rotated_preview.dart`: the preview keeps its previous
  rotation while a new one is fetched. Upstream showed an empty box for a
  frame on every device orientation event, so the preview blinked black
  shortly after opening and when the phone was tilted.

**`camera_avfoundation` 0.11.1** (iOS)

- `PhotoStamper.swift` (new) is the iOS version of the stamper.
- `SavePhotoDelegate.swift` stamps the photo before it is written.
- `CameraPlugin.swift` calls `PhotoStamper.register(...)`.
- `PhotoStamper.swift` supports the same `sampleSize` and `quality` defaults
  as Android.

### What you need to do

1. **Keep the overrides in `pubspec.yaml`.** If you remove them, the app
   builds against the pub.dev plugins. The stamp then disappears, and
   `PhotoStamp.setText` throws `MissingPluginException`.

2. **Ignore the "overridden" warning.** `flutter pub get` prints this, and
   it is expected:

   ```text
   ! camera_android_camerax 0.7.6+1 from path packages/camera_android_camerax (overridden)
   ! camera_avfoundation 0.11.1 from path packages/camera_avfoundation (overridden)
   ```

3. **Pin `camera` to versions that match the copies.** `camera: ^0.12.2`
   requires `camera_android_camerax ^0.7.6` and `camera_avfoundation ^0.11.1`,
   which matches the copies. Before upgrading `camera`, check which plugin
   versions the new release requires on pub.dev. If they are newer than the
   copies, either keep `camera` where it is or update the copies (step 4).
   An override hides version mismatches, so a mismatch shows up as a build or
   runtime error, not as a `pub get` error.

4. **Update a copy to a newer upstream release:**
   1. Download the new release of the plugin from pub.dev or the
      [flutter/packages](https://github.com/flutter/packages) repo.
   2. Copy the changes listed above into it. Search for `PhotoStamper` to
      find every place the changes touch.
   3. Replace the folder under `packages/`.
   4. Fix the first line of its `analysis_options.yaml` to
      `include: ../../analysis_options.yaml` (see below).
   5. Run `flutter pub get`, then `flutter run` on a real Android device and
      a real iPhone. Take a photo and check the stamp.

5. **Don't edit the plugin's generated Pigeon files** (`*.g.kt`, `*.g.dart`,
   `*.g.swift`). Put custom code in separate files such as `PhotoStamper`,
   which keeps future upgrades simple.

### Analyzer setup for the copies

The copies came from the flutter/packages repo with their tests, Pigeon
definitions and example apps. Those folders need packages this app doesn't
install, such as `mockito` and `pigeon`, so the root `analysis_options.yaml`
excludes them:

```yaml
analyzer:
  exclude:
    - packages/*/test/**
    - packages/*/pigeons/**
    - packages/*/example/**
```

`packages/camera_android_camerax/analysis_options.yaml` includes
`../../analysis_options.yaml`. The original pointed to
`../../../analysis_options.yaml`, the flutter/packages repo root, which
doesn't exist here.

You can't run the plugins' own tests from this project. The app doesn't need
them.

### Cleanup

- `camera_android_camerax/android/build.gradle.kts` still lists
  `androidx.camera:camera-effects`. Nothing uses it any more, so it can be
  removed.

## Notes

- The saved photo's JPEG quality defaults to 60 and can be changed by the
  user with the percentage button at the top of the camera screen (20–100%).
  It applies from the next photo. The setting is not remembered between
  camera sessions.
- The camera uses `ResolutionPreset.veryHigh`, so Android photos are
  1080×1920 and match the 16:9 preview. On a PLF110 this takes about 500 ms
  per photo (camera capture about 330 ms, stamping about 115–155 ms), compared with about 930 ms for
  `ResolutionPreset.max` (12MP) downscaled by half. Zero-shutter-lag is
  off, because it can return an older frame after a quick camera move. The
  camera's JPEG quality is 85, because the stamper re-encodes the photo anyway.
- An earlier version used CameraX `OverlayEffect` for the stamp. It cannot
  target photo capture alone, and applying it to the preview broke the
  preview's rotation and size. Don't bring it back.
