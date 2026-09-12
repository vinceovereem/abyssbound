#!/usr/bin/env python3
"""
Builds assets/tiles/tileset.tres from data/tiles.json.

Collision comes from the "solid" flag in the tile data, so there is one place
that decides whether a tile can be stood on and the tile set cannot drift away
from what the game believes.

Run:  python3 tools/gen_tileset.py
"""

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "tiles.json")
OUT = os.path.join(ROOT, "assets", "generated", "tiles", "tileset.tres")

# Ids 0 to 5 are the archived placeholder zones in levels/legacy/. They predate
# data/tiles.json and are not part of the generated world, so their collision
# lives here. Do not renumber them: the archived maps point at these columns.
LEGACY_SOLID = [0, 1, 4, 5]
LEGACY_ONEWAY = [2]          # the one-way platform
LEGACY_NONE = [3]            # background stone

FULL = "PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)"
TOP = "PackedVector2Array(-8, -8, 8, -8, 8, -3, -8, -3)"


def main():
    tiles = json.load(open(DATA))["tiles"]
    solid = {int(t["id"]) for t in tiles if t.get("solid")}
    # A platform is not solid, but you can stand on it: collision on the top
    # edge only, so you walk up through it from below.
    platforms = {int(t["id"]) for t in tiles if t.get("platform")}
    highest = max(int(t["id"]) for t in tiles)
    # 22 is the edge overlay: drawn, never collided with, so it is not in the
    # tile data. Make sure the sheet is still covered up to the last column.
    total = max(highest, 22) + 1

    out = [
        '[gd_resource type="TileSet" load_steps=3 format=3]',
        "",
        '[ext_resource type="Texture2D" path="res://assets/generated/tiles/tiles.png" id="1_tiles"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_main"]',
        'texture = ExtResource("1_tiles")',
        "texture_region_size = Vector2i(16, 16)",
    ]
    for i in range(total):
        out.append(f"{i}:0/0 = 0")
        if i <= 5:
            if i in LEGACY_SOLID:
                out.append(f"{i}:0/0/physics_layer_0/polygon_0/points = {FULL}")
            elif i in LEGACY_ONEWAY:
                out.append(f"{i}:0/0/physics_layer_0/polygon_0/points = {TOP}")
                out.append(f"{i}:0/0/physics_layer_0/polygon_0/one_way = true")
        elif i in solid:
            out.append(f"{i}:0/0/physics_layer_0/polygon_0/points = {FULL}")
        elif i in platforms:
            out.append(f"{i}:0/0/physics_layer_0/polygon_0/points = {TOP}")
            out.append(f"{i}:0/0/physics_layer_0/polygon_0/one_way = true")
    out += [
        "",
        "[resource]",
        "physics_layer_0/collision_layer = 1",
        'sources/0 = SubResource("TileSetAtlasSource_main")',
    ]
    open(OUT, "w").write("\n".join(out) + "\n")
    print(f"  tiles/tileset.tres  {total} tiles, {len(solid) + len(LEGACY_SOLID)} solid")


if __name__ == "__main__":
    main()
