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
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.hotkey.example-plugin' "$plugin/ExamplePlugin.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable ExamplePlugin' "$plugin/ExamplePlugin.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName ExamplePlugin' "$plugin/ExamplePlugin.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 原生窗口示例' "$plugin/ExamplePlugin.app/Contents/Info.plist"
cp Examples/manifest.json "$plugin/manifest.json"
./scripts/sign.sh "$plugin/ExamplePlugin.app"
./scripts/sign.sh "$app"
echo "已构建：$app"
echo "示例插件：$plugin"
