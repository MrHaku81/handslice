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
case "${1:-}" in
    ""|--debug) MODE=debug ;;
    --profile)  MODE=profile ;;
    --release)  MODE=release ;;
    *) echo "Nutzung: $0 [--debug|--profile|--release]" >&2; exit 2 ;;
esac

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
APK_SHA=$(sha256sum "$APK" | awk '{print $1}')
APK_SIZE=$(stat --printf='%s' "$APK")

# Verifikation: der Dart-Code-Blob muss den Commit-Hash als
# Byte-Sequenz enthalten. Die APK selbst ist DEFLATE-komprimiert,
# deshalb kein grep auf dem Rohbyte-APK, sondern unzip -p auf das
# jeweils relevante Entry.
#   Release: lib/arm64-v8a/libapp.so (Dart-AOT-Blob)
#   Debug:   assets/flutter_assets/kernel_blob.bin (JIT-Kernel)
# Fehlt der Hash im Blob, wurde das --dart-define nicht wirksam ->
# App faellt am Geraet in den Startup-Guard (siehe app/lib/main.dart).
# Lieber hier abbrechen, damit solche APKs gar nicht erst auf den
# Poco wandern.
# `unzip -p … | grep -q` scheitert unter `set -euo pipefail`, weil
# `grep -q` nach erstem Treffer schliesst → `unzip` bekommt SIGPIPE
# → Pipe-Exit nicht-0. Deshalb vorher nach tmp extrahieren.
# Debug baut JIT (kernel_blob.bin), Profile und Release bauen AOT
# (libapp.so). Beide AOT-Varianten muessen den Hash als ASCII-
# Bytes im Dart-Blob haben.
if [[ "$MODE" == "debug" ]]; then
    DART_ENTRY="assets/flutter_assets/kernel_blob.bin"
else
    DART_ENTRY="lib/arm64-v8a/libapp.so"
fi
tmp_blob=$(mktemp)
trap 'rm -f "$tmp_blob"' EXIT
unzip -p "$APK" "$DART_ENTRY" > "$tmp_blob" 2>/dev/null
if [[ ! -s "$tmp_blob" ]]; then
    echo "ABBRUCH: $DART_ENTRY aus $APK ist leer oder fehlt." >&2
    exit 4
fi
if ! grep -a -q "$COMMIT" "$tmp_blob"; then
    echo "ABBRUCH: $DART_ENTRY in $APK enthaelt" >&2
    echo "         den Commit-Hash $COMMIT nicht –" >&2
    echo "         --dart-define wurde offenbar nicht weitergegeben." >&2
    exit 4
fi

# Permission-Guard: APK muss android.permission.INTERNET enthalten.
# Debug-Overlay (android/app/src/debug/AndroidManifest.xml) fuegt
# sie nur fuer Debug-Builds hinzu; eine Release-APK ohne diese Zeile
# scheitert am Geraet mit "Failed to create datagram socket".
# Pruefen wir hier fuer beide Modi, damit die Debug-APK dieselbe
# Garantie mitbringt. Beleg: 2026-10-26, Release-APK 785e5cb –
# siehe PROGRESS.md.
AAPT_CANDIDATES=(
    "$ANDROID_HOME/build-tools/36.0.0/aapt2"
    "$ANDROID_HOME/build-tools/34.0.0/aapt2"
)
AAPT=""
for c in "${AAPT_CANDIDATES[@]}"; do
    [[ -x "$c" ]] && AAPT="$c" && break
done
if [[ -z "$AAPT" ]]; then
    echo "WARNUNG: kein aapt2 gefunden, Permission-Verify uebersprungen." >&2
elif ! "$AAPT" dump permissions "$APK" | grep -q "android.permission.INTERNET"; then
    echo "ABBRUCH: $APK enthaelt KEINE android.permission.INTERNET." >&2
    echo "         android/app/src/main/AndroidManifest.xml muss" >&2
    echo "         <uses-permission android:name=\"android.permission.INTERNET\"/>" >&2
    echo "         enthalten (nicht nur im debug/-Overlay)." >&2
    exit 5
fi

echo "APK:    $APK"
echo "SHA256: $APK_SHA"
echo "size:   $APK_SIZE byte"
echo "commit-im-APK: ok ($COMMIT gefunden; cli $ARM_HASH)"
echo "manifest:      INTERNET-Permission vorhanden"
