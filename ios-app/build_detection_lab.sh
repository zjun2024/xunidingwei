#!/usr/bin/env bash
# 打包「定位检测靶场」iPA（无签名 + 自带 entitlements），供 TrollStore 安装。
#
# 用法:  ./build_detection_lab.sh   → build/DetectionLab.ipa
#
# 需要: macOS + Xcode、xcodegen、ldid（brew install ldid xcodegen）
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DetectionLab"
BUILD_DIR="build"
DERIVED="$BUILD_DIR/DerivedData"
OUT_IPA="$BUILD_DIR/$APP_NAME.ipa"

for tool in xcodebuild xcodegen ldid zip; do
  command -v "$tool" >/dev/null || { echo "缺少工具: $tool"; exit 1; }
done

mkdir -p "$BUILD_DIR"

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 编译（不签名）"
xcodebuild \
  -project "Xunidingwei.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=iOS' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$DERIVED/Build/Products/Release-iphoneos/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "没有找到编译产物: $APP_PATH"; exit 1; }

STAGE="$BUILD_DIR/Payload/$APP_NAME.app"
rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$STAGE"
rm -rf "$STAGE/_CodeSignature" "$STAGE/embedded.mobileprovision"

echo "==> 注入 entitlements"
ldid -S"$APP_NAME/DetectionLab.entitlements" "$STAGE/$APP_NAME"

echo "==> 打包 iPA"
rm -f "$OUT_IPA"
(cd "$BUILD_DIR" && zip -qry "$APP_NAME.ipa" Payload)
rm -rf "$BUILD_DIR/Payload"

echo
echo "完成: $(pwd)/$OUT_IPA"
echo "传到手机后用 TrollStore 打开即可安装。"
