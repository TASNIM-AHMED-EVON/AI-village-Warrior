from PIL import Image, ImageDraw, ImageFilter
import math

S = 4                      # supersample factor
CW, CH = 160, 140          # cell size in final pixels
VW, VH = 205, 178          # virtual canvas the creature is drawn on, scaled down to the cell
OX, OY = 26, 34            # offset so wings never clip

def P(pts):                # scale list of (x,y) to supersampled coords
    return [((x+OX)*S, (y+OY)*S) for x, y in pts]

def Q(x, y):
    return ((x+OX)*S, (y+OY)*S)

def rot(pts, ang, origin):
    ox, oy = origin
    c, s = math.cos(ang), math.sin(ang)
    return [(ox + (x-ox)*c - (y-oy)*s, oy + (x-ox)*s + (y-oy)*c) for x, y in pts]

def bez(p0, p1, p2, n=18):
    out = []
    for i in range(n+1):
        t = i/n
        x = (1-t)**2*p0[0] + 2*(1-t)*t*p1[0] + t*t*p2[0]
        y = (1-t)**2*p0[1] + 2*(1-t)*t*p1[1] + t*t*p2[1]
        out.append((x, y))
    return out

def thick_line(d, pts, w0, w1, fill):
    n = len(pts)
    for i in range(n-1):
        w = w0 + (w1-w0)*i/(n-1)
        x0, y0 = pts[i]; x1, y1 = pts[i+1]
        d.line([Q(x0, y0), Q(x1, y1)], fill=fill, width=int(w*S))
        r = w*S/2
        qx, qy = Q(x1, y1)
        d.ellipse([qx-r, qy-r, qx+r, qy+r], fill=fill)
    x0, y0 = pts[0]; r = w0*S/2
    qx, qy = Q(x0, y0)
    d.ellipse([qx-r, qy-r, qx+r, qy+r], fill=fill)

BODY   = (186, 44, 44, 255)
BODY_D = (128, 26, 36, 255)
BELLY  = (244, 196, 98, 255)
BELLY_D= (214, 150, 70, 255)
MEMB   = (222, 92, 56, 255)
MEMB_D = (150, 52, 48, 255)
BONE   = (96, 26, 30, 255)
HORN   = (246, 232, 196, 255)
EYE    = (255, 226, 70, 255)

def wing(d, shoulder, theta, scale, far=False):
    # base shape (pointing up-left from the shoulder), local coords relative to shoulder
    arm   = [(0, 0), (-8, -26), (-22, -48)]            # shoulder -> elbow -> wrist
    tips  = [(-58, -62), (-74, -40), (-70, -14), (-52, 2)]
    trail = [(-26, -6)]
    sx, sy = shoulder
    def place(pts):
        pts = [(sx + x*scale, sy + y*scale) for x, y in pts]
        return rot(pts, theta, (sx, sy))
    wrist = place([arm[2]])[0]
    membrane = place([arm[0], arm[1], arm[2]] + tips + trail)
    d.polygon(P(membrane), fill=MEMB_D if far else MEMB)
    # finger bones
    for t in place(tips):
        d.line([Q(*wrist), Q(*t)], fill=BONE, width=int(2.2*S))
    arm_pts = place(arm)
    d.line(P(arm_pts), fill=BONE, width=int(3.2*S))
    # scalloped trailing edge shading
    inner = place([(-20, -12), (-34, -22), (-46, -16), (-36, -4)])
    d.polygon(P(inner), fill=(MEMB_D if far else (236, 120, 74, 255)))

def render(flap=0.0, mouth=0.0, tilt=0.0, shade=1.0):
    img = Image.new("RGBA", (VW*S, VH*S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    theta_far  = -0.50 + flap*0.85
    theta_near = -0.35 + flap*0.95
    # far wing (behind)
    wing(d, (70, 64), theta_far, 0.92, far=True)
    # tail
    tail = bez((52, 84), (14, 100), (8, 72), 22)
    thick_line(d, tail, 12, 2.5, BODY_D)
    tip = tail[-1]
    d.polygon(P([(tip[0]-1, tip[1]-4), (tip[0]-7, tip[1]-14), (tip[0]+5, tip[1]-6)]), fill=HORN)
    # back legs
    d.ellipse(P([(62, 88), (78, 108)])[0] + P([(62, 88), (78, 108)])[1], fill=BODY_D)
    # body
    body = [(46, 82), (54, 66), (78, 58), (102, 64), (108, 78), (98, 94), (72, 98), (52, 94)]
    d.polygon(P(body), fill=BODY)
    belly = [(54, 90), (76, 96), (98, 92), (104, 82), (92, 88), (70, 90)]
    d.polygon(P(belly), fill=BELLY)
    for i in range(5):                       # belly plates
        x = 60 + i*8
        d.line([Q(x, 89), Q(x+2, 95)], fill=BELLY_D, width=int(1.4*S))
    # back spines
    for i in range(6):
        x = 56 + i*8
        y = 66 - abs(i-2.5)*0.8
        d.polygon(P([(x, y+2), (x+3, y-7), (x+7, y+2)]), fill=BONE)
    # neck
    neck = bez((98, 70), (116, 70), (121, 52), 14)
    thick_line(d, neck, 15, 11, BODY)
    thick_line(d, bez((99, 78), (114, 76), (119, 58), 14), 6, 4, BELLY)
    # head
    hx, hy = 124, 46
    skull = [(hx-12, hy-3), (hx-6, hy-11), (hx+8, hy-11), (hx+16, hy-5), (hx+14, hy+3), (hx-6, hy+8)]
    d.polygon(P(skull), fill=BODY)
    snout = [(hx+8, hy-8), (hx+30, hy-4), (hx+31, hy+1), (hx+8, hy+3)]
    d.polygon(P(snout), fill=BODY)
    jaw_drop = mouth*10
    jaw = [(hx+2, hy+3), (hx+28, hy+1+jaw_drop*0.9), (hx+26, hy+5+jaw_drop), (hx-2, hy+9+jaw_drop*0.4)]
    if mouth > 0.05:
        d.polygon(P([(hx+4, hy+1), (hx+29, hy), (hx+28, hy+2+jaw_drop)]), fill=(70, 12, 18, 255))
        d.polygon(P([(hx+10, hy+1), (hx+24, hy+1), (hx+22, hy+2+jaw_drop*0.7)]), fill=(255, 150, 40, 255))
    d.polygon(P(jaw), fill=BODY_D)
    for k in range(3):                       # teeth
        tx = hx + 14 + k*5
        d.polygon(P([(tx, hy+1), (tx+2, hy+1), (tx+1, hy+4)]), fill=HORN)
    # nostril + eye + brow
    d.ellipse(P([(hx+26, hy-3), (hx+28.5, hy-0.8)])[0] + P([(hx+26, hy-3), (hx+28.5, hy-0.8)])[1], fill=BONE)
    d.ellipse(P([(hx+4, hy-7), (hx+11, hy-1)])[0] + P([(hx+4, hy-7), (hx+11, hy-1)])[1], fill=EYE)
    d.ellipse(P([(hx+7, hy-6), (hx+10, hy-2)])[0] + P([(hx+7, hy-6), (hx+10, hy-2)])[1], fill=(30, 10, 10, 255))
    d.line(P([(hx+2, hy-9), (hx+13, hy-6)]), fill=BONE, width=int(2*S))
    # horns
    d.polygon(P([(hx-5, hy-9), (hx-24, hy-24), (hx-12, hy-6)]), fill=HORN)
    d.polygon(P([(hx+1, hy-10), (hx-14, hy-27), (hx-5, hy-8)]), fill=(214, 200, 164, 255))
    # front legs / claws
    d.ellipse(P([(80, 90), (96, 110)])[0] + P([(80, 90), (96, 110)])[1], fill=BODY)
    for cx in (68, 74, 88, 94):
        d.polygon(P([(cx, 106), (cx+2, 106), (cx+1, 111)]), fill=HORN)
    # near wing (in front)
    wing(d, (72, 62), theta_near, 1.0)
    # rotate whole creature for death animation
    if abs(tilt) > 0.001:
        img = img.rotate(-math.degrees(tilt), resample=Image.BICUBIC, center=(VW*S*0.55, VH*S*0.62))
    # outline: dilate alpha and paint dark behind
    alpha = img.split()[3]
    grow = alpha.filter(ImageFilter.MaxFilter(2*S+1))
    outline = Image.new("RGBA", img.size, (28, 8, 12, 255))
    outline.putalpha(grow)
    out = Image.alpha_composite(outline, img)
    if shade < 1.0:
        px = out.load()
        for y in range(out.size[1]):
            for x in range(out.size[0]):
                r, g, b, a = px[x, y]
                if a:
                    gray = (r + g + b)//3
                    px[x, y] = (int(r*shade*0.6 + gray*0.4*shade), int(g*shade*0.6 + gray*0.4*shade), int(b*shade*0.6 + gray*0.4*shade), a)
    # downscale to a chunky pixel-art look
    small = out.resize((CW//2, CH//2), Image.BOX)  # whole virtual canvas -> half-res cell
    # quantize alpha hard so edges stay crisp
    sp = small.load()
    for y in range(small.size[1]):
        for x in range(small.size[0]):
            r, g, b, a = sp[x, y]
            sp[x, y] = (r, g, b, 255 if a > 110 else 0)
    return small.resize((CW, CH), Image.NEAREST)

def sheet():
    rows = [("idle", 8), ("attack", 6), ("death", 5)]
    out = Image.new("RGBA", (8*CW, 3*CH), (0, 0, 0, 0))
    for r, (name, n) in enumerate(rows):
        for i in range(n):
            if name == "idle":
                f = render(flap=math.sin(i/n*math.tau))
            elif name == "attack":
                f = render(flap=0.45*math.sin(i/n*math.tau), mouth=0.9 if i % 6 not in (0,) else 0.6)
            else:
                t = i/(n-1)
                f = render(flap=0.9, mouth=0.5, tilt=t*1.15, shade=1.0 - 0.45*t)
            out.paste(f, (i*CW, r*CH))
    return out

if __name__ == "__main__":
    sh = sheet()
    sh.save("/tmp/dragon/dragon_sheet.png")
    render(flap=0.0).save("/tmp/dragon/dragon_sprite.png")
    prev = Image.new("RGBA", (8*CW, 3*CH), (86, 130, 76, 255))
    prev.alpha_composite(sh)
    prev.save("/tmp/dragon/preview.png")
    print("ok", sh.size)
