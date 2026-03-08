# Map Generator Notes

## What it does

When the game starts, the map generator builds the entire game world. It runs in this order:

1. Ask the Tile Registry what ID numbers floor, water, and wall tiles are
2. Clear the GridMap
3. Fill the entire map with floor tiles
4. Place a lake somewhere on the map
5. Place a home somewhere on the map

---

## The coordinate system

The map is 80 tiles wide and 40 tiles tall, centered around world position (0, 0). That means:
- X goes from -40 to 39
- Z goes from -20 to 19

This keeps the map centered in the world rather than starting at a corner.

---

## Tile IDs

Tile IDs are not hardcoded in the generator. Instead they are looked up from the **Tile Registry** autoload, which reads from `data/tiles.json`. This means if tile IDs change in the JSON, the generator doesn't need to be touched.

Each tile in `tiles.json` has:
- `name` — used to look up the tile by name
- `description` — flavour text
- `walkable` — whether the player can walk on it

---

## How structures work

Every structure (lake, home, etc.) goes through the same pipeline:

```
create_lake() / create_home()
    └── generates a random size
    └── generate_lake_pattern() / generate_home_pattern()
            └── returns a 2D array where each cell says what tile goes there
    └── create_structure(pattern, width, height)
            └── create_random_origin_for_structure()
                    └── picks a random position
                    └── checks is_area_clear() — retries if anything other than floor is in the way
            └── place_structure()
                    └── loops the 2D array and sets each cell in the GridMap
            └── if the structure is water, updates the water shader
```

### Patterns

A pattern is a 2D array — a grid of tile IDs that defines the shape of a structure.

**Lake pattern** — every cell is water. Size is random (3–7 wide, 4–8 tall).

**Home pattern** — border cells are walls, interior cells are floor. One random non-corner perimeter tile is set to floor to act as a door. Size is random (5–9 wide, 5–9 tall).

Adding a new structure type means writing a new `generate_x_pattern()` function and a `create_x()` function — nothing else needs to change.

---

## Collision avoidance

Before placing a structure, `is_area_clear()` scans every cell in the target rectangle. If any cell is not a floor tile, the origin is rejected and a new random position is tried. This prevents structures from overlapping.

---

## Movement and walkability

The player movement code checks `TileRegistry.is_walkable(tile_id)` before allowing a step. This is driven entirely by the `walkable` field in `tiles.json` — no tile-specific logic lives in the movement code.

---

## What could be refactored later

- `create_structure` detects water by checking `pattern[0][0]` — this is a fragile assumption. A cleaner approach would be to pass a structure type or have the shader setup live in `create_lake` directly.
- `create_floor` doesn't go through `create_structure` — it has its own loop. It could be unified.
- As more structure types are added, a data-driven approach (defining structures in JSON like tiles) may become worthwhile.
