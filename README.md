# PostureGuard

Real-time posture monitor for Android. Uses the front camera and accelerometer together to detect poor posture and alert you with voice + vibration feedback.

---

## How it works

PostureGuard places your phone in front of you (propped up or held) and uses Google ML Kit to track 5 skeletal landmarks in every camera frame — nose, both ears, both shoulders. It computes a **Nose-to-Shoulder (NTS) ratio** that is scale-invariant and position-independent, then compares it against a personal baseline captured during calibration.

The accelerometer runs in parallel. The gravity vector at calibration time is stored alongside the camera baseline. During a session, the signed pitch angle between the two gravity vectors is used to confirm or independently trigger phone-position violations — this handles cases where the shoulders drift off-screen and the camera alone becomes unreliable.

### Detected violations

| Violation | Signal |
|-----------|--------|
| Phone too high | NTS drop + gravity pitch |
| Phone too low | NTS rise + gravity pitch |
| Shoulder asymmetry | Per-shoulder Y delta vs. baseline |
| Head tilt | Ear-height difference vs. baseline |
| Shoulder rounding | Shoulder width narrowing vs. baseline |

Phone-position violations suppress all body checks while active — perspective distortion from an extreme phone angle makes shoulder/head readings unreliable, so they are ignored until the phone returns to a normal position.

### Scoring

Each frame produces an overall score (0–100 %) averaged from five per-metric scores. A 30-frame rolling window smooths the score for the UI. An alert fires (voice + vibration) after 5 consecutive seconds below 50 %, with a 5-second cooldown between alerts. EMA smoothing (α = 0.15) on the NTS value prevents single noisy frames from flipping the phone-position state.

---

## Features

- Personal calibration — your own posture and phone angle are the baseline, not a generic model
- Real-time skeleton overlay drawn on the camera preview
- Ambient border that changes color with posture status (green / yellow / red)
- Score meter updated every frame
- Voice alerts via TTS + haptic vibration
- Android foreground service — monitoring continues when the app is in the background
- Ghost overlay (draw-over-apps) showing live score on top of any app
- Session history stored locally in SQLite with per-session charts
- Dark mode support

---

## Requirements

- **Android 5.0+ (API 21+)**
- Front-facing camera
- The following permissions are requested at runtime or on first use:
  - Camera
  - Notifications (for foreground service)
  - Draw over other apps (for ghost overlay)
  - Write system settings (for brightness control)

---

## Setup

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.x
- Android Studio or VS Code with the Flutter extension
- Android device or emulator (API 21+)

### Install

```bash
git clone <repo-url>
cd PostureGuard
flutter pub get
```

Or run the automated setup script (installs Flutter via Homebrew if missing, writes config files, checks permissions):

```bash
bash setup.sh
```

### Run

Connect an Android device via USB with developer mode and USB debugging enabled, then:

```bash
flutter run
```

### Build release APK

```bash
flutter build apk --release
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

---

## Project structure

```
lib/
├── main.dart                   # App entry point, background service init
├── background_service.dart     # Android foreground service setup
│
├── models/
│   ├── calibration_data.dart   # Stored baseline landmarks + accel vector
│   ├── posture_status.dart     # good / warning / bad enum
│   └── session_summary.dart    # Per-session stats model
│
├── services/
│   ├── camera_service.dart     # CameraX controller (NV21 format)
│   ├── detection_service.dart  # ML Kit pose detection + landmark normalization
│   ├── posture_analyzer.dart   # NTS ratio, accel pitch, violation detection
│   ├── feedback_service.dart   # TTS alerts, vibration, score window, streak
│   ├── calibration_service.dart
│   ├── movement_service.dart   # Accelerometer EMA smoothing
│   ├── overlay_service.dart    # Native overlay channel (SYSTEM_ALERT_WINDOW)
│   └── database_service.dart   # SQLite session persistence
│
├── screens/
│   ├── home_screen.dart        # Last session summary + navigation
│   ├── calibration_screen.dart # 5-second baseline capture
│   ├── session_screen.dart     # Live monitoring
│   ├── summary_screen.dart     # End-of-session results
│   └── history_screen.dart     # Past sessions with charts
│
└── widgets/
    ├── camera_preview.dart
    ├── skeleton_overlay.dart
    ├── ambient_border.dart
    ├── score_meter.dart
    ├── baseline_overlay.dart
    └── heatmap_chart.dart

android/
└── app/src/main/kotlin/com/postureguard/postureguard/
    ├── MainActivity.kt
    └── OverlayService.kt       # Native foreground overlay service
```

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `google_mlkit_pose_detection` | Skeleton landmark detection |
| `camera` | Camera preview and frame stream (CameraX) |
| `sensors_plus` | Accelerometer data |
| `flutter_background_service` | Android foreground service |
| `flutter_local_notifications` | Foreground service notification channel |
| `flutter_tts` | Voice feedback |
| `vibration` | Haptic feedback |
| `sqflite` | Local session history database |
| `fl_chart` | Session history charts |
| `permission_handler` | Runtime permission requests |
| `wakelock_plus` | Keep screen on during sessions |
| `shared_preferences` | Calibration persistence |
