#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

SIM_APP="/Applications/Xcode.app/Contents/Applications/DeviceHub.app"
APP_BUNDLE="${DIR}/build/Release-iphonesimulator/PDFview.app"

echo "🔨 正在编译 iOS 模拟器 Release 目标..."
xcodebuild -project PDFview.xcodeproj -scheme PDFview-iOS -configuration Release -destination "generic/platform=iOS Simulator" -derivedDataPath ./build CONFIGURATION_BUILD_DIR=./build/Release-iphonesimulator CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO > /dev/null 2>&1 || {
    echo "⚠️ 首次检测到工程变更，正在重新生成 Xcode 工程并编译..."
    xcodegen generate
    xcodebuild -project PDFview.xcodeproj -scheme PDFview-iOS -configuration Release -destination "generic/platform=iOS Simulator" -derivedDataPath ./build CONFIGURATION_BUILD_DIR=./build/Release-iphonesimulator CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
}

# Boot iPhone 17 simulator if no simulator is currently booted
if ! xcrun simctl list devices booted | grep -q "(Booted)"; then
    echo "📱 正在启动 iPhone 17 模拟器..."
    xcrun simctl boot "iPhone 17" || true
fi

if [ -d "$SIM_APP" ]; then
    open "$SIM_APP"
fi

echo "📦 正在安装并启动 PDFview iOS 版..."
xcrun simctl install booted "$APP_BUNDLE"
xcrun simctl terminate booted com.pdfview.ios 2>/dev/null || true
xcrun simctl launch booted com.pdfview.ios

echo "✅ PDFview iOS 版已在 iPhone 模拟器 (DeviceHub) 中成功运行！"
