#!/bin/bash
# 只生成本地安装包与更新包，不提交、推送或发布。
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh release
./scripts/build-translation-plugin.sh release --already-built

app="dist/release.noindex/Hotkey.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
translation_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Translation.hotkeyplugin/TranslationPlugin.app/Contents/Info.plist)"
architecture="$(uname -m)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$translation_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "应用和翻译插件版本必须为 major.minor.patch。" >&2
  exit 1
fi

stage="$(mktemp -d "$PWD/dist/.packages.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
payload="$stage/dmg-content"
mkdir "$payload" "$stage/artifacts"

app_zip="Hotkey-$version-macos-$architecture.zip"
app_dmg="Hotkey-$version-macos-$architecture.dmg"
translation_zip="Plugin-Translation-$translation_version-macos-$architecture.zip"
output="$stage/artifacts"

# DMG 只包含已签名的应用副本和拖放安装入口。
/usr/bin/ditto "$app" "$payload/Hotkey.app"
ln -s /Applications "$payload/Applications"
/usr/bin/hdiutil create -format UDZO -fs HFS+ -volname Hotkey -srcfolder "$payload" "$output/$app_dmg"
/usr/bin/hdiutil verify "$output/$app_dmg"
/usr/bin/ditto -c -k --keepParent "$app" "$output/$app_zip"
/usr/bin/ditto -c -k --keepParent dist/Translation.hotkeyplugin "$output/$translation_zip"

python3 - "$output" "$app" "$architecture" "$app_zip" "$app_dmg" "$translation_zip" <<'PY'
import hashlib, json, os, plistlib, shutil, sys
from pathlib import Path

stage = Path(sys.argv[1])
app, arch, app_zip, app_dmg, translation_zip = sys.argv[2:]
aliases = {
    app_zip: f'Hotkey-macos-{arch}.zip',
    app_dmg: f'Hotkey-macos-{arch}.dmg',
    translation_zip: f'Plugin-Translation-macos-{arch}.zip',
}
for versioned, fixed in aliases.items():
    shutil.copyfile(stage / versioned, stage / fixed)

info = plistlib.loads((Path(app) / 'Contents/Info.plist').read_bytes())
files = []
for name in sorted([*aliases, *aliases.values()]):
    path = stage / name
    files.append(dict(name=name, size=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
manifest = dict(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
                bundleIdentifier=info['CFBundleIdentifier'], signing='adhoc', notarized=False, files=files)
(stage / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
(stage / 'SHA256SUMS').write_text(''.join(f"{file['sha256']}  {file['name']}\n" for file in files))

# 本地可能留有旧版本产物；本次清单只登记当前构建生成的文件。
output = Path('dist/packages')
output.mkdir(exist_ok=True)
for name in [*sorted(aliases), *sorted(aliases.values()), 'SHA256SUMS', 'manifest.json']:
    os.replace(stage / name, output / name)
PY
echo "已生成安装 DMG、更新 ZIP、独立插件与校验清单：dist/packages/"
