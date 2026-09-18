#!/bin/bash
# 아이콘 아트워크를 다시 뽑는다. 결과물(Resources/AppIcon.icns)은 저장소에 커밋돼 있으므로
# 평소 빌드는 이 스크립트를 타지 않는다. 디자인을 바꿨을 때만 돌리면 된다.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RES_DIR="${ROOT_DIR}/Resources"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

MASTER="${RES_DIR}/AppIcon-1024.png"
ICONSET="${WORK_DIR}/AppIcon.iconset"

mkdir -p "${RES_DIR}" "${ICONSET}"

echo "🎨 [1/3] 1024px 마스터 아트워크 생성..."
swift "${SCRIPT_DIR}/make_icon.swift" "${MASTER}"

echo "🖼  [2/3] iconset 리사이즈..."
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x" \
            "512:icon_512x512" "1024:icon_512x512@2x"; do
    size="${spec%%:*}"
    name="${spec##*:}"
    sips -z "${size}" "${size}" "${MASTER}" --out "${ICONSET}/${name}.png" > /dev/null
done

echo "📦 [3/3] .icns 패키징..."
iconutil -c icns "${ICONSET}" -o "${RES_DIR}/AppIcon.icns"

echo "✅ ${RES_DIR}/AppIcon.icns"
