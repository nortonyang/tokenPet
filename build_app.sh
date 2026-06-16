#!/bin/bash

# Set strict exit on error
set -e

echo "=== 🚀 开始构建 TokenPet ==="

# 1. 使用 Swift Package Manager 进行 Release 编译
echo "📦 正在编译 Release 版本..."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$(pwd)/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox

# 获取编译出的二进制路径
BINARY_PATH=".build/release/TokenPet"
if [ ! -f "$BINARY_PATH" ]; then
    # Standalone tools might output to different directory structure depending on SPM version, check debug fallback
    BINARY_PATH=$(find .build -name "TokenPet" -type f | grep -v "TokenPet.build" | head -n 1)
fi

echo "✅ 编译成功: $BINARY_PATH"

# 2. 创建 .app 目录结构
APP_DIR="TokenPet.app"
echo "📂 创建 App 包目录结构: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

# 3. 复制二进制文件并赋予执行权限
echo "💾 复制二进制文件..."
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/TokenPet"
chmod +x "$APP_DIR/Contents/MacOS/TokenPet"

# 4. 生成 Info.plist
echo "📝 生成 Info.plist..."
cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>TokenPet</string>
    <key>CFBundleIdentifier</key>
    <string>com.tokenpet.TokenPet</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TokenPet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <!-- LSUIElement = 1 makes the app run as a background agent (no Dock icon, no main menu bar) -->
    <key>LSUIElement</key>
    <string>1</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "=== 🎉 TokenPet.app 构建完成！ ==="
echo "📂 你可以在当前文件夹下双击运行 TokenPet.app"
echo "👉 也可以在终端使用命令运行: open TokenPet.app"
