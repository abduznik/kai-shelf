#!/usr/bin/env python3
"""Generates the Kai-Shelf logo with picocad2-py (github.com/abduznik/picocad2-py).

    PICOCAD2_PY=~/Projects/picocad2-py python3 tools/make_logo.py

Writes assets/icon.png (1024px, opaque), assets/icon_foreground.png (transparent,
for adaptive icons) and assets/logo.txt (the picoCAD 2 project, openable in the editor).
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

# Spine labels: a pixel "K" on the tallest book, bands on the others.
k_spine = t.alloc(16, 32, fill=CHERRY)
t.fill(k_spine.sub(0, 0, 16, 3), GOLD)
t.fill(k_spine.sub(0, 29, 16, 3), GOLD)
for row, bits in enumerate(["1001", "1010", "1100", "1100", "1010", "1001"]):
    for col, b in enumerate(bits):
        if b == "1":
            t.fill(k_spine.sub(4 + col * 2, 10 + row * 2, 2, 2), CREAM)

band = t.alloc(16, 32, fill=BLUE)
t.fill(band.sub(0, 4, 16, 2), SKY)
t.fill(band.sub(0, 26, 16, 2), SKY)
band2 = t.alloc(16, 32, fill=GREEN)
t.fill(band2.sub(0, 6, 16, 3), CREAM)
t.fill(band2.sub(0, 23, 16, 3), CREAM)
pages = t.alloc(8, 8, fill=CREAM)

m = Mesh()
# shelf plank
m.box((6.4, 0.5, 1.8), center=(0, -0.25, 0), color=BROWN, colors={"top": GOLD_DIM})
# books, front (+z) faces carry the spine art
def book(x, w, h, spine, tilt=0.0, color=CHERRY):
    m.box((w, h, 1.3), center=(x, h / 2, 0), color=color, rot=(0, 0, tilt),
          tex={"front": spine}, colors={"top": CREAM, "back": color})

book(-1.7, 0.9, 2.5, band, color=BLUE)
book(-0.6, 1.2, 3.3, k_spine, color=CHERRY)
book(0.6, 0.9, 2.8, band2, color=GREEN)
book(1.75, 0.9, 2.2, band, tilt=-14, color=NAVY)

p.add("logo", m)
os.makedirs(OUT, exist_ok=True)
p.save(os.path.join(OUT, "logo.txt"))

kw = dict(size=256, scale=4, yaw=-18, pitch=14, fit=0.92)
fg = render(p, background=None, outline=1, **kw)
fg.save(os.path.join(OUT, "icon_foreground.png"))

from PIL import Image  # noqa: E402
bg = Image.new("RGBA", fg.size, tuple(MOB.rgb(GOLD_DIM)) + (255,))
# a lighter inner tile so the icon reads as a rounded app tile
bg.alpha_composite(fg)
bg.save(os.path.join(OUT, "icon.png"))
print("wrote", os.path.abspath(OUT))
