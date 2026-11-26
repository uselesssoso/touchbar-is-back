#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -rf .build-arm64 .build-x86_64 QuotaBar.app TouchBack.app QuotaBar-universal.zip TouchBack-universal.zip

for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --scratch-path ".build-$arch"
done

BIN_ARM=".build-arm64/arm64-apple-macosx/release/QuotaBar"
BIN_X86=".build-x86_64/x86_64-apple-macosx/release/QuotaBar"
# SwiftPM layout can vary slightly by toolchain; find the binaries if needed.
if [[ ! -x "$BIN_ARM" ]]; then
  BIN_ARM="$(find .build-arm64 -type f -name QuotaBar -perm -111 | head -n 1)"
fi
if [[ ! -x "$BIN_X86" ]]; then
  BIN_X86="$(find .build-x86_64 -type f -name QuotaBar -perm -111 | head -n 1)"
fi
test -x "$BIN_ARM" && test -x "$BIN_X86"

mkdir -p TouchBack.app/Contents/MacOS TouchBack.app/Contents/Resources
lipo -create "$BIN_ARM" "$BIN_X86" -output TouchBack.app/Contents/MacOS/QuotaBar
chmod +x TouchBack.app/Contents/MacOS/QuotaBar

cat > TouchBack.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>QuotaBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.uselesssoso.quotabar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleDisplayName</key>
  <string>TouchBack</string>
  <key>CFBundleName</key>
  <string>TouchBack</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.4</string>
  <key>CFBundleVersion</key>
  <string>5</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
</dict>
</plist>
PLIST

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --deep --options runtime --sign "$DEVELOPER_ID_APPLICATION" TouchBack.app
else
  codesign --force --deep --sign - TouchBack.app
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent TouchBack.app TouchBack-universal.zip
file TouchBack.app/Contents/MacOS/QuotaBar
lipo -info TouchBack.app/Contents/MacOS/QuotaBar
