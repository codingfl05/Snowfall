#!/bin/bash
set -e

APP_DIR=".build/Snowfall.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

mkdir -p "$MACOS_DIR"

swiftc -O Sources/Snowfall/*.swift -o "$MACOS_DIR/Snowfall"

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Snowfall</string>
    <key>CFBundleIdentifier</key>
    <string>com.codingfl05.snowfall</string>
    <key>CFBundleName</key>
    <string>Snowfall</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# iCloud Drive(Desktop)가 .app 폴더에 자동으로 붙이는 FinderInfo 속성을 제거해야 codesign이 성공함
xattr -dr com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
codesign --force --deep -s - "$APP_DIR"
