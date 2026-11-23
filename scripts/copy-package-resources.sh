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
cp .build/checkouts/pkg-logging/LICENSE "$resources/LICENSE-KirkLogging"
cp .build/checkouts/CocoaLumberjack/LICENSE "$resources/LICENSE-CocoaLumberjack"
if [[ "$mode" == translation ]]; then
  cp .build/checkouts/pkg-translation/LICENSE "$resources/LICENSE-KirkTranslation"
fi
