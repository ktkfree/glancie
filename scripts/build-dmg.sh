#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

echo "🚀 Building Glancie in Release mode..."
swift build -c release

APP_NAME="Glancie"
BUILD_DIR="${ROOT_DIR}/.build/release"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="${ROOT_DIR}/${APP_NAME}.dmg"
DMG_STAGING="${BUILD_DIR}/dmg_staging"

echo "📦 Packaging ${APP_NAME}.app..."
rm -rf "${APP_DIR}" "${DMG_STAGING}" "${DMG_NAME}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# 앱 아이콘 (Finder/Applications 에 노출되는 번들 아이콘)
cp "${ROOT_DIR}/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

cat << 'PLIST' > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Glancie</string>
    <key>CFBundleIdentifier</key>
    <string>com.glancie.app</string>
    <key>CFBundleName</key>
    <string>Glancie</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "💿 Creating DMG archive..."
mkdir -p "${DMG_STAGING}"
cp -R "${APP_DIR}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_NAME}"

echo "✨ DMG created successfully at ${DMG_NAME}"
