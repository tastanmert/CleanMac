#!/bin/zsh
# Builds CleanMac.app into /Applications (or the folder given as $1).
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-/Applications}"
APP="build/CleanMac.app"

# Universal binary: runs natively on Apple Silicon and Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/CleanMac"

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CleanMac"

# Icon
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CleanMac</string>
  <key>CFBundleDisplayName</key><string>CleanMac</string>
  <key>CFBundleIdentifier</key><string>dev.merttastan.cleanmac</string>
  <key>CFBundleExecutable</key><string>CleanMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.4</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>CleanMac uses Finder to empty the Trash when you confirm it.</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
</dict>
</plist>
PLIST

# Interface languages: Turkish texts are the keys, English lives in en.lproj (macOS picks by the user's language).
cp -R Localization/*.lproj "$APP/Contents/Resources/"

# Sign with the local Apple Development certificate when there is one: macOS keys folder and
# Automation permissions to a stable signature, so they survive rebuilds. Ad-hoc otherwise.
IDENTITY="${CLEANMAC_SIGN:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
[ "$IDENTITY" = "-" ] && IDENTITY=""
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "İmza: ${IDENTITY:-ad-hoc}"
mkdir -p "$DEST"
rm -rf "$DEST/CleanMac.app"
cp -R "$APP" "$DEST/"
echo "Hazır: $DEST/CleanMac.app"
