#!/usr/bin/env python3
"""本地发布入口；dry-run 不写文件，不运行任何 Git 写操作。"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
PLUGINS = {'translation': ('划词翻译', 'Plugins/Translation/manifest.json')}

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()

def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)

def select_plugin():
    if not sys.stdin.isatty():
        raise ValueError('非交互环境请指定 PLUGIN，例如 PLUGIN=translation')
    plugins = list(PLUGINS)
    print('选择要发布的插件：')
    for number, plugin in enumerate(plugins, start=1):
        print(f'  {number}. {PLUGINS[plugin][0]}')
    print('  0. 取消')
    choices = {str(number): plugin for number, plugin in enumerate(plugins, start=1)}
    while True:
        try:
            choice = input('请输入编号 [1]：').strip() or '1'
        except (EOFError, KeyboardInterrupt):
            print()
            return None
        if choice == '0':
            return None
        if choice in choices:
            return choices[choice]
        print('请输入列表中的编号。')

def main():
    os.chdir(ROOT)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--plugin', nargs='?', const='', metavar='NAME')
    args = parser.parse_args()
    plugin = args.plugin
    if plugin == '':
        plugin = select_plugin()
        if plugin is None:
            print('已取消，未修改版本。')
            return
    if plugin is not None and plugin not in PLUGINS:
        raise ValueError(f'未知插件：{plugin}。可选插件：{", ".join(PLUGINS)}')
    path = ROOT / (PLUGINS[plugin][1] if plugin else 'Resources/Info.plist')
    original = path.read_text()
    info = json.loads(original) if plugin else plistlib.loads(original.encode())
    current = info['version'] if plugin else info['CFBundleShortVersionString']
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
    build = None if plugin else str(int(info['CFBundleVersion']) + 1)
    tag = f'plugin-{plugin}-v{version}' if plugin else 'v' + version
    build_preview = f'；构建号 {info["CFBundleVersion"]} → {build}' if build is not None else ''
    print(f'版本预览：{current} → {version}{build_preview}；标签 {tag}', flush=True)
    if git('branch', '--show-current') != 'master':
        raise ValueError('发布只允许在 master 分支运行')
    if git('status', '--porcelain'):
        raise ValueError('工作区或暂存区不干净；请先处理已有改动。未修改版本。')
    git('remote', 'get-url', 'origin')
    if git('tag', '--list', tag):
        raise ValueError(f'本地标签 {tag} 已存在')
    if args.dry_run:
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
    if plugin:
        original, count = re.subn(r'("version"\s*:\s*")[^"]*(")', lambda m: m[1] + version + m[2], original)
        if count != 1:
            raise ValueError('无法唯一定位插件版本')
    else:
        for key, value in [('CFBundleShortVersionString', version), ('CFBundleVersion', build)]:
            pattern = r'(<key>' + key + r'</key>\s*<string>)[^<]*(</string>)'
            original, count = re.subn(pattern, lambda m: m[1] + value + m[2], original)
            if count != 1:
                raise ValueError(f'无法唯一定位 {key}')
    path.write_text(original)
    print('开始版本提交；后续失败将保留本地版本变更、提交或标签，不自动重写历史。', flush=True)
    run('git', 'add', '--', str(path.relative_to(ROOT)))
    run('git', 'commit', '-m', f'发布 {tag}')
    run('git', 'tag', '-a', tag, '-m', f'Hotkey {tag if plugin else version}')
    run('git', 'push', '--atomic', 'origin', 'HEAD:refs/heads/master', 'refs/tags/' + tag)
    print(f'已推送 {tag}，由标签工作流构建和发布，无需再次确认。')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'发布停止：{error}', file=sys.stderr)
        print('未执行自动回滚。若已生成本地提交或标签，请检查 git status / git log / git tag；修复推送问题后可原子推送已有提交和标签。', file=sys.stderr)
        sys.exit(1)
