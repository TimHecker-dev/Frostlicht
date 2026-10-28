#!/usr/bin/env python3
"""Erzeugt alle Platzhalter-Grafiken für Frostlicht (res://art/*.png).

Alles wird hier per Code gezeichnet, damit das Projekt ohne externe Assets läuft.
Eigene Grafiken kannst du einfach unter dem gleichen Dateinamen in art/ ersetzen.
Benötigt: pip install pillow
Aufruf:   python3 tools/make_art.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageOps

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art"))
os.makedirs(OUT, exist_ok=True)

OUTLINE = (34, 30, 54, 255)
CLEAR = (0, 0, 0, 0)


def new(w, h):
    img = Image.new("RGBA", (w, h), CLEAR)
    return img, ImageDraw.Draw(img)


def save(img, name):
    img.save(os.path.join(OUT, name))


def outline(img, color=OUTLINE):
    """Legt eine 1-Pixel-Kontur um alles Sichtbare."""
    w, h = img.size
    src = img.load()
    out = img.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 200:
                        dst[x, y] = color
                        break
    return out


# ---------------------------------------------------------------- Boden
def make_ground(size=256):
    rnd = random.Random(11)
    levels = [(222, 234, 248), (227, 238, 250), (232, 242, 252), (237, 245, 254)]
    g = 16
    small = Image.new("L", (g, g))
    small.putdata([rnd.randrange(256) for _ in range(g * g)])
    tiled = Image.new("L", (g * 3, g * 3))
    for ox in range(3):
        for oy in range(3):
            tiled.paste(small, (ox * g, oy * g))
    big = tiled.resize((size * 3, size * 3), Image.BICUBIC).crop((size, size, size * 2, size * 2))
    big = ImageOps.autocontrast(big)
    img = Image.new("RGBA", (size, size))
    px, ip = big.load(), img.load()
    for y in range(size):
        for x in range(size):
            lvl = min(3, px[x, y] * 4 // 256)
            ip[x, y] = levels[lvl] + (255,)
    d = ImageDraw.Draw(img)

    def wrapped(cx, cy, rx, ry, col):
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                d.ellipse([cx - rx + ox, cy - ry + oy, cx + rx + ox, cy + ry + oy], fill=col)

    for _ in range(26):  # kleine Verwehungen mit Schattenkante
        cx, cy = rnd.randrange(size), rnd.randrange(size)
        rx, ry = rnd.randint(6, 16), rnd.randint(2, 4)
        wrapped(cx, cy + 1, rx, ry, (212, 226, 243, 255))
        wrapped(cx, cy, rx, ry, (238, 246, 254, 255))
    for _ in range(130):  # Glitzerpunkte
        ip[rnd.randrange(size), rnd.randrange(size)] = (255, 255, 255, 255)
    for _ in range(170):  # kleine Mulden
        ip[rnd.randrange(size), rnd.randrange(size)] = (198, 214, 236, 255)
    save(img, "ground.png")


# ---------------------------------------------------------------- Spielfigur
SKIN, SKIN_D = (244, 208, 176, 255), (222, 172, 144, 255)
HAT, HAT_L, HAT_D = (196, 72, 84, 255), (228, 110, 114, 255), (158, 52, 70, 255)
CUFF, CUFF_D = (246, 234, 212, 255), (214, 198, 178, 255)
COAT, COAT_L, COAT_D = (76, 114, 162, 255), (104, 146, 194, 255), (54, 84, 128, 255)
SCARF, SCARF_D = (238, 152, 70, 255), (202, 110, 50, 255)
PANTS, PANTS_D = (62, 68, 112, 255), (46, 52, 90, 255)
BOOT, BOOT_D = (98, 68, 56, 255), (70, 48, 44, 255)
PACK, PACK_D = (128, 92, 68, 255), (98, 68, 52, 255)
EYE, CHEEK = (36, 32, 56, 255), (238, 152, 152, 255)


def player_front():
    img, d = new(24, 32)
    d.rectangle([8, 26, 11, 28], fill=PANTS)
    d.rectangle([12, 26, 15, 28], fill=PANTS_D)
    d.rectangle([7, 28, 11, 29], fill=BOOT)
    d.rectangle([12, 28, 16, 29], fill=BOOT_D)
    d.rounded_rectangle([6, 18, 17, 27], radius=3, fill=COAT)
    d.rectangle([14, 20, 17, 26], fill=COAT_D)
    d.rectangle([7, 20, 8, 25], fill=COAT_L)
    d.rectangle([6, 24, 17, 24], fill=PANTS_D)  # Gürtel
    d.rectangle([4, 19, 6, 25], fill=COAT_D)
    d.rectangle([17, 19, 19, 25], fill=COAT_D)
    d.rectangle([4, 25, 6, 26], fill=SKIN)
    d.rectangle([17, 25, 19, 26], fill=SKIN)
    d.ellipse([5, 5, 18, 17], fill=SKIN)
    d.pieslice([4, 1, 19, 17], 180, 360, fill=HAT)
    d.rectangle([6, 3, 8, 4], fill=HAT_L)
    d.rectangle([14, 5, 17, 8], fill=HAT_D)
    d.rounded_rectangle([4, 8, 19, 10], radius=1, fill=CUFF)
    d.rectangle([14, 10, 19, 10], fill=CUFF_D)
    d.ellipse([10, 0, 13, 3], fill=CUFF)
    d.rectangle([8, 12, 8, 13], fill=EYE)
    d.rectangle([15, 12, 15, 13], fill=EYE)
    d.point([7, 15], fill=CHEEK)
    d.point([16, 15], fill=CHEEK)
    d.rectangle([7, 16, 16, 19], fill=SCARF)
    d.rectangle([7, 18, 16, 18], fill=SCARF_D)
    d.rectangle([7, 19, 9, 24], fill=SCARF)
    d.rectangle([7, 24, 9, 24], fill=SCARF_D)
    return outline(img)


def player_back():
    img, d = new(24, 32)
    d.rectangle([8, 26, 11, 28], fill=PANTS)
    d.rectangle([12, 26, 15, 28], fill=PANTS_D)
    d.rectangle([7, 28, 11, 29], fill=BOOT)
    d.rectangle([12, 28, 16, 29], fill=BOOT_D)
    d.rounded_rectangle([6, 18, 17, 27], radius=3, fill=COAT)
    d.rectangle([14, 20, 17, 26], fill=COAT_D)
    d.rectangle([4, 19, 6, 25], fill=COAT_D)
    d.rectangle([17, 19, 19, 25], fill=COAT_D)
    d.rectangle([4, 25, 6, 26], fill=SKIN)
    d.rectangle([17, 25, 19, 26], fill=SKIN)
    d.rounded_rectangle([8, 19, 15, 25], radius=2, fill=PACK)
    d.rectangle([8, 23, 15, 25], fill=PACK_D)
    d.rectangle([8, 20, 15, 20], fill=PACK_D)
    d.ellipse([4, 1, 19, 16], fill=HAT)
    d.rectangle([6, 3, 8, 4], fill=HAT_L)
    d.rectangle([14, 6, 18, 11], fill=HAT_D)
    d.rounded_rectangle([4, 11, 19, 13], radius=1, fill=CUFF)
    d.rectangle([14, 13, 19, 13], fill=CUFF_D)
    d.ellipse([10, 0, 13, 3], fill=CUFF)
    d.rectangle([7, 15, 16, 18], fill=SCARF)
    d.rectangle([7, 17, 16, 17], fill=SCARF_D)
    d.rectangle([11, 18, 13, 23], fill=SCARF)
    d.rectangle([11, 23, 13, 23], fill=SCARF_D)
    return outline(img)


def player_side():
    img, d = new(24, 32)
    d.rectangle([13, 26, 16, 28], fill=PANTS_D)
    d.rectangle([9, 26, 12, 28], fill=PANTS)
    d.rectangle([13, 28, 18, 29], fill=BOOT_D)
    d.rectangle([8, 28, 12, 29], fill=BOOT)
    d.rectangle([2, 19, 8, 22], fill=SCARF)  # Schalende flattert hinten
    d.rectangle([1, 22, 4, 25], fill=SCARF_D)
    d.rounded_rectangle([7, 18, 16, 27], radius=3, fill=COAT)
    d.rectangle([13, 20, 16, 26], fill=COAT_D)
    d.rectangle([10, 20, 13, 25], fill=COAT_L)
    d.rectangle([10, 25, 13, 26], fill=SKIN)
    d.ellipse([5, 5, 18, 17], fill=SKIN)
    d.rectangle([19, 12, 19, 13], fill=SKIN)  # Nase
    d.pieslice([4, 1, 19, 17], 180, 360, fill=HAT)
    d.rectangle([6, 3, 8, 4], fill=HAT_L)
    d.rectangle([5, 5, 10, 8], fill=HAT_D)
    d.rounded_rectangle([4, 8, 19, 10], radius=1, fill=CUFF)
    d.rectangle([4, 10, 9, 10], fill=CUFF_D)
    d.ellipse([5, 0, 8, 3], fill=CUFF)
    d.rectangle([14, 12, 14, 13], fill=EYE)
    d.point([15, 15], fill=CHEEK)
    d.rectangle([7, 16, 16, 19], fill=SCARF)
    d.rectangle([7, 18, 16, 18], fill=SCARF_D)
    return outline(img)


def make_player():
    sheet = Image.new("RGBA", (72, 32), CLEAR)
    for i, f in enumerate((player_front(), player_back(), player_side())):
        sheet.paste(f, (i * 24, 0))
    save(sheet, "player.png")


# ---------------------------------------------------------------- Gegner
def make_blob():
    img, d = new(26, 24)
    d.polygon([(5, 9), (7, 3), (10, 9)], fill=(205, 234, 252, 255))
    d.polygon([(10, 8), (13, 0), (16, 8)], fill=(214, 240, 254, 255))
    d.polygon([(16, 9), (19, 4), (21, 9)], fill=(196, 228, 250, 255))
    d.ellipse([2, 7, 23, 21], fill=(90, 160, 210, 255))
    d.ellipse([3, 7, 22, 18], fill=(124, 198, 234, 255))
    d.ellipse([6, 9, 11, 12], fill=(206, 238, 252, 255))
    d.ellipse([7, 13, 10, 17], fill=(30, 40, 72, 255))
    d.ellipse([15, 13, 18, 17], fill=(30, 40, 72, 255))
    d.point([7, 13], fill=(255, 255, 255, 255))
    d.point([15, 13], fill=(255, 255, 255, 255))
    d.line([6, 11, 10, 12], fill=(30, 40, 72, 255))
    d.line([19, 11, 15, 12], fill=(30, 40, 72, 255))
    save(outline(img), "enemy_blob.png")


def make_wisp():
    img, d = new(22, 28)
    d.polygon([(4, 11), (17, 11), (18, 22), (15, 20), (13, 25), (10, 21), (7, 25), (5, 20), (3, 22)],
              fill=(226, 238, 252, 255))
    d.ellipse([3, 2, 18, 17], fill=(236, 245, 254, 255))
    d.polygon([(13, 11), (17, 11), (18, 22), (15, 20), (13, 25)], fill=(180, 206, 238, 255))
    d.ellipse([13, 6, 18, 15], fill=(196, 218, 244, 255))
    d.ellipse([6, 8, 8, 12], fill=(40, 52, 96, 255))
    d.ellipse([12, 8, 14, 12], fill=(40, 52, 96, 255))
    d.point([6, 8], fill=(255, 255, 255, 255))
    d.point([12, 8], fill=(255, 255, 255, 255))
    d.rectangle([9, 14, 10, 14], fill=(120, 150, 200, 255))
    save(outline(img, (40, 52, 100, 255)), "enemy_wisp.png")


# ---------------------------------------------------------------- Welt
G_MID, G_DARK, G_LIGHT = (58, 112, 94, 255), (38, 80, 74, 255), (88, 146, 114, 255)
SNOW, SNOW_D = (248, 251, 255, 255), (206, 222, 242, 255)
TRUNK = (98, 70, 58, 255)


def pine(w, h, tiers, seed, lights=False):
    rnd = random.Random(seed)
    img, d = new(w, h)
    cx = w // 2
    trunk_h = max(4, round(h * 0.13))
    d.rectangle([cx - 2, h - 2 - trunk_h, cx + 1, h - 3], fill=TRUNK)
    d.rectangle([cx + 1, h - 2 - trunk_h, cx + 1, h - 3], fill=(74, 52, 46, 255))
    fol_h = h - trunk_h - 3
    tier_h = fol_h * (0.62 if tiers == 2 else 0.5)
    step = (fol_h - tier_h) / (tiers - 1)
    for i in range(tiers - 1, -1, -1):  # unten zuerst
        apex = 1 + i * step
        base = apex + tier_h
        hw = (w / 2 - 2) * (0.52 + 0.48 * i / (tiers - 1))
        d.polygon([(cx, apex), (cx - hw, base), (cx + hw, base)], fill=G_MID)
        d.polygon([(cx, apex), (cx + hw, base), (cx, base)], fill=G_DARK)
        d.polygon([(cx, apex + 3), (cx - hw * 0.8, base - 1), (cx - hw * 0.35, base - 1)], fill=G_LIGHT)
        d.line([(cx - hw + 1, base), (cx + hw - 1, base)], fill=(30, 62, 62, 255))
        # Schneehaube
        top = apex + tier_h * 0.48
        sw = hw * 0.5
        d.polygon([(cx, apex), (cx - sw, top), (cx + sw, top)], fill=SNOW)
        d.polygon([(cx, apex), (cx + sw, top), (cx, top)], fill=SNOW_D)
        # Schneeklumpen am Rand
        for sx in (-0.78, -0.4, 0.45, 0.8):
            ex = cx + hw * sx
            ey = base - rnd.randint(1, 3)
            d.ellipse([ex - 2.2, ey - 1.5, ex + 2.2, ey + 1.0], fill=SNOW)
    if lights:
        cols = [(255, 214, 110, 255), (255, 150, 90, 255), (255, 240, 170, 255)]
        for _ in range(11):
            y = rnd.randint(int(h * 0.2), int(h * 0.78))
            half = (y / h) * (w / 2 - 5)
            x = cx + rnd.uniform(-half, half)
            d.rectangle([x, y, x + 1, y + 1], fill=rnd.choice(cols))
    return outline(img)


def make_trees():
    save(pine(40, 62, 3, 1), "tree_a.png")
    save(pine(30, 48, 3, 2), "tree_b.png")
    save(pine(22, 34, 2, 3), "tree_c.png")
    save(pine(40, 62, 3, 4, lights=True), "tree_lit.png")


def make_rock():
    img, d = new(24, 18)
    d.polygon([(2, 15), (3, 8), (8, 3), (16, 2), (21, 7), (22, 15), (12, 16)], fill=(112, 124, 150, 255))
    d.polygon([(12, 16), (22, 15), (21, 7), (16, 2), (14, 9)], fill=(84, 94, 122, 255))
    d.polygon([(3, 8), (8, 3), (13, 3), (9, 9)], fill=(150, 162, 186, 255))
    d.polygon([(5, 6), (9, 2), (16, 1), (19, 5), (13, 6), (9, 8)], fill=SNOW)
    d.polygon([(13, 6), (19, 5), (16, 1)], fill=SNOW_D)
    save(outline(img), "rock.png")


def make_mound():
    img, d = new(30, 12)
    d.ellipse([1, 4, 28, 11], fill=(204, 220, 240, 255))
    d.ellipse([2, 2, 20, 9], fill=(238, 246, 254, 255))
    d.ellipse([14, 4, 27, 9], fill=(230, 240, 252, 255))
    d.ellipse([5, 2, 12, 5], fill=(252, 254, 255, 255))
    save(img, "mound.png")


def make_campfire():
    img, d = new(36, 26)
    cx, cy = 18, 16
    stones = [(cx + 12 * math.cos(math.radians(a)), cy + 6 * math.sin(math.radians(a)))
              for a in range(0, 360, 40)]

    def stone(x, y):
        d.ellipse([x - 3.5, y - 3, x + 3.5, y + 2.5], fill=(120, 130, 154, 255))
        d.ellipse([x - 3.5, y - 3, x + 1, y], fill=(158, 168, 190, 255))

    d.ellipse([cx - 9, cy - 4, cx + 9, cy + 5], fill=(54, 46, 54, 255))
    for x, y in stones:
        if y < cy:
            stone(x, y)
    for ang in (-30, 25, 90):
        a = math.radians(ang)
        dx, dy = 8 * math.cos(a), 4 * math.sin(a)
        d.line([cx - dx, cy - dy + 1, cx + dx, cy + dy + 1], fill=(104, 70, 50, 255), width=3)
        d.line([cx - dx, cy - dy, cx + dx, cy + dy], fill=(140, 96, 66, 255), width=1)
    for x, y in stones:
        if y >= cy:
            stone(x, y)
    save(outline(img), "campfire.png")


def make_small():
    # Schatten
    img, d = new(28, 12)
    d.ellipse([0, 0, 27, 11], fill=(10, 14, 40, 70))
    d.ellipse([3, 2, 24, 9], fill=(10, 14, 40, 70))
    save(img, "shadow.png")
    # Schwung (zeigt nach rechts): dicke, helle Mondsichel
    size_s = 44
    sl = Image.new("RGBA", (size_s, size_s), CLEAR)
    p = sl.load()
    cy = size_s / 2 - 0.5
    for y in range(size_s):
        for x in range(size_s):
            dist = math.hypot(x - 12, y - cy)
            if dist < 20 and math.hypot(x - 2, y - cy) >= 17.2:
                ang = abs(math.atan2(y - cy, x - 12))
                a = max(0.0, 1.0 - ang / 1.35)
                core = 1.0 if dist > 16.5 else 0.75
                p[x, y] = (255, 250, 236, int(255 * min(1.0, a * 1.7) * core))
    save(sl, "slash.png")
    # Fußabdruck
    fp, d = new(5, 4)
    d.ellipse([0, 0, 4, 3], fill=(150, 172, 204, 170))
    save(fp, "footprint.png")
    # Licht (Graustufen, 255 = voll hell)
    size = 256
    li = Image.new("RGBA", (size, size))
    lp = li.load()
    for y in range(size):
        for x in range(size):
            r = math.hypot(x - size / 2 + 0.5, y - size / 2 + 0.5) / (size / 2)
            v = max(0.0, 1.0 - r)
            v = v * v * (3 - 2 * v)  # weich auslaufend
            c = int(255 * v)
            lp[x, y] = (c, c, c, 255)
    save(li, "light.png")


ICON = """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<rect width="128" height="128" rx="24" fill="#1c2540"/>
<g stroke="#e8f2ff" stroke-width="6" stroke-linecap="round">
<path d="M64 24v80M29.4 44l69.2 40M29.4 84l69.2-40"/>
<path d="M54 30l10 8 10-8M54 98l10-8 10 8M26 60l13 0-4-12M102 68l-13 0 4 12M26 68l13 0-4 12M102 60l-13 0 4-12" stroke-width="4"/>
</g>
<circle cx="64" cy="64" r="7" fill="#f4b064"/>
</svg>
"""


if __name__ == "__main__":
    make_ground()
    make_player()
    make_blob()
    make_wisp()
    make_trees()
    make_rock()
    make_mound()
    make_campfire()
    make_small()
    with open(os.path.join(OUT, "..", "icon.svg"), "w", encoding="utf-8") as f:
        f.write(ICON)
    print("Grafiken erzeugt in", OUT)
