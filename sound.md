# Sound System

## Overview

Sound is emitted by the player on every move. It propagates outward as a wave, visually replacing tiles with a Sound tile (id 2) ring by ring, then restoring them as the wave passes.

## Files

- `scenes/character/character_sound.gd` — wave emission and propagation
- `tile_registry.gd` — tile sound dampening lookups and sound claim/release tracking
- `data/tiles.json` — per-tile `sound_dampening` values

## How Propagation Works

`_build_rings` computes all rings up to `RADIUS` before the wave plays out. Each cell tracks a `remaining` budget inherited from its best (highest remaining) parent cell one ring closer to the origin.

Every step costs 1 by default. Wall tiles add their `sound_dampening` value on top of that base cost, reducing how far sound travels past them.

```
remaining[cell] = best_parent_remaining - 1 - extra_dampening
```

A cell is added to its ring (shown visually) if:
- It has no extra dampening (not a wall)
- Its remaining budget is >= 0

Wall cells are never shown visually but still store their reduced `remaining` value, so cells beyond them propagate with a smaller budget.

## Diamond Shape

The wave produces a diamond (rotated square) pattern rather than a filled square. This is because the ring iteration uses Chebyshev distance (`maxi(absi(dx), absi(dz)) == r`), but the budget is consumed per ring step. A diagonal cell at Chebyshev distance 5 has a real Manhattan distance of 10, but only costs 5 budget — the same as a cardinal cell at distance 5. This means diagonals reach further in real terms, compressing the shape into a diamond. This is intentional and gives the sound a natural, aesthetically fitting spread for a roguelike.

## Tile Dampening Values

| Tile  | sound_dampening |
|-------|----------------|
| Floor | 0              |
| Water | 0              |
| Sound | 0              |
| Wall  | 2              |

## Walkability Bug Fix

`character_movement.gd` previously checked walkability against the current cell item, which could be the Sound tile (walkable) even if the underlying tile was a Wall. Fixed by resolving the true tile via `TileRegistry.get_original_tile` before the walkability check.
