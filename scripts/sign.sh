#!/bin/bash
# 免费的本地签名；不创建证书、不访问私钥、不修改钥匙串。
set -euo pipefail
if [[ $# -ne 1 || ! -d "$1/Contents" ]]; then
  echo "用法：scripts/sign.sh <应用.app>" >&2
  exit 2
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")"
codesign --force --sign - --timestamp=none --identifier "$bundle_id" "$1"
codesign --verify --strict "$1"
