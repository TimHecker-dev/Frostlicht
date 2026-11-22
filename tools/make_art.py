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



# ---------------------------------------------------------------- Neue Gegner, Boss und Frosthöhle
FUR_W, FUR_S = (236, 243, 252, 255), (198, 214, 238, 255)
DARK = (36, 32, 56, 255)


def make_fox():
    """Frostfuchs (schaut nach rechts)."""
    img, d = new(30, 24)
    d.ellipse([1, 8, 12, 19], fill=(232, 240, 252, 255))
    d.ellipse([1, 11, 6, 19], fill=(150, 192, 236, 255))
    for x in (10, 14, 19, 23):
        d.rectangle([x, 17, x + 2, 21], fill=(214, 226, 244, 255))
        d.rectangle([x, 20, x + 2, 21], fill=(96, 118, 160, 255))
    d.ellipse([8, 9, 24, 20], fill=FUR_W)
    d.ellipse([9, 14, 24, 20], fill=FUR_S)
    d.ellipse([9, 9, 22, 15], fill=FUR_W)
    d.ellipse([19, 5, 28, 15], fill=FUR_W)
    d.polygon([(26, 9), (29, 12), (26, 14)], fill=FUR_W)
    d.polygon([(20, 7), (21, 1), (24, 6)], fill=FUR_W)
    d.polygon([(24, 6), (26, 1), (28, 7)], fill=FUR_W)
    d.polygon([(21, 6), (21, 3), (23, 6)], fill=(120, 142, 190, 255))
    d.polygon([(25, 6), (26, 3), (27, 7)], fill=(120, 142, 190, 255))
    d.rectangle([28, 11, 29, 12], fill=DARK)
    d.rectangle([25, 9, 25, 10], fill=DARK)
    d.point([24, 12], fill=(250, 200, 200, 255))
    save(outline(img), "enemy_fox.png")


def make_snowman():
    img, d = new(24, 36)
    d.ellipse([3, 20, 20, 33], fill=FUR_S)
    d.ellipse([3, 20, 17, 31], fill=FUR_W)
    d.ellipse([6, 11, 17, 23], fill=FUR_S)
    d.ellipse([6, 11, 15, 21], fill=FUR_W)
    d.ellipse([7, 3, 16, 13], fill=FUR_S)
    d.ellipse([7, 3, 14, 11], fill=FUR_W)
    br = (104, 74, 58, 255)
    for pts in (([6, 15], [1, 11]), ([3, 12], [1, 9]), ([4, 13], [0, 13]), ([17, 15], [22, 10]), ([20, 11], [22, 8]), ([19, 12], [23, 12])):
        d.line([pts[0][0], pts[0][1], pts[1][0], pts[1][1]], fill=br)
    d.rectangle([7, 12, 16, 14], fill=(86, 170, 130, 255))
    d.rectangle([14, 14, 16, 18], fill=(70, 146, 112, 255))
    d.rectangle([8, 0, 15, 3], fill=(62, 58, 86, 255))
    d.rectangle([6, 3, 17, 4], fill=(52, 48, 74, 255))
    d.point([10, 7], fill=DARK)
    d.point([13, 7], fill=DARK)
    d.polygon([(11, 8), (17, 9), (11, 10)], fill=(240, 140, 50, 255))
    for y in (17, 20):
        d.point([11, y], fill=DARK)
    save(outline(img), "enemy_snowman.png")


def hedgehog_frame(ball):
    img, d = new(28, 24)
    ice, ice_d, crystal = (150, 192, 228, 255), (112, 152, 204, 255), (214, 238, 252, 255)
    if not ball:
        cx, cy = 13, 14
        for i in range(10):
            a = math.radians(175 + i * 19)
            b1 = (cx + 9 * math.cos(a - 0.2), cy + 6 * math.sin(a - 0.2))
            b2 = (cx + 9 * math.cos(a + 0.2), cy + 6 * math.sin(a + 0.2))
            tip = (cx + 14.5 * math.cos(a), cy + 11 * math.sin(a))
            d.polygon([b1, tip, b2], fill=crystal)
        d.ellipse([3, 8, 23, 20], fill=ice)
        d.ellipse([4, 14, 23, 20], fill=ice_d)
        d.ellipse([4, 8, 20, 16], fill=ice)
        d.ellipse([18, 12, 26, 21], fill=(226, 238, 250, 255))
        d.rectangle([25, 16, 26, 17], fill=DARK)
        d.rectangle([22, 14, 22, 15], fill=DARK)
        for x in (8, 15):
            d.rectangle([x, 19, x + 2, 22], fill=(96, 118, 160, 255))
    else:
        cx, cy = 14, 12
        for i in range(14):
            a = math.radians(i * 360 / 14)
            b1 = (cx + 8 * math.cos(a - 0.22), cy + 8 * math.sin(a - 0.22))
            b2 = (cx + 8 * math.cos(a + 0.22), cy + 8 * math.sin(a + 0.22))
            d.polygon([b1, (cx + 13 * math.cos(a), cy + 12.5 * math.sin(a)), b2], fill=crystal)
        d.ellipse([5, 3, 23, 21], fill=ice)
        d.ellipse([6, 11, 23, 21], fill=ice_d)
        d.ellipse([7, 5, 16, 11], fill=(190, 222, 244, 255))
    return outline(img)


def make_hedgehog():
    sheet = Image.new("RGBA", (56, 24), CLEAR)
    sheet.paste(hedgehog_frame(False), (0, 0))
    sheet.paste(hedgehog_frame(True), (28, 0))
    save(sheet, "enemy_hedgehog.png")


def make_projectiles():
    img, d = new(11, 11)
    d.ellipse([1, 1, 9, 9], fill=FUR_S)
    d.ellipse([1, 1, 7, 7], fill=FUR_W)
    save(outline(img), "snowball.png")
    img, d = new(10, 16)
    d.polygon([(5, 0), (8, 6), (5, 14), (2, 6)], fill=(140, 214, 246, 255))
    d.polygon([(5, 0), (2, 6), (5, 14)], fill=(214, 244, 255, 255))
    save(outline(img), "shard.png")


BEAR, BEAR_D, BEAR_L, BELLY = (112, 88, 84, 255), (80, 62, 64, 255), (148, 120, 108, 255), (170, 142, 126, 255)
FROST, FROST_D = (224, 238, 252, 255), (172, 202, 232, 255)
CRY, CRY_D, CRY_L = (130, 226, 250, 255), (70, 170, 214, 255), (210, 248, 255, 255)


def boss_frame(pose):
    """Der Winterschläfer (schaut nach rechts). pose 0 = Stehen/Gehen, 1 = Pranke erhoben, 2 = Brüllen/Sprung."""
    img, d = new(64, 60)
    hy = 4 if pose == 2 else 0
    d.ellipse([8, 40, 23, 57], fill=BEAR_D)
    d.ellipse([8, 52, 23, 58], fill=(60, 46, 50, 255))
    d.ellipse([20, 42, 33, 57], fill=BEAR_D)
    d.ellipse([6, 17, 47, 54], fill=BEAR_D)
    d.ellipse([6, 15, 46, 48], fill=BEAR)
    d.ellipse([10, 18, 38, 36], fill=BEAR_L)
    d.ellipse([14, 36, 38, 52], fill=BELLY)
    d.ellipse([12, 15, 30, 25], fill=FROST)
    d.ellipse([26, 17, 42, 26], fill=FROST_D)
    for (x0, top, x1) in ((12, 7, 19), (21, 3, 29), (31, 8, 38)):
        d.polygon([(x0, 19), ((x0 + x1) // 2, top), (x1, 19)], fill=CRY)
        d.polygon([(x0, 19), ((x0 + x1) // 2, top), ((x0 + x1) // 2, 19)], fill=CRY_L)
    if pose == 1:
        d.line([40, 34, 55, 16], fill=BEAR, width=10)
        d.ellipse([30, 40, 44, 57], fill=BEAR)
    elif pose == 2:
        d.line([40, 36, 52, 24], fill=BEAR, width=9)
        d.ellipse([47, 19, 58, 30], fill=BEAR_D)
        d.ellipse([28, 40, 42, 57], fill=BEAR)
    else:
        d.ellipse([36, 38, 50, 58], fill=BEAR)
        d.ellipse([36, 51, 50, 58], fill=BEAR_D)
        d.ellipse([27, 40, 41, 57], fill=BEAR)
    d.ellipse([39, 8 - hy, 61, 33 - hy], fill=BEAR)
    d.ellipse([39, 7 - hy, 49, 15 - hy], fill=BEAR_D)
    d.ellipse([40, 5 - hy, 47, 12 - hy], fill=BEAR_D)
    d.ellipse([52, 5 - hy, 59, 12 - hy], fill=BEAR_D)
    d.ellipse([41, 7 - hy, 45, 10 - hy], fill=(190, 140, 130, 255))
    d.ellipse([53, 7 - hy, 57, 10 - hy], fill=(190, 140, 130, 255))
    d.ellipse([50, 19 - hy, 64, 32 - hy], fill=BEAR_L)
    d.ellipse([60, 21 - hy, 64, 26 - hy], fill=DARK)
    d.rectangle([49, 16 - hy, 52, 19 - hy], fill=DARK)
    d.point([49, 16 - hy], fill=(255, 255, 255, 255))
    d.line([45, 13 - hy, 53, 16 - hy], fill=BEAR_D, width=2)
    d.ellipse([41, 14 - hy, 46, 19 - hy], fill=FROST_D)
    if pose == 1:                                                      # erhobene Pranke vor dem Kopf
        d.ellipse([49, 0, 63, 16], fill=BEAR_D)
        d.ellipse([51, 1, 61, 9], fill=BEAR)
        for x in (51, 55, 59):
            d.polygon([(x, 3), (x + 1, 0), (x + 2, 3)], fill=(240, 234, 226, 255))
    if pose == 2:
        d.polygon([(53, 27 - hy), (64, 25 - hy), (61, 36 - hy), (53, 33 - hy)], fill=(122, 42, 62, 255))
        d.polygon([(55, 27 - hy), (57, 31 - hy), (59, 26 - hy)], fill=(244, 240, 232, 255))
    else:
        d.line([54, 29 - hy, 62, 28 - hy], fill=DARK, width=1)
    return outline(img)


def make_boss():
    sheet = Image.new("RGBA", (192, 60), CLEAR)
    for i in range(3):
        sheet.paste(boss_frame(i), (i * 64, 0))
    save(sheet, "boss.png")
    img, d = new(64, 42)
    d.ellipse([3, 12, 59, 38], fill=BEAR_D)
    d.ellipse([3, 9, 57, 33], fill=BEAR)
    d.ellipse([8, 11, 40, 24], fill=BEAR_L)
    d.ellipse([10, 5, 40, 17], fill=FROST)
    d.ellipse([22, 8, 48, 18], fill=FROST_D)
    for (x0, top, x1) in ((14, -1, 21), (24, -3, 31), (34, 0, 41)):
        d.polygon([(x0, 11), ((x0 + x1) // 2, max(0, top + 3)), (x1, 11)], fill=CRY)
    d.ellipse([40, 18, 61, 38], fill=BEAR)
    d.ellipse([41, 14, 49, 22], fill=BEAR_D)
    d.ellipse([52, 15, 59, 22], fill=BEAR_D)
    d.ellipse([52, 26, 63, 37], fill=BEAR_L)
    d.ellipse([59, 28, 63, 32], fill=DARK)
    d.line([47, 26, 51, 27], fill=DARK, width=1)
    d.ellipse([14, 30, 34, 40], fill=BEAR_D)
    save(outline(img), "boss_sleep.png")


def make_ice_ground(size=256):
    rnd = random.Random(23)
    levels = [(186, 216, 236), (192, 222, 240), (199, 228, 244), (208, 234, 248)]
    g = 14
    small = Image.new("L", (g, g))
    small.putdata([rnd.randrange(256) for _ in range(g * g)])
    tiled = Image.new("L", (g * 3, g * 3))
    for ox in range(3):
        for oy in range(3):
            tiled.paste(small, (ox * g, oy * g))
    big = ImageOps.autocontrast(tiled.resize((size * 3, size * 3), Image.BICUBIC).crop((size, size, size * 2, size * 2)))
    img = Image.new("RGBA", (size, size))
    px, ip = big.load(), img.load()
    for y in range(size):
        for x in range(size):
            ip[x, y] = levels[min(3, px[x, y] * 4 // 256)] + (255,)
    d = ImageDraw.Draw(img)

    def wrapped_line(pts, col):
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                d.line([(x + ox, y + oy) for x, y in pts], fill=col, width=1)

    for _ in range(16):
        x, y = rnd.randrange(size), rnd.randrange(size)
        pts = [(x, y)]
        ang = rnd.uniform(0, 6.28)
        for _ in range(rnd.randint(4, 9)):
            ang += rnd.uniform(-0.7, 0.7)
            x += math.cos(ang) * rnd.randint(6, 14)
            y += math.sin(ang) * rnd.randint(6, 14)
            pts.append((x, y))
        wrapped_line(pts, (146, 184, 214, 255))
        wrapped_line([(px_ + 1, py_ + 1) for px_, py_ in pts], (226, 244, 252, 255))
    for _ in range(40):
        x, y = rnd.randrange(size), rnd.randrange(size)
        ln = rnd.randint(4, 12)
        wrapped_line([(x, y), (x + ln, y - ln // 3)], (240, 250, 255, 255))
    for _ in range(70):
        ip[rnd.randrange(size), rnd.randrange(size)] = (255, 255, 255, 255)
    save(img, "ice.png")


def make_crystals():
    img, d = new(24, 46)
    d.polygon([(12, 0), (19, 11), (17, 42), (7, 42), (5, 11)], fill=(100, 190, 230, 255))
    d.polygon([(12, 0), (5, 11), (7, 42), (12, 38)], fill=(190, 242, 254, 255))
    d.polygon([(12, 0), (19, 11), (17, 42), (12, 38)], fill=(58, 128, 188, 255))
    d.polygon([(3, 26), (0, 38), (6, 38)], fill=(120, 205, 238, 255))
    d.polygon([(21, 30), (23, 40), (17, 40)], fill=(80, 160, 210, 255))
    d.line([12, 6, 12, 34], fill=(230, 252, 255, 255), width=1)
    save(outline(img), "crystal_a.png")
    img, d = new(34, 30)
    for (x0, x1, top, col) in ((2, 11, 12, (90, 176, 220, 255)), (11, 22, 2, (110, 200, 236, 255)), (22, 32, 10, (74, 150, 204, 255))):
        d.polygon([(x0, 27), ((x0 + x1) // 2, top), (x1, 27)], fill=col)
        d.polygon([(x0, 27), ((x0 + x1) // 2, top), ((x0 + x1) // 2, 27)], fill=(200, 246, 255, 255))
    save(outline(img), "crystal_b.png")
    img, d = new(30, 22)
    d.polygon([(2, 18), (4, 9), (11, 3), (20, 3), (27, 10), (28, 18), (15, 20)], fill=(78, 92, 124, 255))
    d.polygon([(15, 20), (28, 18), (27, 10), (20, 3), (17, 11)], fill=(56, 68, 100, 255))
    d.polygon([(4, 9), (11, 3), (20, 3), (24, 8), (14, 9)], fill=(214, 236, 252, 255))
    save(outline(img), "ice_rock.png")


def make_cave():
    img, d = new(58, 54)
    d.polygon([(2, 52), (2, 24), (9, 9), (29, 2), (49, 9), (56, 24), (56, 52)], fill=(92, 102, 130, 255))
    d.polygon([(29, 2), (49, 9), (56, 24), (56, 52), (44, 52), (44, 22), (36, 10)], fill=(70, 80, 108, 255))
    rnd = random.Random(5)
    for _ in range(16):
        x, y = rnd.randint(3, 50), rnd.randint(10, 48)
        d.rectangle([x, y, x + rnd.randint(4, 8), y], fill=(64, 72, 98, 255))
    d.ellipse([12, 16, 46, 52], fill=(40, 120, 180, 255))
    d.ellipse([16, 21, 42, 52], fill=(70, 170, 220, 255))
    d.ellipse([21, 27, 37, 52], fill=(150, 226, 248, 255))
    d.ellipse([25, 33, 33, 52], fill=(226, 252, 255, 255))
    d.polygon([(7, 11), (29, 3), (51, 11), (42, 10), (29, 6), (16, 10)], fill=(248, 251, 255, 255))
    for x, ln in ((16, 9), (23, 6), (34, 8), (40, 5)):
        d.polygon([(x, 19), (x + 2, 19 + ln), (x + 4, 19)], fill=(224, 246, 255, 255))
    save(outline(img), "cave.png")


def make_sign():
    img, d = new(22, 32)
    d.rectangle([10, 12, 12, 29], fill=(104, 74, 58, 255))
    d.polygon([(11, 1), (19, 9), (14, 9), (14, 15), (8, 15), (8, 9), (3, 9)], fill=(172, 126, 84, 255))
    d.polygon([(11, 1), (19, 9), (14, 9), (14, 15), (11, 15)], fill=(140, 100, 68, 255))
    d.line([11, 7, 11, 12], fill=(200, 240, 255, 255))
    d.line([9, 9, 13, 10], fill=(200, 240, 255, 255))
    d.line([13, 9, 9, 10], fill=(200, 240, 255, 255))
    d.ellipse([6, 0, 16, 3], fill=(248, 251, 255, 255))
    save(outline(img), "sign.png")


def make_new():
    make_fox()
    make_snowman()
    make_hedgehog()
    make_projectiles()
    make_boss()
    make_ice_ground()
    make_crystals()
    make_cave()
    make_sign()


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
    make_new()
    with open(os.path.join(OUT, "..", "icon.svg"), "w", encoding="utf-8") as f:
        f.write(ICON)
    print("Grafiken erzeugt in", OUT)
