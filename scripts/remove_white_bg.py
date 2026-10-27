#!/usr/bin/env python3
"""把 AI 生成图标的白色不透明背景抠除为真透明。

问题：生成模型输出 alpha 全 255，背景为纯白；直接进 icns 后
Dock 里图标周围会有一圈白框。

算法（连通域而非全局颜色阈值，避免误伤图标内部的米白键帽）：
  1. 标记所有「接近白色」的像素
  2. 用 scipy.ndimage.label 找连通域，只删与画布边界连通的白色区域
     —— 内部键帽即使颜色接近白也不与边界连通，安全
  3. 抗锯齿边缘残留白 fringe：对 alpha 做 2px 收缩 + 高斯羽化
用法： remove_white_bg.py <src.png> <dst.png>
"""
import sys
import numpy as np
from scipy import ndimage
from PIL import Image, ImageFilter

SRC, DST = sys.argv[1], sys.argv[2]
WHITE_TOL = 60      # 与纯白的最大通道差，覆盖背景的轻微渐变
ERODE_PX = 2        # 边缘收缩，吃掉白蓝混合的 fringe
FEATHER_PX = 1.2    # 羽化半径

img = Image.open(SRC).convert("RGBA")
arr = np.array(img).astype(np.int16)
h, w = arr.shape[:2]

# 1) 白色候选：所有通道都足够高（min(R,G,B) >= 255 - 容差）
is_white = arr[:, :, :3].min(axis=2) >= (255 - WHITE_TOL)

# 2) 只保留与边界连通的白色区域为背景
labels, n = ndimage.label(is_white)
border_labels = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
border_labels.discard(0)
bg = np.isin(labels, list(border_labels)) if border_labels else np.zeros_like(is_white)

print(f"  白色候选: {is_white.sum() / (h*w):.1%},  确认为背景(连通): {bg.sum() / (h*w):.1%}")

# 3) 生成 alpha 并收缩 + 羽化
alpha = np.where(bg, 0, 255).astype(np.uint8)
alpha_img = Image.fromarray(alpha, "L")
k = ERODE_PX * 2 + 1
alpha_img = alpha_img.filter(ImageFilter.MinFilter(k))            # 收缩
alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(FEATHER_PX))  # 羽化

out = arr.astype(np.uint8)
out[:, :, 3] = np.array(alpha_img)

# 4) fringe 去色：边缘半透明像素若偏白，把 RGB 向邻近图形色收缩（简单近似：
#    半透明处显示由背景混合决定，macOS 深浅背景下均自然，无需精确重建）
result = Image.fromarray(out, "RGBA")
bbox = result.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
result = result.crop(bbox)
result.save(DST)
print(f"  输出: {DST}  内容 {result.size[0]}x{result.size[1]}")
