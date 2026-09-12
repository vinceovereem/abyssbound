#!/usr/bin/env python3
"""
BocciaBound level generator.

Writes the plain text maps in levels/. The maps are committed, so you can edit
them by hand in any text editor. This script is here for rebuilding a zone or
adding a new one, and it checks that the result is actually playable.

Run:  python3 tools/gen_levels.py

Legend
  #  ground top          1  solid fill           =  one-way platform
  :  background stone    *  crystal rock         ^  ember rock (hurts)
  .  empty               @  player spawn         c  crystal
  x  crawler             w  critter              v  descent to next zone

Reachability, measured against the values in scripts/player.gd:
  jump peak   ~59 px  ->  3.7 tiles
  jump reach  ~70 px  ->  4.4 tiles
So: nothing you must stand on sits more than 3 tiles above the floor, and no
pit is wider than 3 tiles. verify() enforces both, so a level that would trap
the player fails the build instead of shipping.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The three placeholder zones are archived. They are not the game any more,
# but they still load, so the checks that cover them stay honest.
OUT = os.path.join(ROOT, "levels", "legacy")

MAX_PIT = 3          # tiles
MAX_CLIMB = 3        # tiles

SOLID = set("#1*^")


class Map:
    def __init__(self, width, height, header):
        self.w, self.h = width, height
        self.header = header
        self.g = [["." for _ in range(width)] for _ in range(height)]
        self.surfaces = []      # (x0, x1, top_y) of every walkable run

    # -- drawing ----------------------------------------------------------
    def put(self, x, y, ch):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = ch

    def row(self, y, x0, x1, ch):
        for x in range(x0, x1):
            self.put(x, y, ch)

    def rect(self, x0, y0, x1, y1, ch):
        for y in range(y0, y1):
            self.row(y, x0, x1, ch)

    def ledge(self, x0, x1, top):
        """Walkable ground from `top` down to the bottom of the map."""
        self.row(top, x0, x1, "#")
        self.rect(x0, top + 1, x1, self.h, "1")
        self.surfaces.append((x0, x1, top))

    def shaft(self, x0, x1, ceiling=False):
        """An open drop. Falling in costs a heart and puts you back at spawn."""
        self.rect(x0, 1, x1, self.h, ":")
        if ceiling:
            self.row(0, x0, x1, "1")

    def platform(self, x0, length, y):
        self.row(y, x0, x0 + length, "=")
        self.surfaces.append((x0, x0 + length, y))

    def embers(self, x0, x1, top):
        self.row(top, x0, x1, "^")

    # -- checks -----------------------------------------------------------
    def verify(self, name):
        problems = []

        # every row the same width
        for y, r in enumerate(self.g):
            if len(r) != self.w:
                problems.append(f"row {y} is {len(r)} wide, expected {self.w}")

        # exactly one spawn and one descent
        flat = "".join("".join(r) for r in self.g)
        for ch, label in (("@", "spawn"), ("v", "descent")):
            if flat.count(ch) != 1:
                problems.append(f"expected 1 {label}, found {flat.count(ch)}")

        # no pit wider than a jump
        floor_row = max(t for _, _, t in self.surfaces if t >= self.h - 8)
        run = 0
        for x in range(self.w):
            if self.g[floor_row][x] in SOLID:
                run = 0
            else:
                run += 1
                if run > MAX_PIT:
                    problems.append(f"pit at x={x - run + 1}..{x} is {run} wide, max {MAX_PIT}")
                    run = 0

        # nothing you have to reach is above a single jump
        for x0, x1, top in self.surfaces:
            if floor_row - top > MAX_CLIMB:
                problems.append(
                    f"surface x={x0}..{x1} sits {floor_row - top} tiles up, max {MAX_CLIMB}")

        # every entity is standing on something
        for y in range(self.h - 1):
            for x in range(self.w):
                if self.g[y][x] in "@xwv":
                    below = self.g[y + 1][x]
                    if below not in SOLID and below != "=":
                        problems.append(f"'{self.g[y][x]}' at {x},{y} is floating")

        if problems:
            print(f"  {name}: FAILED")
            for p in problems:
                print(f"    - {p}")
            return False
        return True

    def save(self, name):
        ok = self.verify(name)
        os.makedirs(OUT, exist_ok=True)
        with open(os.path.join(OUT, name), "w") as f:
            for line in self.header:
                f.write("#! " + line + "\n")
            f.write("\n")
            for row in self.g:
                f.write("".join(row) + "\n")
        print(f"  levels/{name}  {self.w}x{self.h}  {'ok' if ok else 'CHECK FAILED'}")
        return ok


# --------------------------------------------------------------------------
def surface():
    m = Map(64, 14, [
        "SURFACE - the tutorial ledge.",
        "Move, jump a gap, collect, meet a crawler, tame a critter, descend.",
    ])
    F = 9                                  # floor row
    m.ledge(0, 16, F)
    m.ledge(19, 34, F)
    m.ledge(37, 51, F)
    m.ledge(54, 64, F)
    for a, b in [(16, 19), (34, 37), (51, 54)]:
        m.shaft(a, b)

    m.platform(10, 4, F - 3)
    m.platform(24, 4, F - 3)
    m.platform(41, 5, F - 3)
    m.platform(46, 4, F - 3)

    for x in (11, 12, 25, 26, 42, 43, 47, 48):
        m.put(x, F - 4, "c")
    for x in (6, 30, 58, 59):
        m.put(x, F - 1, "c")

    m.put(3, F - 1, "@")
    m.put(28, F - 1, "x")
    m.put(45, F - 1, "x")
    m.put(21, F - 1, "w")
    m.put(61, F - 1, "v")
    return m


def caverns():
    m = Map(76, 15, [
        "CAVERNS - a ceiling overhead, embers underfoot, a raised shelf.",
    ])
    F = 10
    m.rect(0, 0, 76, 15, ":")
    m.rect(0, 1, 76, F, ".")
    m.row(0, 0, 76, "1")

    m.ledge(0, 13, F)
    m.ledge(16, 28, F)
    m.ledge(31, 42, F - 3)          # the raised shelf, one jump up
    m.rect(31, F - 2, 42, 15, "1")
    m.ledge(45, 58, F)
    m.ledge(61, 76, F)
    for a, b in [(13, 16), (28, 31), (42, 45), (58, 61)]:
        m.shaft(a, b, ceiling=True)

    m.embers(8, 10, F)
    m.embers(52, 54, F)
    m.row(F - 3, 33, 40, "*")

    m.platform(13, 3, F - 3)
    m.platform(28, 3, F - 3)
    m.platform(42, 3, F - 3)
    m.platform(58, 3, F - 3)

    m.put(3, F - 1, "@")
    for x, y in [(5, F - 1), (19, F - 1), (20, F - 1), (35, F - 4), (36, F - 4),
                 (49, F - 1), (66, F - 1), (67, F - 1), (14, F - 4), (59, F - 4)]:
        m.put(x, y, "c")

    m.put(23, F - 1, "x")
    m.put(37, F - 4, "x")
    m.put(50, F - 1, "x")
    m.put(26, F - 1, "w")
    m.put(72, F - 1, "v")
    return m


def abyss():
    m = Map(70, 17, [
        "ABYSS - crowded, unfriendly, and the end of the placeholder.",
    ])
    F = 12
    m.rect(0, 0, 70, 17, ":")
    m.rect(0, 1, 70, F, ".")
    m.row(0, 0, 70, "1")

    m.ledge(0, 12, F)
    m.ledge(15, 25, F)
    m.ledge(28, 38, F - 3)
    m.rect(28, F - 2, 38, 17, "1")
    m.ledge(41, 50, F)
    m.ledge(53, 62, F - 3)
    m.rect(53, F - 2, 62, 17, "1")
    m.ledge(65, 70, F)
    for a, b in [(12, 15), (25, 28), (38, 41), (50, 53), (62, 65)]:
        m.shaft(a, b, ceiling=True)

    m.embers(6, 8, F)
    m.embers(20, 22, F)
    m.embers(45, 47, F)
    m.row(F - 3, 30, 36, "*")
    m.row(F - 3, 55, 60, "*")

    m.platform(12, 3, F - 3)
    m.platform(25, 3, F - 3)
    m.platform(38, 3, F - 3)
    m.platform(50, 3, F - 3)
    m.platform(62, 3, F - 3)

    m.put(2, F - 1, "@")
    for x, y in [(10, F - 1), (17, F - 1), (32, F - 4), (33, F - 4),
                 (43, F - 1), (57, F - 4), (58, F - 4), (67, F - 1),
                 (13, F - 4), (39, F - 4)]:
        m.put(x, y, "c")

    m.put(18, F - 1, "x")
    m.put(34, F - 4, "x")
    m.put(44, F - 1, "x")
    m.put(59, F - 4, "x")
    m.put(4, F - 1, "w")
    m.put(68, F - 1, "v")
    return m


if __name__ == "__main__":
    print("Generating BocciaBound level maps...")
    results = [surface().save("surface.txt"),
               caverns().save("caverns.txt"),
               abyss().save("abyss.txt")]
    print("Done.")
    sys.exit(0 if all(results) else 1)
