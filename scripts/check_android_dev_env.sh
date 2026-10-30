#!/usr/bin/env bash
# Checks whether this machine is ready for local Android development on
# this project, without installing or changing anything. Run it before
# setup_android_dev.sh or run_android_local.sh.
set -uo pipefail

ok=1

check() {
  local label="$1"
  local cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  [ok]   %-10s %s\n' "$label" "$(command -v "$cmd")"
  else
    printf '  [MISS] %-10s not found on PATH\n' "$label"
    ok=0
  fi
}

echo "== Toolchain =="
check "flutter" flutter
check "dart" dart
check "java" java
check "adb" adb

echo
echo "== Android SDK =="
if [ -n "${ANDROID_HOME:-}" ]; then
  echo "  ANDROID_HOME=$ANDROID_HOME"
elif [ -n "${ANDROID_SDK_ROOT:-}" ]; then
  echo "  ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
else
  echo "  [MISS] ANDROID_HOME / ANDROID_SDK_ROOT not set"
  ok=0
fi

echo
if command -v flutter >/dev/null 2>&1; then
  echo "== flutter doctor -v (Android section) =="
  flutter doctor -v 2>/dev/null | awk '/Android/{p=1} p' | sed -n '1,25p'
fi

echo
if [ "$ok" -eq 1 ]; then
  echo "Environment looks ready. Run scripts/run_android_local.sh next."
else
  echo "Missing pieces above. Run scripts/setup_android_dev.sh for install instructions."
fi
