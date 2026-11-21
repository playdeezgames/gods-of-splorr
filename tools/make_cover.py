#!/usr/bin/env python3
"""Draws the itch.io cover for Gods of SPLORR!!, assets/cover.png (630x500), from the game's own Urizen tiles
(assets/tileset.png, tinted as the game tints them) and a monospace title like the game's panels.
A placeholder until the user wants a real one. Run: python3 -I tools/make_cover.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sheet = Image.open(os.path.join(ROOT, 'assets/tileset.png')).convert('RGB')
W, H, S = 630, 500, 4          # cover size; tiles drawn at 4x (48 px cells)
C = 12 * S
img = Image.new('RGB', (W, H), (10, 20, 10))

def tile(col, row, cx, cy, color, scale=S):
    """Tint one 12x12 Urizen tile (one colour on black) and paste it with its top-left at pixel (cx, cy)."""
    src = sheet.crop((13 * col + 1, 13 * row + 1, 13 * col + 13, 13 * row + 13))
    mask = src.convert('L').point(lambda v: 255 if v > 0 else 0).resize((12 * scale, 12 * scale), Image.NEAREST)
    img.paste(Image.new('RGB', mask.size, color), (cx, cy), mask)

GRASS, TREE, BUSH, POND, STONE = (24, 48, 24), (20, 180, 20), (40, 140, 40), (20, 70, 110), (120, 120, 110)
cols, rows = W // C + 1, H // C + 1
for gy in range(rows):
    for gx in range(cols):
        tile(15, 5, gx * C, gy * C, GRASS)
# A little world along the bottom: trees, berry bushes, a pond, a stone field, the tribe and a snake.
ground = {(0, 7): (0, 8, TREE), (1, 8): (18, 9, BUSH), (3, 7): (0, 8, TREE), (11, 7): (0, 8, TREE), (12, 8): (0, 8, TREE),
          (10, 9): (18, 9, BUSH), (0, 9): (16, 6, POND), (1, 9): (16, 6, POND), (12, 6): (14, 5, STONE), (2, 6): (0, 8, TREE)}
for (gx, gy), (c, r, col) in ground.items():
    img.paste((10, 20, 10), (gx * C, gy * C, gx * C + C, gy * C + C))
    tile(c, r, gx * C, gy * C, col)
for gx, gy, c, r in [(5, 8, 104, 0), (6, 8, 112, 46), (7, 9, 104, 0)]:
    img.paste((10, 20, 10), (gx * C, gy * C, gx * C + C, gy * C + C))
    tile(c, r, gx * C, gy * C, (200, 150, 110))
img.paste((10, 20, 10), (9 * C, 8 * C, 10 * C, 9 * C))
tile(2, 14, 9 * C, 8 * C, (190, 60, 60))                     # a snake creeping in
# The god's gaze: a gold beam onto the tribe.
d = ImageDraw.Draw(img, 'RGBA')
d.polygon([(W // 2 - 20, 0), (W // 2 + 20, 0), (7 * C + 24, 8 * C), (5 * C - 24, 8 * C)], fill=(240, 216, 144, 40))
# Title on a dark band.
d.rectangle((0, 40, W, 250), fill=(5, 10, 5, 215))
bold = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf', 120)
small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf', 44)
GOLD = (240, 216, 144)
for text, font, y in [("GODS", bold, 52), ("of SPLORR!!", small, 190)]:
    w = d.textlength(text, font=font)
    d.text(((W - w) / 2, y), text, font=font, fill=GOLD if font is bold else (207, 232, 207))
img.save(os.path.join(ROOT, 'assets/cover.png'))
print("assets/cover.png", img.size)
