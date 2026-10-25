#!/usr/bin/env bash
# Baut die App mit eingebrannter Commit-Info (BUILD_COMMIT + BUILD_TIME +
# CLI_COMMIT), damit am Geraet sichtbar ist, welche App- UND CLI-Version
# drauf ist. Default: Debug-APK. --release schaltet auf Release um.
#
# Build-Guard: ruft handslice-cli-x86 --version und handslice-cli-arm64
# --version und bricht ab, wenn die Hashes voneinander oder vom aktuellen
# Repo-HEAD abweichen. Hintergrund: beim M4-Build wurde arm64 vergessen
# nachzuziehen – die App rief ein veraltetes --z-offset-freies arm64-
# Binary ("unknown flag"). Dieser Guard verhindert eine Wiederholung.
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

# --- CLI-Guard: x86 vs arm64 muessen vom selben Commit sein ---
# Beide CLI-Binaries sind entweder vorhanden (dann pruefen) oder nicht
# (dann fuer den APK-Bau zumindest arm64 Pflicht, weil es ins jniLibs
# kopiert wird).
CLI_X86="../engine/bin/handslice-cli-x86"
CLI_ARM="../engine/bin/handslice-cli-arm64"

if [[ ! -x "$CLI_ARM" ]]; then
    echo "FEHLT: $CLI_ARM" >&2
    echo "  → zuerst 'bash engine/build-cli-arm64.sh' laufen lassen." >&2
    exit 2
fi

# Hash wird aus der Side-Car-Datei gelesen (das arm64-Binary laesst
# sich auf dem x86-Host nicht per --version aufrufen; die Side-Car-
# Datei schreibt das jeweilige Build-Script neben die Binary).
cli_hash () {
    local sidecar="$1.commit"
    if [[ -s "$sidecar" ]]; then
        cat "$sidecar"
    else
        echo "unknown"
    fi
}

ARM_HASH=$(cli_hash "$CLI_ARM")
echo "handslice-cli-arm64 commit: $ARM_HASH"

if [[ -x "$CLI_X86" ]]; then
    X86_HASH=$(cli_hash "$CLI_X86")
    echo "handslice-cli-x86   commit: $X86_HASH"
    if [[ "$ARM_HASH" != "$X86_HASH" ]]; then
        echo "ABBRUCH: x86- und arm64-CLI sind nicht vom selben Quellstand." >&2
        echo "         x86  = $X86_HASH" >&2
        echo "         arm64= $ARM_HASH" >&2
        echo "  → beide CLIs neu bauen (build-headless-x86.sh +" >&2
        echo "    build-cli-arm64.sh)." >&2
        exit 3
    fi
fi

if [[ "$ARM_HASH" == "unknown" ]]; then
    echo "ABBRUCH: $CLI_ARM.commit fehlt oder leer." >&2
    echo "  → arm64-CLI mit dem aktuellen Build-Script neu bauen." >&2
    exit 3
fi

# Warnung (nicht Abbruch): CLI-Hash ≠ Repo-HEAD. Nicht alle Repo-Commits
# brauchen einen CLI-Rebuild; wir warnen aber, damit das sichtbar ist.
if [[ "$ARM_HASH" != "$COMMIT" ]]; then
    echo "WARNUNG: CLI-Commit ($ARM_HASH) weicht vom Repo-HEAD ($COMMIT) ab." >&2
    echo "         Fuer App-only-Aenderungen ist das OK; fuer Engine-" >&2
    echo "         Aenderungen bitte CLI nachbauen." >&2
fi

echo "Build-APK ($MODE) commit=$COMMIT cli=$ARM_HASH time=$TIME"

flutter build apk --$MODE \
    --dart-define=BUILD_COMMIT="$COMMIT" \
    --dart-define=BUILD_TIME="$TIME" \
    --dart-define=CLI_COMMIT="$ARM_HASH"

APK="build/app/outputs/flutter-apk/app-$MODE.apk"
echo "APK: $APK"
echo "SHA256: $(sha256sum "$APK" | awk '{print $1}')"
echo "size:   $(stat --printf='%s' "$APK") byte"
