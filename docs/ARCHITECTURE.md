# How BocciaBound fits together

## The shape of it

```
Game (autoload)          state that survives a scene change
Ui   (autoload)          HUD, fade, messages. Also survives

scenes/main.tscn         title screen
  |
  v  Game.change_zone()
scenes/levels/zone_*.tscn
  |
  +-- Backdrop      CanvasLayer at layer -100, drifts with the camera
  +-- Background    TileMapLayer, no collision, shafts and ceilings
  +-- Tiles         TileMapLayer, collision, everything you stand on
  +-- Entities      spawned at runtime from the text map
        |
        +-- Player      carries the Camera2D
        +-- Crawler     enemy
        +-- Critter     tameable
        +-- Crystal     pickup
        +-- Hazard      area over an ember tile
        +-- Descent     area that loads the next zone
```

## Why levels are text files

A tilemap painted in the Godot editor is stored as a packed integer array. It works, but you cannot read it, you cannot review a change to it, and two people editing the same map produces a conflict nobody can resolve by hand.

A text map is the opposite. You can see the level in the diff. You can edit it in any editor. A script can generate one, and so can an AI. The cost is that `scripts/level.gd` has to build the tilemap at load, which takes a few milliseconds.

When the game gets big enough that hand-placed detail matters more than reviewability, swap `_build()` for a real editor-authored TileMapLayer. Nothing else has to change, because everything else only talks to the scene tree.

## Why the camera lives on the player

Because scene changes replace the whole tree. A camera parented to the level would have to find the player and follow it. Parented to the player, it just works, and the level only has to set the limits so the view never runs off the edge of the map.

## Why the HUD is an autoload

Same reason. `get_tree().change_scene_to_file()` frees everything in the current scene. If the HUD lived in the level, hearts would flicker on every descent and the fade would be destroyed halfway through fading.

## The damage flow

```
Crawler._check_player()          runs every physics frame
  overlapping bodies include the player?
    player above and falling  ->  player.bounce(), crawler.die()
    otherwise                 ->  player.take_damage(1, direction)
                                    -> sets invulnerability, knockback
                                    -> Game.damage(1)
                                        -> health_changed signal
                                            -> Ui redraws the hearts
```

Overlap is checked every frame rather than with `body_entered`, because `body_entered` fires once. Standing against an enemy would be free.

## Adding a system

Put state that has to survive a descent in `Game`. Put anything on screen that has to survive a descent in `Ui`. Everything else goes in the level scene and dies with it. That single rule covers most decisions.
