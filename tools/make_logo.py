#!/usr/bin/env python3
"""Generates the Kai-Shelf logo with picocad2-py (github.com/abduznik/picocad2-py).

    PICOCAD2_PY=~/Projects/picocad2-py python3 tools/make_logo.py

Writes assets/icon.png (1024px, opaque), assets/icon_foreground.png (transparent,
for adaptive icons) and assets/logo.txt (the picoCAD 2 project, openable in the editor).

Design: one big open manga volume, comic panels on the left page and a bold
"K" panel on the right, on a round badge. Flat saturated colours so it
reads at 48px.
"""
import os
import sys

root = os.environ.get("PICOCAD2_PY", os.path.expanduser("~/Projects/picocad2-py"))
sys.path.insert(0, root)
from picocad import MOB, Mesh, Project  # noqa: E402
from render import render  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

INK, BROWN, GOLD_DIM, GOLD, GOLD_HI, CREAM = 1, 2, 3, 4, 5, 6
CHERRY_DK, CHERRY, NAVY, BLUE, SKY, GREEN_DK, GREEN, GREY, SILVER = 7, 8, 9, 10, 11, 12, 13, 14, 15

p = Project(palette=MOB)
t = p.texture

PW, PH = 48, 64  # page texture size (px)


def panel(page, x, y, w, h, fill):
    t.fill(page.sub(x, y, w, h), INK)
    t.fill(page.sub(x + 1, y + 1, w - 2, h - 2), fill)
    return page.sub(x + 1, y + 1, w - 2, h - 2)


# ---- left page: three comic panels
left = t.alloc(PW, PH, fill=CREAM)
a = panel(left, 3, 3, 42, 24, SKY)
t.circle(a.x + 30, a.y + 8, 5, GOLD_HI)               # sun
t.fill(a.sub(0, 16, a.w, 6), GREEN)                   # ground
b = panel(left, 3, 30, 20, 31, CHERRY)
t.fill(b.sub(3, 4, 12, 10), CREAM)                    # speech bubble
t.fill(b.sub(5, 14, 4, 3), CREAM)                     # its tail
c = panel(left, 26, 30, 19, 31, GOLD)
t.circle(c.x + 9, c.y + 15, 6, CHERRY)
t.circle(c.x + 9, c.y + 15, 3, CREAM)

# ---- right page: a big pixel K
right = t.alloc(PW, PH, fill=CREAM)
k = panel(right, 3, 3, 42, 58, NAVY)
# Thick K: a stem plus two arms, drawn pixel by pixel as distance-to-segment.
def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    u = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return ((px - ax - u * dx) ** 2 + (py - ay - u * dy) ** 2) ** 0.5


kw_, kh_ = 28, 42
ox, oy = k.x + (k.w - kw_) // 2, k.y + (k.h - kh_) // 2
for y in range(kh_):
    for x in range(kw_):
        inside = (
            x < 9
            or seg_dist(x, y, 9, kh_ / 2, kw_, 0) <= 4.6
            or seg_dist(x, y, 9, kh_ / 2, kw_, kh_) <= 4.6
        )
        if inside:
            t.pset(ox + x, oy + y, GOLD_HI)

m = Mesh()
# cover (cherry) and spine
m.box((5.5, 0.34, 3.9), center=(0, -0.2, 0), color=CHERRY, colors={"top": CHERRY_DK})
# page blocks, tilted down toward the spine
m.box((2.4, 0.34, 3.5), center=(-1.22, 0.1, 0), rot=(0, 0, -7), color=CREAM, tex={"top": left})
m.box((2.4, 0.34, 3.5), center=(1.22, 0.1, 0), rot=(0, 0, 7), color=CREAM, tex={"top": right})

p.add("logo", m)
os.makedirs(OUT, exist_ok=True)
p.save(os.path.join(OUT, "logo.txt"))

kw = dict(size=256, scale=4, yaw=0, pitch=62, fov=14, fit=0.80)
fg = render(p, background=None, outline=1, **kw)
fg.save(os.path.join(OUT, "icon_foreground.png"))

from PIL import Image  # noqa: E402
from PIL import ImageDraw  # noqa: E402
bg = Image.new("RGBA", fg.size, tuple(MOB.rgb(BLUE)) + (255,))
d = ImageDraw.Draw(bg)
w = fg.size[0]
d.ellipse([w * 0.06, w * 0.06, w * 0.94, w * 0.94], fill=tuple(MOB.rgb(SKY)) + (255,))
bg.alpha_composite(fg)
bg.save(os.path.join(OUT, "icon.png"))
print("wrote", os.path.abspath(OUT))
