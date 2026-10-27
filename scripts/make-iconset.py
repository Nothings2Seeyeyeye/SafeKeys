#!/usr/bin/env python3
"""把 AI 生成的图标源图规范化为 macOS 图标网格规范。

问题背景：AI 生成的 squircle 往往铺满整个 1024 画布，而 Apple 模板要求
图形内容只占画布约 80%（squircle 为 824/1024），其余为透明边距。
铺满的图标放进 Dock 会比其他规范图标明显偏大。

处理：
  1. 裁剪源图的透明边，得到图形内容的紧致包围盒
  2. 缩放到目标占比（>=128px 用 80.5%，小尺寸用 90% 保证辨识度）
  3. 居中贴到正方形透明画布
  4. 直接输出 iconset 全部 10 个尺寸（Lanczos 重采样）
"""
import os
import sys
from PIL import Image

SRC = sys.argv[1]
OUT_DIR = sys.argv[2]

# (边长, 文件名)。@2x 是 retina 版本。
SIZES = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

# 大尺寸按 Apple 模板：图形 824 / 画布 1024 ≈ 0.805
# 小尺寸（16/32）屏幕上太小，再留 20% 边距会糊，放宽到 90%
LARGE_RATIO = 824 / 1024
SMALL_RATIO = 0.90
SMALL_THRESHOLD = 128

os.makedirs(OUT_DIR, exist_ok=True)

img = Image.open(SRC).convert("RGBA")

# 1) 裁掉透明边（对半透明像素也算内容）
alpha = img.getchannel("A")
bbox = alpha.point(lambda a: 255 if a > 8 else 0).getbbox()
content = img.crop(bbox) if bbox else img

# 2) 逐尺寸输出
for canvas_size, name in SIZES:
    ratio = SMALL_RATIO if canvas_size < SMALL_THRESHOLD else LARGE_RATIO
    target = round(canvas_size * ratio)

    # 内容可能是长方形，等比缩放到限制框内
    scale = min(target / content.width, target / content.height)
    w = max(1, round(content.width * scale))
    h = max(1, round(content.height * scale))
    resized = content.resize((w, h), Image.LANCZOS)

    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((canvas_size - w) // 2, (canvas_size - h) // 2))
    canvas.save(f"{OUT_DIR}/{name}")
    print(f"  {name}: 内容 {w}x{h} / 画布 {canvas_size} ({ratio:.1%})")

print("done")
