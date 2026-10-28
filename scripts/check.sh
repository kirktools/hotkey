#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for script in scripts/*.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist
python3 - <<'PY'
import ast, json
from pathlib import Path
for path in Path('scripts').glob('*.py'):
    ast.parse(path.read_text(), filename=str(path))
json.loads(Path('Examples/manifest.json').read_text())
PY
# 自动检查无需分页阅读，避免终端运行时停在 less 等交互界面。
git --no-pager diff --check
# Swift 编译器承担类型检查；不安装、不启动应用。
./scripts/swift.sh build
