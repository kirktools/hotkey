#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# 只更新本工作区的开发版，保留日常使用的正式版进程。
python3 - <<'PY'
import os, signal, subprocess, time
from pathlib import Path
executable = str(Path('dist/dev/Hotkey Dev.app/Contents/MacOS/Hotkey').resolve())
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
open "dist/dev/Hotkey Dev.app" --args --settings
