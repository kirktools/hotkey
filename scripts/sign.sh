#!/bin/bash
# 免费的本地签名；不创建证书、不访问私钥、不修改钥匙串。
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 || ! -d "$1/Contents" ]]; then
  echo "用法：scripts/sign.sh <应用.app>" >&2
  exit 2
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")"
identity="-"
if [[ "${2:-release}" == debug ]]; then
  identity="${DEV_SIGNING_IDENTITY:-}"
  identity_file="$(dirname "$0")/../.local/dev-signing-identity"
  if [[ -z "$identity" && -f "$identity_file" ]]; then identity="$(cat "$identity_file")"; fi
  if [[ -z "$identity" ]]; then
    identity="-"
    echo "开发签名：ad-hoc（未配置固定证书；不能保证跨构建保留隐私授权）。"
  fi
else
  identity="${RELEASE_SIGNING_IDENTITY:--}"
fi
options=()
if [[ "${2:-release}" == release && "$identity" != "-" ]]; then
  options+=(--options runtime)
  if [[ -n "${RELEASE_SIGNING_KEYCHAIN:-}" ]]; then
    options+=(--keychain "$RELEASE_SIGNING_KEYCHAIN")
  fi
fi
codesign --force --sign "$identity" --timestamp=none --identifier "$bundle_id" ${options[@]+"${options[@]}"} "$1"
codesign --verify --strict "$1"
if [[ "${2:-release}" == release && "$identity" != "-" ]]; then
  requirement="$(codesign --display --requirements - "$1" 2>/dev/null)"
  if [[ "$requirement" != *"certificate "* || "$requirement" == *"cdhash "* ]]; then
    echo "签名未生成稳定的证书身份要求。" >&2
    exit 1
  fi
fi
