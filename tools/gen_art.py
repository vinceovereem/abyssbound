#!/usr/bin/env python3
"""
BocciaBound placeholder art generator.

Every sprite in assets/ is produced by this script. Nothing is hand-painted,
so art is reproducible and reviewable in git as code.

Run:  python3 tools/gen_art.py
Needs: pillow  (pip install pillow)

The palette below is lifted from the BocciaBound concept sheet. Change a hex
value here and every sprite updates together.
"""

import os
import random
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets")

# --------------------------------------------------------------------------
# Palette. One character per colour so sprites can be written as ASCII grids.
# --------------------------------------------------------------------------
PAL = {
    ".": None,                    # transparent
    "K": (11, 15, 22),            # outline, near black
    "k": (26, 34, 48),            # stone darkest
    "g": (42, 54, 72),            # stone mid
    "G": (58, 74, 96),            # stone light
    "m": (86, 106, 132),          # stone highlight
    "S": (232, 185, 138),         # skin
    "s": (196, 146, 104),         # skin shadow
    "H": (74, 55, 40),            # hair
    "h": (52, 38, 28),            # hair dark
    "C": (107, 143, 94),          # shirt
    "c": (72, 102, 64),           # shirt dark
    "P": (61, 74, 92),            # trousers
    "p": (42, 52, 68),            # trousers dark
    "B": (58, 42, 32),            # boots
    "A": (122, 92, 58),           # pack leather
    "W": (232, 236, 240),         # white
    "T": (90, 217, 232),          # teal glow
    "t": (46, 140, 168),          # teal dark
    "V": (178, 95, 214),          # violet
    "v": (110, 58, 150),          # violet dark
    "R": (224, 64, 80),           # heart red
    "r": (150, 36, 52),           # heart dark
    "Y": (240, 192, 74),          # gold
    "F": (138, 143, 150),         # fur
    "f": (90, 96, 104),           # fur dark
    "N": (139, 94, 60),           # hide brown
    "n": (92, 60, 38),            # hide dark
    "O": (217, 79, 42),           # ember orange
}


def grid(rows, name="sprite"):
    """Turn a list of equal-length strings into an RGBA image."""
    w = len(rows[0])
    for i, r in enumerate(rows):
        assert len(r) == w, f"{name}: row {i} is {len(r)} wide, expected {w}"
    img = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            col = PAL[ch]
            if col:
                px[x, y] = (*col, 255)
    return img


def sheet(frames, path):
    """Lay frames out left to right into one strip."""
    w = sum(f.width for f in frames)
    h = max(f.height for f in frames)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x = 0
    for f in frames:
        img.paste(f, (x, 0), f)
        x += f.width
    full = os.path.join(OUT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    img.save(full)
    print(f"  {path}  {img.width}x{img.height}  ({len(frames)} frames)")


# --------------------------------------------------------------------------
# Player. 20x30, about two tiles tall.
#
# Drawn as one base (head, pack, torso, arms) plus a swappable set of legs, so
# a walk cycle is six small grids rather than six whole characters. Feet sit on
# the last drawn row; scenes/actors/player.tscn offsets the sprite so that row
# lands on the collision box's floor.
# --------------------------------------------------------------------------
PLAYER_BASE = [
    "....................",
    "......hhhhhh........",
    ".....hHHHHHHh.......",
    "....hHHHHHHHHh......",
    "....HHHSSSSSHh......",
    "....HSSSSSSSSh......",
    "....HSSKSSSKSh......",
    "....hSSSSSSSSh......",
    ".....sSSSSSSs.......",
    "......sSSSSs........",
    "...AAAcCCCCcAA......",
    "..AAAAcCCCCcAAA.....",
    "..AAAncCCCCCcAA.....",
    "..AAAncCCCCCcAA.....",
    "..AAAncCCCCCcAA.....",
    "...AAncCCCCCcA......",
    "....ScCCCCCCcS......",
    "....SScCCCCcSS......",
    ".....SSpPPPpSS......",
    "......pPPPPPp.......",
]

PLAYER_LEGS = {
    "idle": [
        "......pPPPPPp.......",
        "......PP..PP........",
        "......PP..PP........",
        "......pP..Pp........",
        "......pP..Pp........",
        "......BB..BB........",
        ".....BBBB.BBB.......",
        ".....KKKK.KKK.......",
        "....................",
        "....................",
    ],
    "run_a": [
        "......pPPPPPp.......",
        ".....PPP..PP........",
        "....PPP...PPp.......",
        "...pPP.....Pp.......",
        "...pP......Pp.......",
        "...BB......BB.......",
        "..BBBB....BBBB......",
        "..KKKK....KKKK......",
        "....................",
        "....................",
    ],
    "run_b": [
        "......pPPPPPp.......",
        "......PPP.PPp.......",
        "......PPP..Pp.......",
        ".......PP..Pp.......",
        ".......PP..Pp.......",
        ".......BB..BB.......",
        "......BBBB.BBB......",
        "......KKKK.KKK......",
        "....................",
        "....................",
    ],
    "run_c": [
        "......pPPPPPp.......",
        "......PP..PPP.......",
        "......pP...PPP......",
        "......pP....PPp.....",
        "......pP.....Pp.....",
        "......BB.....BB.....",
        ".....BBBB...BBBB....",
        ".....KKKK...KKKK....",
        "....................",
        "....................",
    ],
    "jump": [
        "......pPPPPPp.......",
        ".....PPP..PPP.......",
        "....PPP....PPP......",
        "...pPP......PPp.....",
        "...BB........BB.....",
        "..BBBB......BBBB....",
        "..KKKK......KKKK....",
        "....................",
        "....................",
        "....................",
    ],
    "fall": [
        "......pPPPPPp.......",
        "......PPP.PPP.......",
        "......PP...PP.......",
        "......pP...Pp.......",
        "......pP...Pp.......",
        "......BB...BB.......",
        ".....BBBB.BBBB......",
        ".....KKKK.KKKK......",
        "....................",
        "....................",
    ],
}


def player_frame(legs_name):
    return grid(PLAYER_BASE + PLAYER_LEGS[legs_name], "player-%s" % legs_name)


def player():
    frames = [
        player_frame("idle"), player_frame("idle"),
        player_frame("run_a"), player_frame("run_b"),
        player_frame("run_c"), player_frame("run_b"),
        player_frame("jump"), player_frame("fall"),
    ]
    sheet(frames, "sprites/player.png")


# --------------------------------------------------------------------------
# Crawler. 24x18. A low, heavy beast: wide silhouette, small eyes, four stumps.
# --------------------------------------------------------------------------
CRAWLER_BODY = [
    "........................",
    "........................",
    ".....KKKK...KKKK........",
    "....KNNNNKKNNNNK........",
    "...KNNNNNNNNNNNNK.......",
    "..KNNNnNNNNNNnNNNK......",
    "..KNNWKNNNNNNKWNNK......",
    "..KNNNNNNNNNNNNNNK......",
    "..KNnNNNNNNNNNNnNK......",
    "..KNNNNNNNNNNNNNNK......",
    "...KNNNNNNNNNNNNK.......",
    "...KNnNNNNNNNNnNK.......",
]

CRAWLER_FEET = {
    "a": [
        "....KNNK...KNNK.........",
        "....KNNK...KNNK.........",
        "....KnnK...KnnK.........",
        "....KKKK...KKKK.........",
        "........................",
        "........................",
    ],
    "b": [
        "...KNNK.....KNNK........",
        "...KNNK.....KNNK........",
        "...KnnK.....KnnK........",
        "...KKKK.....KKKK........",
        "........................",
        "........................",
    ],
}


def crawler():
    sheet([grid(CRAWLER_BODY + CRAWLER_FEET[k], "crawler-%s" % k) for k in ("a", "b")],
          "sprites/crawler.png")


# --------------------------------------------------------------------------
# Critter. 20x16. A wild rabbit: tall ears, round body, nothing threatening.
# --------------------------------------------------------------------------
CRITTER_BODY = [
    "....................",
    ".......FF..FF.......",
    "......FfF..FfF......",
    "......FFF..FFF......",
    "......FFF..FFF......",
    ".....FFFFFFFFF......",
    "....FFFFFFFFFFF.....",
    "...FFKFFFFFFKFF.....",
    "...FFFFFRFFFFFF.....",
    "...FFFFFFFFFFFF.....",
    "...fFFFFFFFFFFf.....",
    "....FFFFFFFFFF......",
]

CRITTER_FEET = {
    "a": [
        ".....FF....FF.......",
        ".....ff....ff.......",
        "....................",
        "....................",
    ],
    "b": [
        "....FF......FF......",
        "....ff......ff......",
        "....................",
        "....................",
    ],
}


def critter():
    sheet([grid(CRITTER_BODY + CRITTER_FEET[k], "critter-%s" % k) for k in ("a", "b")],
          "sprites/critter.png")


def crystal_frames():
    base = [
        "...KK...",
        "..KTTK..",
        "..KTTK..",
        ".KTTTTK.",
        ".KTWTTK.",
        ".KTWTTK.",
        ".KTTTTK.",
        "..KttK..",
        "..KttK..",
        "...KK...",
    ]
    out = []
    for i in range(4):
        rows = list(base)
        if i == 1:
            rows[4] = ".KTTWTK."
        elif i == 2:
            rows[3] = ".KTWTTK."
            rows[4] = ".KTTTTK."
        elif i == 3:
            rows[5] = ".KTTWTK."
        out.append(grid(rows, f"crystal_{i}"))
    return out


def crystal():
    sheet(crystal_frames(), "sprites/crystal.png")


# --------------------------------------------------------------------------
# UI: hearts, 9x8, full then empty.
# --------------------------------------------------------------------------
HEART_FULL = [
    ".KK.KK...",
    "KRRKRRK..",
    "KRWRRRK..",
    "KRRRRRK..",
    ".KRRRK...",
    "..KRK....",
    "...K.....",
    ".........",
]
HEART_EMPTY = [
    ".KK.KK...",
    "KggKggK..",
    "KgggggK..",
    "KgggggK..",
    ".KgggK...",
    "..KgK....",
    "...K.....",
    ".........",
]


def hearts():
    sheet([grid(HEART_FULL, "heart_full"), grid(HEART_EMPTY, "heart_empty")],
          "ui/heart.png")


# --------------------------------------------------------------------------
# Tileset. Six 16x16 tiles in one strip, generated with seeded noise so the
# rock reads as rock rather than flat colour.
# --------------------------------------------------------------------------
def tile_noise(seed, base, light, dark, top_edge=None, accent=None):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    for y in range(16):
        for x in range(16):
            roll = rnd.random()
            col = base
            if roll > 0.86:
                col = light
            elif roll < 0.20:
                col = dark
            px[x, y] = (*col, 255)
    if top_edge:
        for x in range(16):
            px[x, 0] = (*top_edge, 255)
            if rnd.random() > 0.45:
                px[x, 1] = (*top_edge, 255)
            px[x, 2] = (*dark, 255) if rnd.random() > 0.6 else px[x, 2]
    if accent:
        for _ in range(5):
            cx, cy = rnd.randint(3, 12), rnd.randint(4, 12)
            px[cx, cy] = (*accent, 255)
            px[cx, cy - 1] = (*accent, 255)
            if cx + 1 < 16:
                px[cx + 1, cy] = (*PAL["W"], 255)
    return img


def top_edge_overlay():
    """A lit lip for the top of any exposed tile.

    Cheaper than a full 47 piece terrain set and it buys most of the same
    thing: a dug tunnel gets a lit rim instead of reading as a rectangle
    stamped out of flat rock.
    """
    rnd = random.Random(41)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    for x in range(16):
        px[x, 0] = (255, 255, 255, 74)
        px[x, 1] = (255, 255, 255, 40 if rnd.random() > 0.35 else 20)
        px[x, 2] = (255, 255, 255, 14)
    return img


WORKBENCH = [
    "................",
    "................",
    "................",
    "..KKKKKKKKKKKK..",
    "..KAAAAAAAAAAK..",
    "..KAnAAAAAnAAK..",
    "..KKKKKKKKKKKK..",
    "...K.A....A.K...",
    "...K.A....A.K...",
    "...K.A....A.K...",
    "...K.A....A.K...",
    "...K.A....A.K...",
    "...KnA....AnK...",
    "...KKK....KKK...",
    "................",
    "................",
]

FURNACE = [
    "................",
    "..KKKKKKKKKKKK..",
    "..KggggggggggK..",
    "..KgGGGGGGGGgK..",
    "..KgGKKKKKKGgK..",
    "..KgGKOOOOKGgK..",
    "..KgGKOYYOKGgK..",
    "..KgGKOOOOKGgK..",
    "..KgGKKKKKKGgK..",
    "..KgGGGGGGGGgK..",
    "..KggggggggggK..",
    "..KgggggggggGK..",
    "..KKKKKKKKKKKK..",
    "................",
    "................",
    "................",
]

ANVIL = [
    "................",
    "................",
    "................",
    "....KKKKKKKK....",
    "...KmmmmmmmmK...",
    "..KmmmmmmmmmmK..",
    "..KmmGGGGGGmmK..",
    "...KGGGGGGGGK...",
    ".....KGGGGK.....",
    ".....KGGGGK.....",
    "....KGGGGGGK....",
    "...KGGGGGGGGK...",
    "...KKKKKKKKKK...",
    "................",
    "................",
    "................",
]


def water_tile():
    """Translucent so the tiles and walls behind it still read."""
    rnd = random.Random(30)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    for y in range(16):
        for x in range(16):
            col = (40, 100, 175) if rnd.random() > 0.25 else (54, 120, 198)
            px[x, y] = (*col, 210)
    return img


TORCH = [
    "................",
    "................",
    "................",
    "................",
    "......YY........",
    ".....YOOY.......",
    ".....OOOO.......",
    "......OO........",
    "......AA........",
    "......AA........",
    "......AA........",
    "......AA........",
    "......AA........",
    "......AA........",
    "................",
    "................",
]


def tiles():
    """The tile sheet.

    Indices 0 to 5 are the original placeholder zone tiles. They are frozen:
    the archived zones in levels/legacy/ still point at them, so appending is
    safe and renumbering is not. Everything the generated world uses starts at
    index 6.
    """
    stone = ((86, 92, 104), (108, 116, 130), (60, 66, 78))
    t = [
        # -- 0 to 5, the legacy placeholder zone tiles. Do not renumber. ------
        # 0 grass ledge, the surface zone
        tile_noise(1, PAL["g"], PAL["G"], PAL["k"], top_edge=(84, 122, 74)),
        # 1 stone fill
        tile_noise(2, PAL["g"], PAL["G"], PAL["k"]),
        # 2 cavern ledge, lit top edge
        tile_noise(3, PAL["g"], PAL["G"], PAL["k"], top_edge=PAL["m"]),
        # 3 background stone, no collision
        tile_noise(4, (20, 26, 38), (30, 40, 56), (13, 18, 27)),
        # 4 crystal rock
        tile_noise(5, PAL["g"], PAL["G"], PAL["k"], top_edge=PAL["m"], accent=PAL["T"]),
        # 5 hazard, ember rock
        tile_noise(6, (72, 34, 30), (128, 52, 36), (44, 20, 20), top_edge=PAL["O"]),
        # -- 6 onward, the generated world ----------------------------------
        # 6 dirt
        tile_noise(10, (112, 78, 52), (134, 96, 64), (84, 56, 36)),
        # 7 grass, dirt with a living top edge
        tile_noise(11, (112, 78, 52), (134, 96, 64), (84, 56, 36), top_edge=(96, 152, 72)),
        # 8 stone
        tile_noise(12, *stone),
        # 9 sand
        tile_noise(13, (214, 190, 132), (232, 212, 158), (176, 152, 100)),
        # 10 snow
        tile_noise(14, (222, 232, 242), (240, 248, 255), (186, 200, 216)),
        # 11 wood
        tile_noise(15, (120, 86, 50), (146, 108, 66), (88, 62, 36)),
        # 12 leaves
        tile_noise(16, (66, 122, 62), (88, 150, 78), (44, 90, 46)),
        # 13 copper ore
        tile_noise(17, *stone, accent=(198, 118, 62)),
        # 14 iron ore
        tile_noise(18, *stone, accent=(190, 194, 200)),
        # 15 ice
        tile_noise(19, (160, 204, 228), (196, 230, 246), (120, 168, 200)),
        # 16 abyss stone
        tile_noise(20, (48, 38, 66), (68, 54, 92), (30, 24, 44)),
        # 17 torch, the first light source
        grid(TORCH, "torch"),
        # 18 glowstone
        tile_noise(22, (58, 74, 96), (86, 106, 132), (42, 54, 72), accent=(140, 230, 240)),
        # 19 dirt wall, background only
        tile_noise(23, (74, 54, 40), (92, 68, 50), (54, 38, 28)),
        # 20 stone wall, background only
        tile_noise(24, (62, 68, 82), (78, 86, 102), (44, 48, 60)),
        # 21 water. Translucent, drawn on its own layer over everything else.
        water_tile(),
        # 22 top edge highlight, drawn over any solid tile with air above it.
        top_edge_overlay(),
        # 23 tree trunk. Looks like wood, but you walk through it the way you
        # walk through a tree in Terraria. Wood the building block stays solid.
        tile_noise(15, (120, 86, 50), (146, 108, 66), (88, 62, 36)),
        # 24 to 26, the crafting stations. Furniture: drawn, walked through.
        grid(WORKBENCH, "workbench"),
        grid(FURNACE, "furnace"),
        grid(ANVIL, "anvil"),
        # 27 to 29: what you find in a cave rather than make.
        grid(CHEST, "chest"),
        grid(CHEST_OPEN, "chest_open"),
        grid(LIFE_CRYSTAL, "life_crystal"),
    ]
    sheet(t, "tiles/tiles.png")


# --------------------------------------------------------------------------
# Parallax backdrops, one per zone. 320x180, vertical gradient plus silhouettes.
# --------------------------------------------------------------------------
def backdrop(name, top, bottom, silhouette, seed, glow=None):
    w, h = 320, 180
    img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    px = img.load()
    for y in range(h):
        f = y / (h - 1)
        col = tuple(int(top[i] + (bottom[i] - top[i]) * f) for i in range(3))
        for x in range(w):
            px[x, y] = (*col, 255)

    rnd = random.Random(seed)
    if glow:
        for _ in range(40):
            gx, gy = rnd.randint(0, w - 1), rnd.randint(0, h - 1)
            px[gx, gy] = (*glow, 255)

    # jagged silhouette across the lower half
    y_cur = int(h * 0.55)
    for x in range(w):
        y_cur += rnd.choice([-2, -1, 0, 0, 1, 2])
        y_cur = max(int(h * 0.35), min(int(h * 0.8), y_cur))
        for y in range(y_cur, h):
            px[x, y] = (*silhouette, 255)

    full = os.path.join(OUT, "bg", f"{name}.png")
    os.makedirs(os.path.dirname(full), exist_ok=True)
    img.save(full)
    print(f"  bg/{name}.png  {w}x{h}")


def backdrops():
    backdrop("bg_surface", (96, 148, 176), (188, 208, 196), (32, 46, 44), 11)
    backdrop("bg_caverns", (14, 22, 34), (24, 40, 56), (10, 16, 26), 12, glow=PAL["t"])
    backdrop("bg_abyss", (28, 12, 44), (58, 22, 82), (14, 8, 24), 13, glow=PAL["V"])


# --------------------------------------------------------------------------
# Project icon.
# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
# Item icons. 16x16, one row, in the order listed in ICONS below.
#
# Tools and bars are the same shape in four metals, so the grids use "X" as a
# stand-in that gets painted the tier colour. One drawing, four items.
# --------------------------------------------------------------------------
PICK = [
    "................",
    "....XXX....XXX..",
    "...XXXXXXXXXXX..",
    "...XXXXXXXXXXX..",
    "....XXXXXXXXX...",
    ".......AA.......",
    ".......AA.......",
    ".......AA.......",
    ".......AA.......",
    ".......AA.......",
    ".......AA.......",
    ".......AA.......",
    ".......nn.......",
    "................",
    "................",
    "................",
]

SWORD = [
    "............XX..",
    "...........XXX..",
    "..........XXX...",
    ".........XXX....",
    "........XXX.....",
    ".......XXX......",
    "......XXX.......",
    ".....XXX........",
    "....XXX.........",
    "...AAAAA........",
    "....nn..........",
    "...nnn..........",
    "...nn...........",
    "................",
    "................",
    "................",
]

ORE = [
    "................",
    "................",
    "....gggg........",
    "...ggXXgg.......",
    "..ggXXXXgg......",
    "..gXXggXXg......",
    "..ggXXggXg......",
    "...gXXggg.......",
    "....gggg........",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
]

BAR = [
    "................",
    "................",
    "................",
    ".....XXXXXX.....",
    "....XXXXXXXX....",
    "...XXXXXXXXXX...",
    "...XXXXXXXXXX...",
    "....XXXXXXXX....",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
]

HIDE = [
    "................",
    "................",
    "...KK......KK...",
    "..KNNK....KNNK..",
    "..KNNNKKKKNNNK..",
    "..KNNNNNNNNNNK..",
    "..KNNNNNNNNNNK..",
    "...KNNNNNNNNK...",
    "...KNNNNNNNNK...",
    "....KNNNNNNK....",
    "....KNNKKNNK....",
    ".....KK..KK.....",
    "................",
    "................",
    "................",
    "................",
]

HELM = [
    "................",
    "................",
    "....KKKKKK......",
    "...KXXXXXXK.....",
    "..KXXXXXXXXK....",
    "..KXXKKKKXXK....",
    "..KXX....XXK....",
    "..KXX....XXK....",
    "..KXK....KXK....",
    "..KK......KK....",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
]

MAIL = [
    "................",
    "..KK........KK..",
    "..KXKKKKKKKKXK..",
    "..KXXXXXXXXXXK..",
    "..KXXXXXXXXXXK..",
    "...KXXXXXXXXK...",
    "...KXXXXXXXXK...",
    "...KXXXXXXXXK...",
    "...KXXXXXXXXK...",
    "...KXXXXXXXXK...",
    "....KXXXXXXK....",
    "....KKKKKKKK....",
    "................",
    "................",
    "................",
    "................",
]

GREAVES = [
    "................",
    "...KKKKKKKKKK...",
    "...KXXXXXXXXK...",
    "...KXXXXXXXXK...",
    "...KXXXXXXXXK...",
    "...KXXKKKKXXK...",
    "...KXXK..KXXK...",
    "...KXXK..KXXK...",
    "...KXXK..KXXK...",
    "...KXXK..KXXK...",
    "...KKK....KKK...",
    "................",
    "................",
    "................",
    "................",
    "................",
]

CHEST = [
    "................",
    "................",
    "..KKKKKKKKKKKK..",
    "..KAAAAAAAAAAK..",
    "..KAnnnnnnnnAK..",
    "..KKKKKKKKKKKK..",
    "..KAAAAYYAAAAK..",
    "..KAAAAYYAAAAK..",
    "..KAnAAAAAAnAK..",
    "..KAnAAAAAAnAK..",
    "..KAAAAAAAAAAK..",
    "..KKKKKKKKKKKK..",
    "................",
    "................",
    "................",
    "................",
]

CHEST_OPEN = [
    "................",
    "..KKKKKKKKKKKK..",
    "..KAnnnnnnnnAK..",
    "..KKKKKKKKKKKK..",
    "................",
    "..KKKKKKKKKKKK..",
    "..KkkkkkkkkkK...",
    "..KkkkkkkkkkK...",
    "..KAnAAAAAAnAK..",
    "..KAnAAAAAAnAK..",
    "..KAAAAAAAAAAK..",
    "..KKKKKKKKKKKK..",
    "................",
    "................",
    "................",
    "................",
]

LIFE_CRYSTAL = [
    "................",
    "................",
    ".......KK.......",
    "......KRRK......",
    ".....KRRRRK.....",
    "....KRRWWRRK....",
    "....KRRWWRRK....",
    ".....KRRRRK.....",
    ".....KRRRRK.....",
    "......KRRK......",
    ".......KK.......",
    "................",
    "................",
    "................",
    "................",
    "................",
]

TIER = {
    "wood": (146, 108, 66),
    "stone": (108, 116, 130),
    "copper": (198, 118, 62),
    "iron": (190, 194, 200),
}

# Order matters: it is the "icon" index in data/items.json.
ICONS = [
    ("copper_ore", ORE, "copper"),
    ("iron_ore", ORE, "iron"),
    ("copper_bar", BAR, "copper"),
    ("iron_bar", BAR, "iron"),
    ("wood_pick", PICK, "wood"),
    ("stone_pick", PICK, "stone"),
    ("copper_pick", PICK, "copper"),
    ("iron_pick", PICK, "iron"),
    ("wood_sword", SWORD, "wood"),
    ("copper_sword", SWORD, "copper"),
    ("iron_sword", SWORD, "iron"),
    ("hide", HIDE, "wood"),
    ("copper_helm", HELM, "copper"),
    ("copper_mail", MAIL, "copper"),
    ("copper_greaves", GREAVES, "copper"),
    ("iron_helm", HELM, "iron"),
    ("iron_mail", MAIL, "iron"),
    ("iron_greaves", GREAVES, "iron"),
]


def tinted(rows, colour, name):
    """Like grid(), but "X" means "paint this the tier colour"."""
    img = Image.new("RGBA", (len(rows[0]), len(rows)), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        assert len(row) == 16, f"{name}: row {y} is {len(row)} wide"
        for x, ch in enumerate(row):
            if ch == "X":
                px[x, y] = (*colour, 255)
            elif PAL[ch]:
                px[x, y] = (*PAL[ch], 255)
    return img


def items():
    frames = [tinted(rows, TIER[tier], name) for name, rows, tier in ICONS]
    sheet(frames, "sprites/items.png")


def icon():
    img = Image.new("RGBA", (64, 64), (13, 20, 32, 255))
    px = img.load()
    for y in range(64):
        for x in range(64):
            d = abs(x - 32) + abs(y - 34)
            if d < 20:
                shade = int(90 + (20 - d) * 6)
                px[x, y] = (min(shade, 90), min(shade + 60, 217), min(shade + 80, 232), 255)
            if d < 8:
                px[x, y] = (232, 236, 240, 255)
    img.save(os.path.join(OUT, "..", "icon.png"))
    print("  icon.png  64x64")


if __name__ == "__main__":
    print("Generating BocciaBound placeholder art...")
    player()
    crawler()
    critter()
    crystal()
    hearts()
    tiles()
    items()
    backdrops()
    icon()
    print("Done.")
