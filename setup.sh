#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
#  PostureGuard — Automated Setup Script
#  Run this once inside your project folder:  bash setup.sh
# ═══════════════════════════════════════════════════════════════════

set -e  # Stop on any error

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     PostureGuard Setup Script        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Step 1: Check Flutter is installed ───────────────────────────────────────
echo "▶ Checking Flutter installation..."
if ! command -v flutter &> /dev/null; then
    echo ""
    echo "  Flutter is not installed. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "  Installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install --cask flutter
    echo "  ✓ Flutter installed"
else
    echo "  ✓ Flutter already installed: $(flutter --version | head -1)"
fi

# ── Step 2: Check Xcode (needed for iOS builds) ───────────────────────────────
echo ""
echo "▶ Checking Xcode..."
if ! command -v xcodebuild &> /dev/null; then
    echo "  ⚠ Xcode not found. Please install Xcode from the Mac App Store."
    echo "    Then run: sudo xcode-select --switch /Applications/Xcode.app"
else
    echo "  ✓ Xcode found: $(xcodebuild -version | head -1)"
fi

# ── Step 3: Accept Xcode license ─────────────────────────────────────────────
echo ""
echo "▶ Accepting Xcode license..."
sudo xcodebuild -license accept 2>/dev/null || echo "  ⚠ Could not auto-accept license — run: sudo xcodebuild -license accept"

# ── Step 4: Check CocoaPods (needed for iOS Flutter packages) ────────────────
echo ""
echo "▶ Checking CocoaPods..."
if ! command -v pod &> /dev/null; then
    echo "  Installing CocoaPods..."
    sudo gem install cocoapods
    echo "  ✓ CocoaPods installed"
else
    echo "  ✓ CocoaPods found: $(pod --version)"
fi

# ── Step 5: Create Flutter project if it doesn't exist ───────────────────────
echo ""
echo "▶ Checking Flutter project..."
if [ ! -f "pubspec.yaml" ]; then
    echo "  No Flutter project found. Creating PostureGuard..."
    flutter create . --project-name postureguard --org com.postureguard --platforms android,ios
    echo "  ✓ Flutter project created"
else
    echo "  ✓ Flutter project already exists"
fi

# ── Step 6: Copy pubspec.yaml with all dependencies ───────────────────────────
echo ""
echo "▶ Writing pubspec.yaml with all dependencies..."
cat > pubspec.yaml << 'PUBSPEC'
name: postureguard
description: Real-time smartphone posture monitor using front camera and Google ML Kit.
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  google_mlkit_pose_detection: ^0.10.0
  camera: ^0.10.5+9
  flutter_tts: ^4.0.2
  vibration: ^1.8.4
  fl_chart: ^0.68.0
  sqflite: ^2.3.2
  path: ^1.9.0
  shared_preferences: ^2.2.3
  cupertino_icons: ^1.0.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
PUBSPEC
echo "  ✓ pubspec.yaml written"

# ── Step 7: Write .env file ───────────────────────────────────────────────────
echo ""
echo "▶ Writing .env configuration file..."
cat > .env << 'ENVFILE'
# PostureGuard Environment Configuration
# ─────────────────────────────────────────────────────────────────

# App Settings
APP_NAME=PostureGuard
APP_VERSION=1.0.0

# Posture Detection Thresholds (defaults — overridden by personal calibration)
DEFAULT_SHOULDER_SYMMETRY_THRESHOLD=0.05
DEFAULT_HEAD_TILT_THRESHOLD=0.04
DEFAULT_SHOULDER_WIDTH_THRESHOLD=0.25
DEFAULT_HEAD_DROP_THRESHOLD=0.10

# Feedback Settings
VOICE_ALERT_TRIGGER_SECONDS=10
VOICE_ALERT_COOLDOWN_SECONDS=30
SCORE_ROLLING_WINDOW_FRAMES=30
BORDER_SMOOTHING_SECONDS=2
STREAK_RESET_BAD_SECONDS=3

# Session Settings
SESSION_LOG_INTERVAL_SECONDS=1
CALIBRATION_DURATION_SECONDS=5
DEFAULT_DAILY_GOAL_PERCENT=80

# Optional Flask Backend (leave empty to use local-only mode)
FLASK_BASE_URL=
FLASK_PORT=5000

# Build Targets
ANDROID_MIN_SDK=21
IOS_DEPLOYMENT_TARGET=12.0
ENVFILE
echo "  ✓ .env file written"

# ── Step 8: Add Android camera permission ─────────────────────────────────────
echo ""
echo "▶ Adding Android camera permission..."
MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
    if ! grep -q "android.permission.CAMERA" "$MANIFEST"; then
        sed -i '' 's/<manifest/<manifest\n    xmlns:tools="http:\/\/schemas.android.com\/tools"/' "$MANIFEST" 2>/dev/null || true
        sed -i '' 's/<application/<uses-permission android:name="android.permission.CAMERA"\/>\n    <uses-feature android:name="android.hardware.camera" android:required="true"\/>\n    <application/' "$MANIFEST"
        echo "  ✓ Camera permission added to AndroidManifest.xml"
    else
        echo "  ✓ Camera permission already present"
    fi
fi

# ── Step 9: Add iOS camera permission ────────────────────────────────────────
echo ""
echo "▶ Adding iOS camera permission..."
PLIST="ios/Runner/Info.plist"
if [ -f "$PLIST" ]; then
    if ! grep -q "NSCameraUsageDescription" "$PLIST"; then
        sed -i '' 's/<\/dict>/<key>NSCameraUsageDescription<\/key>\n\t<string>PostureGuard needs camera access to monitor your posture in real time.<\/string>\n<\/dict>/' "$PLIST"
        echo "  ✓ Camera permission added to Info.plist"
    else
        echo "  ✓ Camera permission already present"
    fi
fi

# ── Step 10: Set iOS minimum deployment target ────────────────────────────────
echo ""
echo "▶ Setting iOS minimum deployment target..."
PODFILE="ios/Podfile"
if [ -f "$PODFILE" ]; then
    sed -i '' "s/# platform :ios, '12.0'/platform :ios, '12.0'/" "$PODFILE" 2>/dev/null || true
    sed -i '' "s/platform :ios, '[0-9.]*'/platform :ios, '12.0'/" "$PODFILE" 2>/dev/null || true
    echo "  ✓ iOS deployment target set to 12.0"
fi

# ── Step 11: Install Flutter packages ────────────────────────────────────────
echo ""
echo "▶ Running flutter pub get (installing all packages)..."
flutter pub get
echo "  ✓ All Flutter packages installed"

# ── Step 12: Install iOS CocoaPods ───────────────────────────────────────────
echo ""
echo "▶ Installing iOS CocoaPods dependencies..."
if [ -d "ios" ]; then
    cd ios
    pod install --repo-update
    cd ..
    echo "  ✓ CocoaPods dependencies installed"
fi

# ── Step 13: Run flutter doctor ──────────────────────────────────────────────
echo ""
echo "▶ Running flutter doctor to check full setup..."
echo ""
flutter doctor
echo ""

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  Setup Complete!                         ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║  Connect your Android phone via USB and run:            ║"
echo "║    flutter run -d android                               ║"
echo "║                                                          ║"
echo "║  Connect your iPhone via USB and run:                   ║"
echo "║    flutter run -d ios                                   ║"
echo "║                                                          ║"
echo "║  Build Android APK:                                      ║"
echo "║    flutter build apk --release                          ║"
echo "║                                                          ║"
echo "║  Build iPhone (TestFlight):                             ║"
echo "║    flutter build ipa --release                          ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Open the project in VS Code:"
echo "    code ."
echo ""