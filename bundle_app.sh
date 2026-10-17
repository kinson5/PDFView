#!/usr/bin/env bash
set -e

TARGET_BIN="DuokanPDFViewer"
APP_NAME="PDFview"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "🔨 Building Release target..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${TARGET_BIN}"

echo "📦 Creating macOS App Bundle: ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

cp "${BIN_PATH}" "${MACOS}/${APP_NAME}"
chmod +x "${MACOS}/${APP_NAME}"

# Copy application icon
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${RESOURCES}/AppIcon.icns"
fi

cat << 'EOF' > "${CONTENTS}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PDFview</string>
    <key>CFBundleIdentifier</key>
    <string>com.pdfview.reader</string>
    <key>CFBundleName</key>
    <string>PDFview</string>
    <key>CFBundleDisplayName</key>
    <string>PDFview</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

touch "${APP_BUNDLE}"

# Keep DuokanPDFViewer.app synced in case of existing Dock links
rm -rf "DuokanPDFViewer.app"
cp -R "${APP_BUNDLE}" "DuokanPDFViewer.app"

echo "📱 Creating dedicated iOS Mobile Bundle: PDFview-iOS.app..."
IOS_APP_NAME="PDFview-iOS"
IOS_APP_BUNDLE="${IOS_APP_NAME}.app"
rm -rf "${IOS_APP_BUNDLE}"
cp -R "${APP_BUNDLE}" "${IOS_APP_BUNDLE}"

# In PDFview-iOS, put a wrapper launcher script
mv "${IOS_APP_BUNDLE}/Contents/MacOS/PDFview" "${IOS_APP_BUNDLE}/Contents/MacOS/PDFview-bin"
cat << 'LAUNCHER' > "${IOS_APP_BUNDLE}/Contents/MacOS/PDFview"
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
export PDFVIEW_MOBILE=1
exec "${DIR}/PDFview-bin" --ios "$@"
LAUNCHER
chmod +x "${IOS_APP_BUNDLE}/Contents/MacOS/PDFview"

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName PDFview (iOS手机版)" "${IOS_APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleName PDFview-iOS" "${IOS_APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true
touch "${IOS_APP_BUNDLE}"

echo "🔗 Creating Desktop shortcuts..."
rm -f "$HOME/Desktop/多看PDF重排阅读器"
rm -f "$HOME/Desktop/PDFview"
rm -f "$HOME/Desktop/PDFview (iOS手机版)"

osascript -e '
set appPath to POSIX file "'$(pwd)'/'${APP_BUNDLE}'"
set deskPath to POSIX file "'$HOME'/Desktop"
tell application "Finder"
    make new alias file at deskPath to appPath with properties {name:"PDFview"}
end tell
' || true

osascript -e '
set appPath to POSIX file "'$(pwd)'/'${IOS_APP_BUNDLE}'"
set deskPath to POSIX file "'$HOME'/Desktop"
tell application "Finder"
    make new alias file at deskPath to appPath with properties {name:"PDFview (iOS手机版)"}
end tell
' || true

echo "✅ App bundle created successfully at $(pwd)/${APP_BUNDLE}"
echo "✅ iOS Mobile bundle created at $(pwd)/${IOS_APP_BUNDLE}"
echo "✅ Desktop shortcuts created: ~/Desktop/PDFview and ~/Desktop/PDFview (iOS手机版)"
