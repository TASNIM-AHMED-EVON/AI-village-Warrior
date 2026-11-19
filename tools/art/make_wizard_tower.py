"""Builds assets/generated/wizard_tower_sprite.png (archer-tower body + a starry wizard-hat roof) and the small
artwork crops the tower animations use (archer, waving banners). Run from anywhere."""
from PIL import Image, ImageDraw, ImageFilter
import colorsys, math, random
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

SRC = str(ROOT / "assets/buildings/archer_tower_sprite.png")
im = Image.open(SRC).convert("RGBA")
w, h = im.size           # 330 x 559
px = im.load()

def hsv(r, g, b): return colorsys.rgb_to_hsv(r/255, g/255, b/255)
def rgb(hh, s, v):
    r, g, b = colorsys.hsv_to_rgb(hh % 1.0, max(0, min(1, s)), max(0, min(1, v)))
    return int(r*255), int(g*255), int(b*255)

CUT_Y = 192        # everything above this (parapet + archer) is replaced by the new roof

# 1) recolour the body: warm wood -> deep violet, blue banners -> arcane purple, stone -> cool blue-grey
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a == 0: continue
        if y < CUT_Y:
            px[x, y] = (0, 0, 0, 0); continue
        hh, s, v = hsv(r, g, b)
        if 0.52 < hh < 0.68 and s > 0.25:                       # banner blue -> purple
            px[x, y] = (*rgb(0.78, min(0.85, s*1.2), min(1, v*1.05)), a)
        elif 0.02 < hh < 0.11 and s > 0.30 and v < 0.62:         # brown timber -> deep violet
            px[x, y] = (*rgb(0.74, min(0.75, s*0.9), v*0.85), a)
        elif 0.06 < hh < 0.18 and 0.08 < s < 0.45 and v > 0.45:  # tan wall panels -> pale lavender
            px[x, y] = (*rgb(0.72, 0.16, min(1, v*0.98)), a)
        elif s < 0.22 and v > 0.25:                              # stone -> cool bluish stone
            px[x, y] = (*rgb(0.64, min(0.28, s + 0.16), min(1, v*1.0)), a)

# 2) the new conical roof, drawn large then reduced to chunky pixels like the rest of the art
S = 4
layer = Image.new("RGBA", (w*S, h*S), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
def P(x, y): return (x*S, y*S)
cx = 167.0
base_y = 190.0
rx, ry = 128.0, 50.0
apex = (cx, 20.0)
# cone body: left darker, right lighter (matches the tower's lighting)
left = [(cx-rx, base_y), apex, (cx, base_y + ry)]
right = [(cx+rx, base_y), apex, (cx, base_y + ry)]
LEFT_C = (88, 58, 150, 255); RIGHT_C = (126, 88, 196, 255)
d.polygon([P(*p) for p in left], fill=LEFT_C)
d.polygon([P(*p) for p in right], fill=RIGHT_C)
# front ellipse underside of the eaves
d.pieslice([P(cx-rx, base_y-ry), P(cx+rx, base_y+ry)], 0, 180, fill=(104, 70, 172, 255))
# shingle rows following the cone
random.seed(7)
for k in range(1, 11):
    t = k / 11.0
    yy = apex[1] + (base_y - apex[1]) * t
    half = rx * t
    sag = ry * t
    for side, col in ((-1, (70, 44, 130, 255)), (1, (160, 120, 224, 255))):
        d.arc([P(cx - half, yy - sag), P(cx + half, yy + sag)], 0, 180, fill=col, width=int(1.4*S))
# vertical seams
for k in range(-4, 5):
    xb = cx + k * rx / 4.5
    d.line([P(cx, apex[1]), P(xb, base_y + ry * math.sqrt(max(0, 1 - ((xb-cx)/rx)**2)))], fill=(60, 36, 112, 140), width=int(1.0*S))
# gold rim around the eaves
d.arc([P(cx-rx, base_y-ry), P(cx+rx, base_y+ry)], 0, 180, fill=(255, 205, 70, 255), width=int(3.2*S))
d.arc([P(cx-rx+3, base_y-ry+2), P(cx+rx-3, base_y+ry-2)], 0, 180, fill=(190, 130, 30, 255), width=int(1.6*S))
# stars on the roof
for sx, sy in [(-52, 120), (-18, 78), (34, 96), (62, 140), (4, 150), (-70, 156), (24, 52)]:
    px0, py0 = cx + sx, sy
    d.polygon([P(px0, py0-4), P(px0+1.4, py0-1.4), P(px0+4, py0), P(px0+1.4, py0+1.4), P(px0, py0+4), P(px0-1.4, py0+1.4), P(px0-4, py0), P(px0-1.4, py0-1.4)], fill=(255, 226, 120, 255))
# gold finial with a star
d.line([P(*apex), P(apex[0], apex[1]-10)], fill=(220, 160, 40, 255), width=int(2.2*S))
d.ellipse([P(apex[0]-4, apex[1]-16), P(apex[0]+4, apex[1]-8)], fill=(255, 215, 90, 255), outline=(190, 130, 30, 255), width=S)
# crescent moon band on the roof front
d.arc([P(cx-24, 100), P(cx+24, 148)], 20, 160, fill=(255, 226, 120, 255), width=int(2.6*S))
small = layer.resize((w//2, h//2), Image.BOX)
sp = small.load()
for yy in range(small.size[1]):
    for xx in range(small.size[0]):
        r, g, b, a = sp[xx, yy]
        sp[xx, yy] = (r, g, b, 255 if a > 100 else 0)
roof = small.resize((w, h), Image.NEAREST)
# dark outline like the rest of the art
alpha = roof.split()[3]
grow = alpha.filter(ImageFilter.MaxFilter(3))
outline = Image.new("RGBA", roof.size, (24, 12, 36, 255)); outline.putalpha(grow)
roof = Image.alpha_composite(outline, roof)
im.alpha_composite(roof)

out = ROOT / "assets/generated"
im.save(out / "wizard_tower_sprite.png")

# 4) crops used by the animations: (x, y, width, height) in sprite pixels
ARCHER_RECT = (95, 50, 140, 140)
BANNER_L = (94, 258, 46, 88)
BANNER_R = (194, 258, 44, 88)
original = Image.open(SRC).convert("RGBA")
original.crop((ARCHER_RECT[0], ARCHER_RECT[1], ARCHER_RECT[0] + ARCHER_RECT[2], ARCHER_RECT[1] + ARCHER_RECT[3])).save(out / "archer_tower_archer.png")
for name, rect in (("l", BANNER_L), ("r", BANNER_R)):
    box = (rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3])
    original.crop(box).save(out / f"archer_tower_banner_{name}.png")
    im.crop(box).save(out / f"wizard_tower_banner_{name}.png")
print("ok", im.size)
