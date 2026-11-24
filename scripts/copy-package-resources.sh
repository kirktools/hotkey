#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bin_path="$1"
resources="$2"
mode="$3"
privacy_bundle="$bin_path/CocoaLumberjack_CocoaLumberjack.bundle"
test -f "$privacy_bundle/PrivacyInfo.xcprivacy"
mkdir -p "$resources"
ditto "$privacy_bundle" "$resources/CocoaLumberjack_CocoaLumberjack.bundle"
# SwiftPM 的依赖检出可能为只读，产物中的副本需要支持重复构建。
install -m 0644 .build/checkouts/pkg-logging/LICENSE "$resources/LICENSE-KirkLogging"
install -m 0644 .build/checkouts/CocoaLumberjack/LICENSE "$resources/LICENSE-CocoaLumberjack"
if [[ "$mode" == translation ]]; then
  install -m 0644 .build/checkouts/pkg-translation/LICENSE "$resources/LICENSE-KirkTranslation"
fi
