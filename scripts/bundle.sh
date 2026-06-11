#!/bin/bash
# Builds an optimized release binary with swiftc (works with Command Line
# Tools alone — CLT's SwiftPM can't resolve the platform path) and wraps it
# into a signed MacPulse.app.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build dist

echo "→ Compiling release binary (swiftc -O -wmo)…"
swiftc -O -whole-module-optimization -parse-as-library \
    Sources/MacPulse/*.swift \
    Sources/MacPulse/Views/*.swift \
    -o .build/MacPulse-release

APP="dist/MacPulse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/MacPulse-release "$APP/Contents/MacOS/MacPulse"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

echo "→ Stripping symbols…"
strip -Sx "$APP/Contents/MacOS/MacPulse" 2>/dev/null || true

echo "→ Code-signing (ad-hoc, hardened runtime)…"
codesign --force --sign - --options runtime "$APP"
codesign --verify --strict "$APP"

echo "✓ Built $APP ($(du -sh "$APP" | cut -f1))"
