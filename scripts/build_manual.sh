#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="Glancie"
BUILD_DIR="${ROOT_DIR}/.build/release"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
ZIP_NAME="${ROOT_DIR}/${APP_NAME}.zip"

echo "🚀 [1/4] Building ${APP_NAME} in Release mode..."
swift build -c release

echo "📦 [2/4] Creating ${APP_NAME}.app bundle..."
rm -rf "${APP_DIR}" "${ZIP_NAME}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# 바이너리 복사
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# 앱 아이콘 (Finder/Applications 에 노출되는 번들 아이콘)
cp "${ROOT_DIR}/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

# Info.plist 작성 (LSUIElement: 백그라운드/메뉴바 상주 앱)
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

echo "🗜️  [3/4] Creating ZIP distribution package..."
ditto -c -k --keepParent "${APP_DIR}" "${ZIP_NAME}"

# Installing is opt-in. The step called itself "(Optional)" while replacing
# whatever sat at /Applications/Glancie.app every time, which is not a thing to
# do to someone who cloned the repo and ran the build script to look at it.
if [ -n "${GLANCIE_SKIP_INSTALL:-}" ]; then
    INSTALL="no"
elif [ ! -t 0 ]; then
    # No terminal to ask at (CI, a pipe): never install.
    INSTALL="no"
elif [ -n "${GLANCIE_INSTALL:-}" ]; then
    INSTALL="yes"
else
    if [ -d "/Applications/${APP_NAME}.app" ]; then
        echo "⚠️  [4/4] /Applications/${APP_NAME}.app 이 이미 있습니다. 덮어쓸까요?"
    else
        echo "📂 [4/4] /Applications 에 설치할까요?"
    fi
    printf "    [y/N] "
    read -r REPLY
    case "${REPLY}" in
        [yY]*) INSTALL="yes" ;;
        *)     INSTALL="no" ;;
    esac
fi

if [ "${INSTALL}" = "yes" ] && [ -d "/Applications" ]; then
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "${APP_DIR}" "/Applications/${APP_NAME}.app"

    # 같은 경로에 덮어쓰면 Finder 가 예전 아이콘을 계속 들고 있는다.
    # 번들 mtime 을 올리고 Launch Services 에 다시 등록해 캐시를 털어준다.
    touch "/Applications/${APP_NAME}.app"
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    [ -x "${LSREGISTER}" ] && "${LSREGISTER}" -f "/Applications/${APP_NAME}.app" || true

    echo "✅ /Applications/${APP_NAME}.app 설치 완료!"
else
    echo "⏭️  [4/4] 설치를 건너뜁니다. 설치하려면: GLANCIE_INSTALL=1 ./scripts/build_manual.sh"
fi

echo ""
echo "🎉 빌드 및 패키징이 성공적으로 완료되었습니다!"
echo "   - App 번들  : ${APP_DIR}"
echo "   - ZIP 배포본 : ${ZIP_NAME}"
if [ "${INSTALL}" = "yes" ]; then echo "   - 시스템 설치: /Applications/${APP_NAME}.app"; fi
