#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo "CONFIG 必须为 debug 或 release。" >&2; exit 2 ;; esac

./scripts/swift.sh build -c "$configuration" --product TranslationPlugin
bin_path="$(./scripts/swift.sh build -c "$configuration" --show-bin-path)"
output="dist"
bundle_id="dev.hotkey.translation-plugin"
if [[ "$configuration" == debug ]]; then
  output="dist/dev"
  bundle_id="dev.hotkey.translation-plugin.dev"
fi
mkdir -p "$output"
stage="$(mktemp -d "$output/.translation.XXXXXX")"
trap 'rm -r "$stage"' EXIT
plugin="$stage/Translation.hotkeyplugin"
contents="$plugin/TranslationPlugin.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$bin_path/TranslationPlugin" "$contents/MacOS/"
cp Plugins/Translation/manifest.json "$plugin/"
cp LICENSE "$plugin/"
cp LICENSE "$contents/Resources/"
cp Vendor/KirkTranslation/LICENSE "$plugin/LICENSE-KirkTranslation"
cp Vendor/KirkTranslation/LICENSE "$contents/Resources/LICENSE-KirkTranslation"
python3 - "$plugin" "$contents" "$bundle_id" <<'PY'
import json, plistlib, sys
from pathlib import Path

plugin, contents = map(Path, sys.argv[1:3])
manifest = json.loads((plugin / 'manifest.json').read_text())
info = {
    'CFBundleIdentifier': sys.argv[3],
    'CFBundleName': 'TranslationPlugin',
    'CFBundleDisplayName': manifest['name'],
    'CFBundleExecutable': 'TranslationPlugin',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': manifest['version'],
    'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '15.0',
    'LSUIElement': True,
}
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
PY
./scripts/sign.sh "$plugin/TranslationPlugin.app" "$configuration"
destination="$output/Translation.hotkeyplugin"
if [[ -e "$destination" ]]; then
  mv "$destination" "$stage/previous.hotkeyplugin"
fi
if ! mv "$plugin" "$destination"; then
  if [[ -e "$stage/previous.hotkeyplugin" ]]; then
    mv "$stage/previous.hotkeyplugin" "$destination" || trap - EXIT
  fi
  exit 1
fi
echo "已构建：$destination"
