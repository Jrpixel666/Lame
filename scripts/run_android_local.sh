#!/usr/bin/env bash
# Build and run this app on a connected Android device or emulator, entirely
# locally (no CI). Usage:
#   scripts/run_android_local.sh            # debug build, installs + runs on the first attached device
#   scripts/run_android_local.sh release    # release APK, built to build/app/outputs/flutter-apk/
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

mode="${1:-debug}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH — run scripts/setup_android_dev.sh first." >&2
  exit 1
fi

flutter pub get

if [ "$mode" = "release" ]; then
  echo "Building release APK (arm64)..."
  flutter build apk --release --target-platform android-arm64
  echo
  echo "APK: build/app/outputs/flutter-apk/app-arm64-release.apk"
  exit 0
fi

echo "Connected devices:"
flutter devices

echo
echo "Launching debug build on the default device (pass a device id as \$2 to target a specific one)..."
if [ -n "${2:-}" ]; then
  flutter run -d "$2"
else
  flutter run
fi
