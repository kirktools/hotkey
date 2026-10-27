#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer_dir="$(xcode-select -p)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
testing_macros="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
bin_path="$(./scripts/swift.sh build --show-bin-path)"
export HOTKEY_FIXTURE_EXECUTABLE="$bin_path/ProtocolFixture"
if [[ -d "$testing_frameworks/Testing.framework" && -f "$testing_macros" ]]; then
  # 部分 Command Line Tools 预览版未自动提供 Testing 的搜索路径。
  ./scripts/swift.sh test --disable-xctest \
    -Xswiftc -F -Xswiftc "$testing_frameworks" \
    -Xswiftc -load-plugin-library -Xswiftc "$testing_macros" \
    -Xlinker "-F$testing_frameworks" \
    -Xlinker -rpath -Xlinker "$testing_frameworks"
else
  ./scripts/swift.sh test --disable-xctest
fi
