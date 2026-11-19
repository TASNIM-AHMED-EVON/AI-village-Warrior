"""Builds assets/generated/town_hall_royal_sprite.png from the original town hall: royal purple roof, gold
ridges, crimson-and-gold banners, red carpet on the stairs and a crown on the spire. Run from anywhere."""
from PIL import Image, ImageDraw
import colorsys, math
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

SRC = str(ROOT / "assets/buildings/town_hall_sprite.png")
im = Image.open(SRC).convert("RGBA")
w, h = im.size
px = im.load()

def hsv(r, g, b): return colorsys.rgb_to_hsv(r/255, g/255, b/255)
def rgb(hh, s, v):
    r, g, b = colorsys.hsv_to_rgb(hh % 1.0, max(0, min(1, s)), max(0, min(1, v)))
    return int(r*255), int(g*255), int(b*255)

def in_poly(x, y, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]; xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi):
            inside = not inside
        j = i
    return inside

# --- areas -------------------------------------------------------------------------------------
BANNERS = [(318, 296, 348, 348), (424, 250, 448, 300)]          # blue crest banners at the door
STAIR_TL, STAIR_TR, STAIR_BR, STAIR_BL = (356, 380), (462, 336), (499, 400), (394, 442)
def lerp(a, b, t): return (a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t)
UP = (-14, -24)
c0 = lerp(STAIR_TL, STAIR_TR, 0.30); c1 = lerp(STAIR_TL, STAIR_TR, 0.70)
d0 = lerp(STAIR_BL, STAIR_BR, 0.30); d1 = lerp(STAIR_BL, STAIR_BR, 0.70)
DOWN = (14, 26)
CARPET = [(c0[0]+UP[0], c0[1]+UP[1]), (c1[0]+UP[0], c1[1]+UP[1]), (d1[0]+DOWN[0], d1[1]+DOWN[1]), (d0[0]+DOWN[0], d0[1]+DOWN[1])]

# --- recolour ----------------------------------------------------------------------------------
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a == 0: continue
        hh, s, v = hsv(r, g, b)
        in_banner = any(bx0 <= x <= bx1 and by0 <= y <= by1 for bx0, by0, bx1, by1 in BANNERS)
        # crimson royal banners (keep the gold crest: warm, bright pixels)
        if in_banner and 0.5 < hh < 0.7 and s > 0.25:
            px[x, y] = (*rgb(0.98, min(0.9, s*1.5), v*1.05), a); continue
        # carpet on the staircase: keep shading, turn stone red
        if in_poly(x, y, CARPET) and s < 0.30 and v > 0.22:
            px[x, y] = (*rgb(0.995, 0.82, v*0.92 + 0.06), a); continue
        # royal purple roof / glass
        if 0.50 < hh < 0.68 and s > 0.12:
            px[x, y] = (*rgb(0.74 + (hh-0.57)*0.2, min(0.8, s*1.45), min(1.0, v*1.14 + 0.02)), a); continue
        # roof ridges and eaves in gold (brown wood above the walls)
        if y < 262 and 0.02 < hh < 0.11 and s > 0.30 and 0.22 < v < 0.75:
            px[x, y] = (*rgb(0.125, 0.78, min(0.97, v*1.5 + 0.12)), a); continue
        # warm up the stone plaza a little
        if y > 330 and x > 300 and s < 0.12 and v > 0.4:
            px[x, y] = (*rgb(0.10, 0.12, min(1.0, v*1.05 + 0.02)), a)

# --- pad the top so the crown has room, then draw the gold details ---------------------------------
PAD = 36
padded = Image.new("RGBA", (w, h + PAD), (0, 0, 0, 0)); padded.alpha_composite(im, (0, PAD)); im = padded
w, h = im.size
S = 4
over = Image.new("RGBA", (w*S, h*S), (0, 0, 0, 0))
d = ImageDraw.Draw(over)
def P(x, y): return (x*S, y*S)
GOLD = (255, 205, 70, 255); GOLD_D = (190, 130, 30, 255); GOLD_L = (255, 240, 170, 255)
# carpet gold edging
SH = lambda p: (p[0], p[1] + PAD)
d.line([P(*SH(CARPET[0])), P(*SH(CARPET[3]))], fill=GOLD, width=int(1.6*S))
d.line([P(*SH(CARPET[1])), P(*SH(CARPET[2]))], fill=GOLD, width=int(1.6*S))
# big crown sitting on the tip of the bell-turret spire
cx, cy = 310, 55
crown = [(cx-14, cy), (cx-14, cy-20), (cx-7, cy-12), (cx, cy-26), (cx+7, cy-12), (cx+14, cy-20), (cx+14, cy)]
d.polygon([P(*p) for p in crown], fill=GOLD, outline=GOLD_D)
d.rectangle([P(cx-14, cy-5), P(cx+14, cy)], fill=GOLD_D)
d.rectangle([P(cx-14, cy-6.2), P(cx+14, cy-5)], fill=GOLD_L)
for gx, gy, col in [(cx-14, cy-20, (235, 60, 85, 255)), (cx, cy-26, (80, 175, 255, 255)), (cx+14, cy-20, (235, 60, 85, 255))]:
    d.ellipse([P(gx-2.6, gy-2.6), P(gx+2.6, gy+2.6)], fill=col, outline=GOLD_D)
for gx in (cx-7, cx+7):
    d.ellipse([P(gx-1.6, cy-3.6), P(gx+1.6, cy-0.4)], fill=(255, 255, 255, 235))
over = over.resize((w, h), Image.LANCZOS)
im.alpha_composite(over)
im.save(ROOT / "assets/generated/town_hall_royal_sprite.png")
print("done", im.size)
