#!/usr/bin/env bash
# Baut die App mit eingebrannter Commit-Info (BUILD_COMMIT + BUILD_TIME),
# damit am Geraet sichtbar ist, welche Version drauf ist. Default:
# Debug-APK. --release schaltet auf Release um.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

MODE=debug
if [[ "${1:-}" == "--release" ]]; then MODE=release; fi

export PATH="$HOME/flutter/bin:$HOME/android-sdk/cmdline-tools/latest/bin:$HOME/android-sdk/platform-tools:$PATH"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

COMMIT=$(git -C .. rev-parse --short=10 HEAD)
TIME=$(date -u +"%Y-%m-%dT%H:%MZ")

echo "Build-APK ($MODE) commit=$COMMIT time=$TIME"

flutter build apk --$MODE \
    --dart-define=BUILD_COMMIT="$COMMIT" \
    --dart-define=BUILD_TIME="$TIME"

APK="build/app/outputs/flutter-apk/app-$MODE.apk"
echo "APK: $APK"
echo "SHA256: $(sha256sum "$APK" | awk '{print $1}')"
echo "size:   $(stat --printf='%s' "$APK") byte"
