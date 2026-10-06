#!/usr/bin/env python3
"""Generates the Kai-Shelf logo with picocad2-py (github.com/abduznik/picocad2-py).

    PICOCAD2_PY=~/Projects/picocad2-py python3 tools/make_logo.py

Writes assets/icon.png (1024px, opaque), assets/icon_foreground.png (transparent,
for adaptive icons) and assets/logo.txt (the picoCAD 2 project, openable in the editor).

Design: a single chunky 3D "K" in two flat colours on a solid tile. It's an app
icon, so there is deliberately nothing in it that would vanish at 48px.
"""
import math
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

# front faces bright, the extruded sides darker so the depth reads at a glance
SIDES = {"left": GOLD_DIM, "right": GOLD, "top": GOLD, "bottom": GOLD_DIM, "back": GOLD_DIM}

H = 4.0      # letter height
T = 1.15     # stroke thickness
D = 1.3      # extrusion depth
m = Mesh()

# stem
m.box((T, H, D), center=(-0.9, 0, 0), color=GOLD_HI, colors=SIDES)

# arms meet the stem at its middle and fan out to the top/bottom right
arm_len = math.hypot(1.9, H / 2) + 0.35
ang = math.degrees(math.atan2(H / 2, 1.9))
m.box((arm_len, T, D), center=(0.62, H / 4, 0), rot=(0, 0, ang), color=GOLD_HI, colors=SIDES)
m.box((arm_len, T, D), center=(0.62, -H / 4, 0), rot=(0, 0, -ang), color=GOLD_HI, colors=SIDES)

p.add("logo", m)
os.makedirs(OUT, exist_ok=True)
p.save(os.path.join(OUT, "logo.txt"))

kw = dict(size=256, scale=4, yaw=-24, pitch=16, fov=0, fit=0.74)
fg = render(p, background=None, outline=1, **kw)
fg.save(os.path.join(OUT, "icon_foreground.png"))

from PIL import Image  # noqa: E402
bg = Image.new("RGBA", fg.size, tuple(MOB.rgb(NAVY)) + (255,))
bg.alpha_composite(fg)
bg.save(os.path.join(OUT, "icon.png"))
print("wrote", os.path.abspath(OUT))
