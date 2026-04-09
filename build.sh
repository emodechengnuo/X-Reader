#!/bin/bash
# X-Reader - 构建打包脚本
# 用法: ./build.sh [release|debug]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:-debug}"
APP_NAME="X-Reader"
BUNDLE_NAME="X-Reader"
APP_BUNDLE="$SCRIPT_DIR/build/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "🔨 Building $APP_NAME in $MODE mode..."

# 1. Swift 编译
if [ "$MODE" = "release" ]; then
    swift build -c release 2>&1 | tail -5
    BINARY=".build/release/$BUNDLE_NAME"
else
    swift build -c debug 2>&1 | tail -5
    BINARY=".build/debug/$BUNDLE_NAME"
fi

echo "✅ Build complete: $BINARY"

# 2. 创建/清理 App Bundle 结构
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# 3. 复制可执行文件
cp "$BINARY" "$MACOS_DIR/$BUNDLE_NAME"
chmod +x "$MACOS_DIR/$BUNDLE_NAME"

# 4. 复制 Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 5. 复制资源文件（如果有）
if [ -d "$SCRIPT_DIR/Resources" ]; then
    cp -R "$SCRIPT_DIR/Resources/"* "$RESOURCES_DIR/" 2>/dev/null || true
fi

# 6. 🛡️ Code signing
echo "🔐 Code signing..."

# 签名主程序
codesign --force --sign - "$MACOS_DIR/$BUNDLE_NAME" 2>/dev/null

# 签名整个 App Bundle
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null

# 7. 验证签名
if codesign -v "$APP_BUNDLE" 2>/dev/null; then
    echo "✅ Signature valid!"
else
    echo "❌ Signature verification failed!"
    exit 1
fi

echo ""
echo "🎉 Done! App at: $APP_BUNDLE"
echo "   To open: open \"$APP_BUNDLE\""
