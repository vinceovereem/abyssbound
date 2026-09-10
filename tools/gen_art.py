#!/usr/bin/env python3
"""
Abyssbound placeholder art generator.

Every sprite in assets/ is produced by this script. Nothing is hand-painted,
so art is reproducible and reviewable in git as code.

Run:  python3 tools/gen_art.py
Needs: pillow  (pip install pillow)

The palette below is lifted from the Abyssbound concept sheet. Change a hex
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
# Player. 12x16. Torso is shared, legs swap per frame.
# --------------------------------------------------------------------------
TORSO = [
    "...111111...".replace("1", "K"),
    "..KHHHHHHK..",
    "..KHhhhhHK..",
    "..KHSSSSHK..",
    "..KSKSSKSK..",
    "..KSSssSSK..",
    "...KSSSSK...",
    ".KCCCCCCCCK.",
    ".KSCCCCCCSK.",
    ".KSCCAACCSK.",
    ".KScCCCCcSK.",
    "..KcCCCCcK..",
]

LEGS = {
    "idle": [
        "..KPPPPPPK..",
        "..KPPPPPPK..",
        "..KPPKKPPK..",
        "..KBB..BBK..",
    ],
    "run_a": [
        "..KPPPPPPK..",
        ".KPPPKPPPK..",
        ".KPPK..KppK.",
        ".BBK....KBB.",
    ],
    "run_b": [
        "..KPPPPPPK..",
        "..KPPPPPPK..",
        "..KPPKKPPK..",
        "..KBBKKBBK..",
    ],
    "run_c": [
        "..KPPPPPPK..",
        "..KPPPKPPPK.",
        ".KppK..KPPK.",
        ".BBK....KBB.",
    ],
    "jump": [
        "..KPPPPPPK..",
        ".KPPPKKPPK..",
        ".KBBK..KppK.",
        "..BK....KB..",
    ],
    "fall": [
        "..KPPPPPPK..",
        "..KPPPPPPK..",
        ".KPPK..KPPK.",
        ".KBBK..KBBK.",
    ],
}

# Arms raised while airborne, so the jump reads at 16 pixels tall.
TORSO_AIR = list(TORSO)
TORSO_AIR[8] = ".SKCCCCCCKS."
TORSO_AIR[9] = ".SKCCAACCKS."


def player():
    frames = []
    order = ["idle", "idle", "run_a", "run_b", "run_c", "run_b", "jump", "fall"]
    for i, key in enumerate(order):
        torso = TORSO_AIR if key in ("jump", "fall") else TORSO
        rows = list(torso) + LEGS[key]
        f = grid(rows, f"player[{key}]")
        # 1px idle bob on the second idle frame
        if i == 1:
            bob = Image.new("RGBA", (12, 16), (0, 0, 0, 0))
            bob.paste(f.crop((0, 0, 12, 15)), (0, 1), f.crop((0, 0, 12, 15)))
            f = bob
        frames.append(f)
    sheet(frames, "sprites/player.png")


# --------------------------------------------------------------------------
# Crawler. The hostile one. 16x12.
# --------------------------------------------------------------------------
CRAWLER_A = [
    ".....KKKKKK.....",
    "...KKnnnnnnKK...",
    "..KnnNNNNNNnnK..",
    ".KnNNNNNNNNNNnK.",
    ".KNNKWKNNKWKNNK.",
    ".KNNNNNNNNNNNNK.",
    ".KNnNNNNNNNNnNK.",
    "..KNNNNNNNNNNK..",
    "..KKnnnnnnnnKK..",
    "...KWKKWWKKWK...",
    "..KK..KK..KK....",
    "................",
]
CRAWLER_B = [
    "................",
    ".....KKKKKK.....",
    "...KKnnnnnnKK...",
    "..KnnNNNNNNnnK..",
    ".KnNNNNNNNNNNnK.",
    ".KNNKWKNNKWKNNK.",
    ".KNNNNNNNNNNNNK.",
    ".KNnNNNNNNNNnNK.",
    "..KNNNNNNNNNNK..",
    "..KKnnnnnnnnKK..",
    "...KWKKWWKKWK...",
    "....KK..KK..KK..",
]


def crawler():
    sheet([grid(CRAWLER_A, "crawler_a"), grid(CRAWLER_B, "crawler_b")],
          "sprites/crawler.png")


# --------------------------------------------------------------------------
# Critter. The tameable one, a wolf pup. 16x12.
# --------------------------------------------------------------------------
CRITTER_A = [
    "...KK.......KK..",
    "..KFFK.....KFFK.",
    "..KFFFKKKKKFFFK.",
    "...KFFFFFFFFFFK.",
    "..KFFKWKFFKWKFK.",
    ".KFFFFFFFFFFFFK.",
    ".KFffFFFFFFffFK.",
    ".KFFFFFFFFFFFFKK",
    "..KffFFFFFFffK.f",
    "..KFK.KFFK.KFK.f",
    "..KKK.KKKK.KKK..",
    "................",
]
CRITTER_B = [
    "................",
    "...KK.......KK..",
    "..KFFK.....KFFK.",
    "..KFFFKKKKKFFFK.",
    "...KFFFFFFFFFFK.",
    "..KFFKWKFFKWKFK.",
    ".KFFFFFFFFFFFFKf",
    ".KFffFFFFFFffFKf",
    ".KFFFFFFFFFFFFK.",
    "..KffFFFFFFffK..",
    "...KFK.KFFK.KFK.",
    "...KKK.KKKK.KKK.",
]


def critter():
    sheet([grid(CRITTER_A, "critter_a"), grid(CRITTER_B, "critter_b")],
          "sprites/critter.png")


# --------------------------------------------------------------------------
# Crystal pickup. 8x10, four frames of sparkle.
# --------------------------------------------------------------------------
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


def tiles():
    t = [
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
    print("Generating Abyssbound placeholder art...")
    player()
    crawler()
    critter()
    crystal()
    hearts()
    tiles()
    backdrops()
    icon()
    print("Done.")
