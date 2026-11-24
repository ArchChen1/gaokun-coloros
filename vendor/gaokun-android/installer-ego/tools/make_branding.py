#!/usr/bin/env python3
"""生成 ColorOS 分支的安装器图标（不需要 ImageMagick）。

上游用 tool/icon/crdroid-eye.svg 经 ImageMagick 生成图标；ColorOS 分支换成自己的
中性标记（开口朝右的绿色圆环，不带任何上游 / crDroid 元素），由本脚本用 Pillow 直接栅格化：

    python installer-ego/tools/make_branding.py [--repo <gaokun-android 目录>]

产物：
    installer/windows/assets/logo.png                 侧栏标题左边的标志（112×112）
    installer/windows/windows/runner/resources/app_icon.ico   exe / 任务栏图标（16–256 多尺寸）
    installer/windows/web/favicon.png、web/icons/*.png  浏览器预览
    installer/live/assets/logo.png                    LiveCD 安装器（同一份）
"""

import argparse
import os

from PIL import Image, ImageDraw

GREEN = (31, 164, 99, 255)   # ColorOS 风格的绿
# 圆环：外圆 0.86 半径，线宽 0.26；开口朝右（PIL 的 0° 在 3 点钟，顺时针）
ARC_START, ARC_END, R_OUT, R_IN = 40, 320, 0.86, 0.60
SUPERSAMPLE = 4
SIDES = [256, 128, 96, 64, 48, 40, 32, 24, 20, 16]


def render(size: int) -> Image.Image:
    """画一张 size×size 的透明底图标（先超采样再缩，边缘不糊）"""
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    box = [int(big * (1 - R_OUT) / 2), int(big * (1 - R_OUT) / 2),
           int(big * (1 + R_OUT) / 2), int(big * (1 + R_OUT) / 2)]
    width = int(big * (R_OUT - R_IN))
    # 圆环 = 外圆减内圆：先画圆弧（外径），再在中间挖掉内圆
    d.arc(box, start=ARC_START, end=ARC_END, fill=GREEN, width=width)
    inner = [box[0] + width, box[1] + width, box[2] - width, box[3] - width]
    d.pieslice(inner, start=ARC_START, end=ARC_END, fill=(0, 0, 0, 0))
    return img.resize((size, size), Image.LANCZOS)


def save_png(path: str, img: Image.Image) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG", optimize=True)


def write_ico(path: str) -> None:
    """app_icon.ico：把各尺寸的 PNG 直接塞进 ICO 容器（Pillow 的 ico 保存即可）"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    render(256).save(path, "ICO", sizes=[(s, s) for s in SIDES])


def maskable(size: int) -> Image.Image:
    """maskable：底色用界面的深色，图形缩到中间 60% 的安全区"""
    bg = Image.new("RGBA", (size, size), (17, 20, 24, 255))
    mark = render(int(size * 0.6))
    bg.alpha_composite(mark, (int(size * 0.2), int(size * 0.2)))
    return bg


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.join(os.path.dirname(__file__), "..", "..", "..", "third_party", "gaokun-android"),
                    help="gaokun-android 仓库目录")
    a = ap.parse_args()
    win = os.path.join(a.repo, "installer", "windows")
    live = os.path.join(a.repo, "installer", "live")

    logo = render(112)
    save_png(os.path.join(win, "assets", "logo.png"), logo)
    save_png(os.path.join(live, "assets", "logo.png"), logo)
    write_ico(os.path.join(win, "windows", "runner", "resources", "app_icon.ico"))
    save_png(os.path.join(win, "web", "favicon.png"), render(32))
    save_png(os.path.join(win, "web", "icons", "Icon-192.png"), render(192))
    save_png(os.path.join(win, "web", "icons", "Icon-512.png"), render(512))
    for s in (192, 512):
        save_png(os.path.join(win, "web", "icons", f"Icon-maskable-{s}.png"), maskable(s))
    print("OK: logo.png / app_icon.ico / favicon.png / icons/*.png")


if __name__ == "__main__":
    main()
