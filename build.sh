#!/bin/bash
set -e

APP_DIR=".build/Snowfall.app"
STAGE_DIR="$(mktemp -d /tmp/snowfall-build.XXXXXX)"
STAGE_APP="$STAGE_DIR/Snowfall.app"
CONTENTS_DIR="$STAGE_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

trap 'rm -rf "$STAGE_DIR"' EXIT

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

# iCloud Drive(Desktop)가 .app에 FinderInfo를 붙여 codesign이 실패하는 현상을 방지하기 위해 /tmp에서 서명 후 이동
# 자체 서명 인증서 "Snowfall Dev"가 있으면 사용해 리빌드 후에도 손쉬운 사용(Accessibility) 권한을 유지하고,
# 없으면 경고를 출력한 뒤 ad-hoc(-s -) 서명으로 대체함.
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq '"Snowfall Dev"'; then
    codesign --force --deep -s "Snowfall Dev" "$STAGE_APP"
else
    echo "warning: 'Snowfall Dev' certificate not found; falling back to ad-hoc signing (-s -)." >&2
    codesign --force --deep -s - "$STAGE_APP"
fi

mkdir -p .build
rm -rf "$APP_DIR"
mv "$STAGE_APP" "$APP_DIR"
