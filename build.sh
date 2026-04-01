#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="KickMyMac"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/audio"

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy audio files
if [ -d "$SCRIPT_DIR/audio" ]; then
    cp "$SCRIPT_DIR/audio/"*.mp3 "$APP_BUNDLE/Contents/Resources/audio/" 2>/dev/null || true
    echo "Copied $(ls "$APP_BUNDLE/Contents/Resources/audio/"*.mp3 2>/dev/null | wc -l | tr -d ' ') audio files"
fi

# Compile Swift
swiftc \
    -O \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -framework AVFoundation \
    "$SCRIPT_DIR/$APP_NAME.swift"

echo "Built: $APP_BUNDLE"
echo ""
echo "Run:  open $APP_BUNDLE"
