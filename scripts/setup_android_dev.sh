#!/usr/bin/env bash
# One-time local setup for Android development on this project.
# Safe to re-run. Does not touch anything outside the Flutter/Android SDKs
# it is pointed at, and never auto-installs the SDKs themselves — it tells
# you how, since that differs by OS and by how much you already have.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "== Uncensored Local AI — Android dev setup =="
echo

if ! command -v flutter >/dev/null 2>&1; then
  cat <<'EOF'
Flutter SDK not found on PATH.

Install it with:
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
  export PATH="$HOME/flutter/bin:$PATH"   # add this line to your shell profile

Then re-run this script.
EOF
  exit 1
fi

echo "Flutter found: $(flutter --version | head -n1)"

if ! command -v java >/dev/null 2>&1; then
  cat <<'EOF'

Java (JDK 17, matching android/app/build.gradle.kts) not found.
Install it with your OS package manager, e.g.:
  Ubuntu/Debian: sudo apt install openjdk-17-jdk
  macOS (brew):  brew install openjdk@17
EOF
  exit 1
fi
echo "Java found: $(java -version 2>&1 | head -n1)"

if [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  cat <<'EOF'

Android SDK not detected (ANDROID_HOME / ANDROID_SDK_ROOT unset).
Easiest path: install Android Studio (https://developer.android.com/studio),
open this project once so it downloads the SDK, then export in your shell
profile:
  export ANDROID_HOME="$HOME/Android/Sdk"
  export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"

Then re-run this script.
EOF
  exit 1
fi
echo "Android SDK: ${ANDROID_HOME:-$ANDROID_SDK_ROOT}"

echo
echo "Fetching Flutter packages..."
flutter pub get

echo
echo "Running flutter doctor (fix anything it flags under Android before building)..."
flutter doctor

cat <<'EOF'

Setup looks good. Next steps:
  scripts/check_android_dev_env.sh   # re-verify anytime
  scripts/run_android_local.sh       # build/install a debug APK on a connected device or emulator
EOF
