#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR"
OUTPUT_DIR="/Users/liyifei/Downloads"
APP_NAME="MarkView"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

echo "=== Building $APP_NAME ==="

# Step 1: Generate icon
echo "Step 1: Generating app icon..."
python3 "$BUILD_DIR/generate_icon.py"

echo "Step 1b: Converting to .icns..."
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
echo "  Created AppIcon.icns"

# Step 2: Compile Swift
echo "Step 2: Compiling Swift..."
swiftc "$BUILD_DIR/main.swift" \
    -o "$BUILD_DIR/$APP_NAME" \
    -framework AppKit \
    -framework WebKit \
    -swift-version 5 \
    -O
echo "  Compiled $APP_NAME binary"

# Step 3: Assemble .app bundle
echo "Step 3: Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$BUILD_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy HTML
cp "$PROJECT_DIR/index.html" "$APP_BUNDLE/Contents/Resources/index.html"

# Copy icon
cp "$BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "  Bundle created at: $APP_BUNDLE"

# Step 4: Touch to refresh Finder
touch "$APP_BUNDLE"

echo ""
echo "=== Build Complete ==="
echo "  $APP_BUNDLE"
echo "  Double-click to open, or run:"
echo "  open \"$APP_BUNDLE\""
