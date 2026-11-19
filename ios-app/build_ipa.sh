#!/usr/bin/env bash
# 打包成可直接丢进 TrollStore 安装的 iPA（无签名 + 自带 entitlements）。
#
# 用法:  ./build_ipa.sh            → build/Xunidingwei.ipa
#
# 需要: macOS + Xcode、xcodegen、ldid（brew install ldid xcodegen）
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Xunidingwei"
BUILD_DIR="build"
DERIVED="$BUILD_DIR/DerivedData"
OUT_IPA="$BUILD_DIR/$APP_NAME.ipa"

for tool in xcodebuild xcodegen ldid zip; do
  command -v "$tool" >/dev/null || { echo "缺少工具: $tool"; exit 1; }
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 同步地点表"
python3 ../tools/gen_locations.py

echo "==> 生成 Xcode 工程"
xcodegen generate --quiet

echo "==> 编译（不签名）"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
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
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$STAGE"
rm -rf "$STAGE/_CodeSignature" "$STAGE/embedded.mobileprovision"

echo "==> 注入 entitlements（巨魔安装时会保留这份签名）"
ldid -S"$APP_NAME/Xunidingwei.entitlements" "$STAGE/$APP_NAME"

echo "==> 打包 iPA"
(cd "$BUILD_DIR" && zip -qry "$APP_NAME.ipa" Payload)
rm -rf "$BUILD_DIR/Payload"

echo
echo "完成: $(pwd)/$OUT_IPA"
echo "传到手机后用 TrollStore 打开这个文件即可安装。"
