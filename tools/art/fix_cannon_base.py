"""Repairs the bite missing from the rim of assets/buildings/cannon_base_sprite.png (it shows once the barrel can
turn) and writes assets/generated/cannon_base_fixed.png. The gap is filled by looking up the colour of the same
distance-from-centre on the intact lower-right of the platform."""
from pathlib import Path
from PIL import Image
import math

ROOT = Path(__file__).resolve().parents[2]
im = Image.open(ROOT / "assets/buildings/cannon_base_sprite.png").convert("RGBA")
px = im.load()
w, h = im.size
CX, CY, RX, RY = 68.0, 87.0, 54.0, 31.0

def rho(x, y):
    return math.hypot((x - CX) / RX, (y - CY) / RY)

# colour table by normalised radius, sampled where the platform is intact: lower right, away from the bite
samples = {}
for y in range(int(CY) + 4, h):
    for x in range(int(CX) + 10, w):
        if px[x, y][3] > 200:
            r = rho(x, y)
            if r <= 1.02:
                samples.setdefault(round(r * 40), []).append(px[x, y])
table = {}
for k, values in samples.items():
    n = len(values)
    table[k] = tuple(sum(v[i] for v in values) // n for i in range(3))
keys = sorted(table)

def lookup(r):
    k = round(r * 40)
    if k in table:
        return table[k]
    nearest = min(keys, key=lambda q: abs(q - k))
    return table[nearest]

filled = 0
for y in range(40, h):
    for x in range(int(CX) + 8, w):
        if px[x, y][3] < 40 and 0.0 < rho(x, y) <= 1.0 and y < CY + 4:
            # only the upper-right wedge where the rim is missing
            r, g, b = lookup(rho(x, y))
            px[x, y] = (r, g, b, 255)
            filled += 1
out = im
out.save(ROOT / "assets/generated/cannon_base_fixed.png")
print("filled", filled)
