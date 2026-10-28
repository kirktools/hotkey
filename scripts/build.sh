#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo "用法：scripts/build.sh [debug|release]" >&2; exit 2 ;; esac
./scripts/swift.sh build -c "$configuration"
bin_path="$(./scripts/swift.sh build -c "$configuration" --show-bin-path)"
if [[ "$configuration" == debug ]]; then
  app="dist/dev/Hotkey Dev.app"
else
  app="dist/Hotkey.app"
fi
plugin="dist/NativeMessage.hotkeyplugin"
mkdir -p .build/tools "$app/Contents/Resources"
if [[ ! -x .build/tools/generate-icon || scripts/generate-icon.swift -nt .build/tools/generate-icon ]]; then
  xcrun swiftc scripts/generate-icon.swift -module-cache-path "$PWD/.build/module-cache" -o .build/tools/generate-icon
fi
icon_mode="release"
if [[ "$configuration" == debug ]]; then icon_mode="dev"; fi
iconset=".build/tools/$icon_mode.iconset"
.build/tools/generate-icon "$iconset" "$icon_mode" "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/MacOS" "$plugin/ExamplePlugin.app/Contents/MacOS"
cp "$bin_path/Hotkey" "$app/Contents/MacOS/Hotkey"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ "$configuration" == debug ]]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.hotkey.app.dev' "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName Hotkey Dev' "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Hotkey Dev' "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :HotkeyDataDirectoryName Hotkey-dev' "$app/Contents/Info.plist"
fi
cp "$bin_path/ExamplePlugin" "$plugin/ExamplePlugin.app/Contents/MacOS/ExamplePlugin"
cp Resources/Info.plist "$plugin/ExamplePlugin.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFile' "$plugin/ExamplePlugin.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.hotkey.example-plugin' "$plugin/ExamplePlugin.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable ExamplePlugin' "$plugin/ExamplePlugin.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName ExamplePlugin' "$plugin/ExamplePlugin.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 原生窗口示例' "$plugin/ExamplePlugin.app/Contents/Info.plist"
if [[ "$configuration" == debug ]]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.hotkey.example-plugin.dev' "$plugin/ExamplePlugin.app/Contents/Info.plist"
fi
cp Examples/manifest.json "$plugin/manifest.json"
# 许可文件在签名前加入，随应用与独立示例插件一起分发。
mkdir -p "$plugin/ExamplePlugin.app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp LICENSE "$plugin/LICENSE"
cp LICENSE "$plugin/ExamplePlugin.app/Contents/Resources/LICENSE"
./scripts/sign.sh "$plugin/ExamplePlugin.app" "$configuration"
./scripts/sign.sh "$app" "$configuration"
echo "已构建：$app"
echo "示例插件：$plugin"
