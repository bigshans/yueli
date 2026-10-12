#!/usr/bin/env python3
"""从同一份矢量标记生成应用图标资源。"""
import pathlib

OUT = pathlib.Path(__file__).parent

DEFS = """
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#5B8CFF"/>
      <stop offset="1" stop-color="#2A47C9"/>
    </linearGradient>
    <linearGradient id="pageL" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#F1F5FF"/>
    </linearGradient>
    <linearGradient id="pageR" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#E6EDFF"/>
      <stop offset="1" stop-color="#CDD9FF"/>
    </linearGradient>
    <linearGradient id="ribbon" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFCF6B"/>
      <stop offset="1" stop-color="#FF9A1F"/>
    </linearGradient>
    <filter id="shadow" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="12" stdDeviation="16" flood-color="#0A1A52" flood-opacity="0.28"/>
    </filter>
    <filter id="shadow2" x="-40%" y="-40%" width="180%" height="180%">
      <feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#8A4A00" flood-opacity="0.35"/>
    </filter>
  </defs>
"""

# 打开的书 + 书签（画布 1024，标记居中）。
MARK = """
  <g filter="url(#shadow)">
    <path d="M512 330 C 436 288, 316 280, 226 322 L 226 686 C 316 644, 436 652, 512 694 Z" fill="url(#pageL)"/>
    <path d="M512 330 C 588 288, 708 280, 798 322 L 798 686 C 708 644, 588 652, 512 694 Z" fill="url(#pageR)"/>
    <rect x="500" y="326" width="24" height="372" rx="12" fill="#B7C6F4"/>
    <g stroke="#C6D2F7" stroke-width="12" stroke-linecap="round">
      <line x1="292" y1="430" x2="446" y2="414"/>
      <line x1="292" y1="500" x2="446" y2="488"/>
      <line x1="292" y1="570" x2="410" y2="560"/>
    </g>
    <g stroke="#C6D2F7" stroke-width="12" stroke-linecap="round">
      <line x1="588" y1="414" x2="742" y2="430"/>
      <line x1="588" y1="488" x2="700" y2="498"/>
      <line x1="588" y1="560" x2="700" y2="568"/>
    </g>
    <g filter="url(#shadow2)">
      <path d="M652 300 L 776 300 L 776 590 L 714 536 L 652 590 Z" fill="url(#ribbon)"/>
    </g>
  </g>
"""

HEAD = '<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">'


def write(name: str, body: str) -> None:
    (OUT / name).write_text(f"{HEAD}\n{DEFS}\n{body}\n</svg>\n")
    print("wrote", name)


# 1) 完整方形图标（OS 会自行圆角）
write("app_icon.svg", f'  <rect x="0" y="0" width="1024" height="1024" fill="url(#bg)"/>\n{MARK}')

# 2) 自适应图标背景（满幅渐变，系统裁剪）
write("app_icon_background.svg", '  <rect x="0" y="0" width="1024" height="1024" fill="url(#bg)"/>')

# 3) 自适应图标前景（透明底，标记缩到安全区内）
write(
    "app_icon_foreground.svg",
    '  <g transform="translate(512 512) scale(0.86) translate(-512 -512)">\n'
    f"{MARK}\n  </g>",
)
