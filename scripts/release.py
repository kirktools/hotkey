#!/usr/bin/env python3
"""本地发布入口；dry-run 不写文件，不运行任何 Git 写操作。"""
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()

def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)

def main():
    os.chdir(ROOT)
    dry = sys.argv[1:] == ['--dry-run']
    if sys.argv[1:] and not dry:
        raise ValueError('仅支持 --dry-run')
    path = ROOT / 'Resources/Info.plist'
    original = path.read_text()
    info = plistlib.loads(original.encode())
    current = info['CFBundleShortVersionString']
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', current):
        raise ValueError('当前版本必须为 major.minor.patch')
    parts = list(map(int, current.split('.')))
    bump = os.environ.get('BUMP', 'patch')
    if bump not in ('major', 'minor', 'patch'):
        raise ValueError('BUMP 仅支持 patch、minor、major')
    index = ('major', 'minor', 'patch').index(bump)
    parts[index] += 1
    for i in range(index + 1, 3):
        parts[i] = 0
    version = '.'.join(map(str, parts))
    build = str(int(info['CFBundleVersion']) + 1)
    tag = 'v' + version
    print(f'版本预览：{current} → {version}；构建号 {info["CFBundleVersion"]} → {build}；标签 {tag}', flush=True)
    if git('branch', '--show-current') != 'master':
        raise ValueError('发布只允许在 master 分支运行')
    if git('status', '--porcelain'):
        raise ValueError('工作区或暂存区不干净；请先处理已有改动。未修改版本。')
    git('remote', 'get-url', 'origin')
    if git('tag', '--list', tag):
        raise ValueError(f'本地标签 {tag} 已存在')
    if dry:
        print('本地发布条件通过。正式发布还会检查远端同步和标签，运行 make check、make test，再提交版本并原子推送 master 与标签。')
        print('dry-run 未联网，远端条件尚未验证；未修改文件、提交或推送。')
        return
    run('git', 'fetch', '--tags', 'origin', 'master')
    if git('rev-parse', 'HEAD') != git('rev-parse', 'refs/remotes/origin/master'):
        raise ValueError('master 与 origin/master 不一致，请先完成同步')
    if git('ls-remote', '--tags', 'origin', 'refs/tags/' + tag):
        raise ValueError(f'远端标签 {tag} 已存在')
    run('make', 'check')
    run('make', 'test')
    if git('status', '--porcelain'):
        raise ValueError('检查期间工作区发生变化，已停止发布')
    for key, value in [('CFBundleShortVersionString', version), ('CFBundleVersion', build)]:
        pattern = r'(<key>' + key + r'</key>\s*<string>)[^<]*(</string>)'
        original, count = re.subn(pattern, lambda m: m[1] + value + m[2], original)
        if count != 1:
            raise ValueError(f'无法唯一定位 {key}')
    path.write_text(original)
    print('开始版本提交；后续失败将保留本地版本变更、提交或标签，不自动重写历史。', flush=True)
    run('git', 'add', '--', 'Resources/Info.plist')
    run('git', 'commit', '-m', f'发布 {tag}')
    run('git', 'tag', '-a', tag, '-m', f'Hotkey {version}')
    run('git', 'push', '--atomic', 'origin', 'HEAD:refs/heads/master', 'refs/tags/' + tag)
    print(f'已推送 {tag}，由标签工作流构建和发布，无需再次确认。')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'发布停止：{error}', file=sys.stderr)
        print('未执行自动回滚。若已生成本地提交或标签，请检查 git status / git log / git tag；修复推送问题后可原子推送已有提交和标签。', file=sys.stderr)
        sys.exit(1)
