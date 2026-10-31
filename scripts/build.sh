#!/usr/bin/env bash
#
# Headless build of the d3d example project.
#
# Downloads a pinned JDK 25 and the matching Defold bob.jar into .tools/ on the
# first run. Both are git-ignored, so a fresh clone only needs curl + tar.
#
# Usage:
#   scripts/build.sh [extra bob arguments]
#   PLATFORM=x86_64-win32 scripts/build.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/.tools"
JRE_DIR="$TOOLS/jre25"
BOB="$TOOLS/bob.jar"
BOB_VERSION="1.14.0"
PLATFORM="${PLATFORM:-x86_64-linux}"

mkdir -p "$TOOLS"

if [ ! -x "$JRE_DIR/bin/java" ]; then
    echo "Downloading Temurin JRE 25..."
    curl -fsSL --retry 3 -o "$TOOLS/jre25.tar.gz" \
        "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jre/hotspot/normal/eclipse?project=jdk"
    mkdir -p "$JRE_DIR"
    tar -xzf "$TOOLS/jre25.tar.gz" -C "$JRE_DIR" --strip-components=1
    rm -f "$TOOLS/jre25.tar.gz"
fi

if [ ! -f "$BOB" ]; then
    echo "Downloading Defold bob $BOB_VERSION..."
    curl -fsSL --retry 3 -o "$BOB" \
        "https://github.com/defold/defold/releases/download/$BOB_VERSION/bob.jar"
fi

"$JRE_DIR/bin/java" -jar "$BOB" \
    --root "$ROOT" \
    --platform "$PLATFORM" \
    build "$@"
