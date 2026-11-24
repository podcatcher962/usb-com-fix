# -*- coding: utf-8 -*-
"""生成单文件 EXE 用的图标与启动画面"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = r'E:\_usbfix_bench\exe'
os.makedirs(OUT, exist_ok=True)

BLUE1 = (21, 101, 192, 255)
BLUE2 = (10, 58, 122, 255)
WHITE = (255, 255, 255, 255)


def grad(size, c1, c2):
    w, h = size
    im = Image.new('RGBA', (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=(
            int(c1[0] + (c2[0] - c1[0]) * t),
            int(c1[1] + (c2[1] - c1[1]) * t),
            int(c1[2] + (c2[2] - c1[2]) * t), 255))
    return im


def make_icon(size=256):
    # 圆角底（用 4 倍超采样再缩小，边缘更干净）
    S = size * 4
    base = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    g = grad((S, S), BLUE1, BLUE2)
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.20), fill=255)
    base.paste(g, (0, 0), mask)

    d = ImageDraw.Draw(base)
    cx = S // 2
    lw = int(S * 0.055)

    # USB 三叉：主杆
    d.line([(cx, int(S * 0.17)), (cx, int(S * 0.80))], fill=WHITE, width=lw)
    # 顶部圆
    r = int(S * 0.085)
    d.ellipse([cx - r, int(S * 0.17) - r, cx + r, int(S * 0.17) + r], fill=WHITE)
    # 右叉（方块）
    x1, y1 = cx, int(S * 0.50)
    x2, y2 = int(S * 0.74), int(S * 0.34)
    d.line([(x1, y1), (x2, y2)], fill=WHITE, width=lw)
    b = int(S * 0.075)
    d.rectangle([x2 - b, y2 - b, x2 + b, y2 + b], fill=WHITE)
    # 左叉（圆）
    x3, y3 = int(S * 0.26), int(S * 0.63)
    d.line([(x1, int(S * 0.60)), (x3, y3)], fill=WHITE, width=lw)
    r2 = int(S * 0.070)
    d.ellipse([x3 - r2, y3 - r2, x3 + r2, y3 + r2], fill=WHITE)
    # 底部三角
    tw = int(S * 0.085)
    d.polygon([(cx - tw, int(S * 0.80)), (cx + tw, int(S * 0.80)), (cx, int(S * 0.94))], fill=WHITE)

    return base.resize((size, size), Image.LANCZOS)


ic = make_icon(256)
sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)]
ic.save(os.path.join(OUT, 'usbfix.ico'), format='ICO', sizes=sizes)
print('ico  ->', os.path.getsize(os.path.join(OUT, 'usbfix.ico')), 'bytes')

# ---------- 启动画面 ----------
W, H = 640, 300
sp = Image.new('RGB', (W, H), (245, 247, 250))
d = ImageDraw.Draw(sp)
d.rectangle([0, 0, W, 6], fill=BLUE1)

try:
    f_title = ImageFont.truetype(r'C:\Windows\Fonts\msyhbd.ttc', 40)
    f_sub = ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc', 20)
    f_tip = ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc', 17)
except Exception:
    f_title = f_sub = f_tip = ImageFont.load_default()

ic48 = make_icon(72)
sp.paste(ic48, (46, 60), ic48)

d.text((140, 62), 'USB / 串口 一键修复', font=f_title, fill=(20, 40, 70))
SUB_ZH = '修复认不出的 USB / 串口设备，并把端口固定到你选的 COM 号'


def fit(text, font, maxw):
    """按实际像素宽度自动缩字号，宁可小一点也不要被裁掉"""
    sz = getattr(font, 'size', 17)
    while sz > 10:
        f = ImageFont.truetype(r'C://Windows//Fonts//msyh.ttc', sz)
        if d.textlength(text, font=f) <= maxw:
            return f
        sz -= 1
    return font


f_sub = fit(SUB_ZH, f_sub, W - 142 - 40)
d.text((142, 116), SUB_ZH, font=f_sub, fill=(90, 100, 115))
d.text((142, 148), 'Fix undetected USB devices · pin the COM port', font=f_tip, fill=(140, 150, 165))

d.rectangle([46, 200, W - 46, 252], fill=(232, 238, 246))
d.text((62, 210), '正在准备程序…　第一次打开会慢一点，之后就快了', font=f_tip, fill=(21, 101, 192))
d.text((62, 232), 'Please wait — the very first launch takes a few seconds', font=f_tip, fill=(120, 132, 148))

d.text((W - 150, H - 34), '© 永远的兰兰', font=f_tip, fill=(160, 168, 180))

sp.save(os.path.join(OUT, 'splash.png'))
print('splash ->', os.path.getsize(os.path.join(OUT, 'splash.png')), 'bytes')
make_icon(256).save(os.path.join(OUT, 'icon256.png'))
print('done')
