#!/bin/bash
# 只生成本地更新包，不提交、打标签、推送或发布。
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh release
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Hotkey.app/Contents/Info.plist)"
architecture="$(uname -m)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "版本必须为 major.minor.patch。" >&2
  exit 1
fi
mkdir -p dist/packages
app_archive="Hotkey-$version-macos-$architecture.zip"
plugin_archive="NativeMessage-$version-macos-$architecture.zip"
ditto -c -k --keepParent dist/Hotkey.app "dist/packages/$app_archive"
ditto -c -k --keepParent dist/NativeMessage.hotkeyplugin "dist/packages/$plugin_archive"
python3 - "$app_archive" "$plugin_archive" <<'PY'
import hashlib, json, plistlib, sys
from pathlib import Path
output = Path('dist/packages')
info = plistlib.loads(Path('dist/Hotkey.app/Contents/Info.plist').read_bytes())
files = []
for name in sys.argv[1:]:
    path = output / name
    files.append(dict(name=name, size=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
manifest = dict(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
                bundleIdentifier=info['CFBundleIdentifier'], signing='adhoc', notarized=False, files=files)
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
(output / 'SHA256SUMS').write_text(''.join(f"{file['sha256']}  {file['name']}\n" for file in files))
PY
echo "已生成本地更新包与校验清单：dist/packages/"
