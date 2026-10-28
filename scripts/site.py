#!/usr/bin/env python3
"""官网构建仅允许明确列出的公开文件，不遍历复制仓库。"""
import argparse
import html
from html.parser import HTMLParser
from pathlib import Path
import os
import plistlib
import re
import shutil
from urllib.parse import urlsplit, unquote

ROOT = Path(__file__).resolve().parent.parent
FILES = ('index.html', 'assets/style.css', 'assets/demo-poster.svg', 'assets/demo.webm')
OUT = ROOT / '.build/site'

class Document(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids = set(); self.links = []; self.video = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            if attrs['id'] in self.ids: raise ValueError('重复锚点')
            self.ids.add(attrs['id'])
        for name in ('href', 'src', 'poster'):
            if name in attrs: self.links.append((name, attrs[name]))
        if tag == 'video': self.video.append(attrs)
        if tag in ('script', 'iframe'): raise ValueError('官网不允许脚本或 iframe')

def build():
    version = plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
    tag = os.environ.get('SITE_RELEASE_TAG', '')
    if tag and (not re.fullmatch(r'v\d+\.\d+\.\d+', tag) or tag != 'v'+version):
        raise ValueError('发布标签必须与源码版本一致')
    if (ROOT/".build").is_symlink() or OUT.is_symlink(): raise ValueError("拒绝通过符号链接写入官网目录")
    OUT.mkdir(parents=True, exist_ok=True)
    # 仅清理本工具的固定构建目录。
    for path in OUT.iterdir():
        if path.is_symlink() or path.is_file(): path.unlink()
        else: shutil.rmtree(path)
    for name in FILES:
        source = ROOT/'site'/name
        if source.is_symlink() or not source.resolve().is_relative_to((ROOT/"site").resolve()) or not source.is_file(): raise ValueError('缺少公开文件或文件为符号链接：'+name)
        destination = OUT/name; destination.parent.mkdir(parents=True, exist_ok=True)
        if name.endswith('.html'):
            destination.write_text(source.read_text().replace('@@VERSION@@', html.escape(tag or version+'（本地预览）')).replace('@@TAG@@', tag or 'master'))
        else: shutil.copyfile(source, destination)
    (OUT/'.nojekyll').write_text('')
    (OUT/'robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: https://kirktools.github.io/hotkey/sitemap.xml\n')
    (OUT/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://kirktools.github.io/hotkey/</loc></url></urlset>\n')
    print('官网构建完成：.build/site/')

def check():
    build()
    actual = {str(p.relative_to(OUT)) for p in OUT.rglob('*') if p.is_file()}
    if actual != set(FILES)|{'.nojekyll', 'robots.txt', 'sitemap.xml'}: raise ValueError('官网发布文件范围不匹配')
    doc = Document(); text = (OUT/'index.html').read_text(); doc.feed(text)
    if '@@' in text: raise ValueError('未替换的构建变量')
    for kind, link in doc.links:
        value = urlsplit(link)
        if value.scheme:
            if value.scheme != 'https': raise ValueError('外部链接必须使用 HTTPS')
            if kind != 'href': raise ValueError('素材必须由本站提供')
            continue
        if value.netloc or value.path.startswith('/'): raise ValueError('资源需要使用项目站点兼容的相对路径')
        if value.path:
            path = (OUT/unquote(value.path)).resolve()
            if not path.is_relative_to(OUT.resolve()) or not path.is_file(): raise ValueError('资源不存在或路径逃逸：'+link)
        if value.fragment and not value.path and value.fragment not in doc.ids: raise ValueError('锚点不存在：'+link)
    css = (OUT/'assets/style.css').read_text()
    if '@import' in css or re.search(r'url\s*\(', css):
        raise ValueError('当前官网 CSS 不允许额外资源或外部依赖')
    if 'lang="zh-CN"' not in text or 'name="viewport"' not in text or 'name="description"' not in text:
        raise ValueError('缺少语言、移动端或简介元信息')
    expected_download = 'https://github.com/kirktools/hotkey/releases/latest/download/Hotkey-macos-arm64.zip'
    if ('href', expected_download) not in doc.links: raise ValueError('主下载入口未指向固定正式版文件')
    if len(doc.video) != 1 or 'controls' not in doc.video[0] or 'autoplay' in doc.video[0] or 'poster' not in doc.video[0]:
        raise ValueError('演示视频需要封面、原生控制且禁止自动播放')
    print('官网检查通过：资源、锚点、视频控制、封面和发布白名单。')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('command', choices=['build','check','preview']); args = parser.parse_args()
    if args.command == 'build': build()
    else:
        check()
        if args.command == 'preview':
            import http.server
            port = int(os.environ.get('PORT', '4173'))
            os.chdir(OUT)
            print(f'预览：http://127.0.0.1:{port}', flush=True)
            http.server.ThreadingHTTPServer(('127.0.0.1', port), http.server.SimpleHTTPRequestHandler).serve_forever()
