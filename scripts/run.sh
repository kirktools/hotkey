#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# 退出旧版本，让其先清理插件进程。只针对本项目使用的应用标识。
python3 - <<'PY'
import os, signal, subprocess, time
from pathlib import Path
executable = str(Path('dist/Hotkey.app/Contents/MacOS/Hotkey').resolve())
rows = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines()
for row in rows:
    fields = row.strip().split(None, 1)
    if len(fields) != 2 or fields[1] != executable:
        continue
    pid = int(fields[0])
    os.kill(pid, signal.SIGTERM)
    for _ in range(100):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.1)
    else:
        raise SystemExit('旧版本尚未退出，请在菜单栏退出后重试。')
PY
./scripts/build.sh
open dist/Hotkey.app --args --settings
