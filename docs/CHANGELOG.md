# Changelog

## v1 — Infinite World Zone System

### Overview
Replaced the hard-bounded 80×40 map with an infinite world made of persistent zones. Walking off any edge loads the adjacent zone, enemies simulate while off-screen, and all zone state (tiles, items, enemies) persists across visits.

### New Files
- **`scripts/world_state.gd`** — Autoload singleton. Stores zone tile data, item records, and off-screen enemy records. Handles coordinate math between world space, zone IDs, and local grid space. Ticks off-screen enemy patrol movement each turn.

### Modified Files
- **`project.godot`** — Registered `WorldState` as the first autoload (before `TileRegistry` and `SceneLoader`).
- **`tile_registry.gd`** — Added `clear_state()` to wipe sound/vision overlay dicts on zone transition.
- **`scripts/scene_loader.gd`** — Added zone transition handler `_on_zone_exit`: tears down current zone (serializes enemies + items, clears grid), generates/loads new zone, restores returning enemies, places player at guaranteed walkable entry cell on the opposite edge. Zone transition costs 15 seconds and runs a full enemy turn. Added `_find_walkable_near` spiral search. Added `_loaded` guard to prevent double initialization.
- **`scripts/turn_order.gd`** — Calls `WorldState.tick_off_screen_enemies()` each turn (skipped on bonus turn path).
- **`scenes/character/character_movement.gd`** — Added `zone: Vector2i` field, `zone_exit(direction)` signal. Emits `zone_exit` when player walks off the map edge instead of silently blocking. `place()` now accepts an optional zone parameter.
- **`scenes/map/map_generator.gd`** — `generate(zone_id)` checks WorldState: loads saved tiles + lake shader data if zone was previously visited, otherwise generates fresh and saves. Lake origins and sizes serialized alongside tile data.
- **`scenes/map/item_configurator.gd`** — `place(zone_id)` loads saved items on revisit, generates and saves on first visit.
- **`scenes/map/enemy_configurator.gd`** — `spawn(zone_id)` restores off-screen enemies returning to the zone. Only spawns fresh enemies on first visit (tracked via `WorldState.is_visited`).

### Architecture
- **Coordinate system:** World coords are continuous integers. Zone ID = `floor(world / zone_size)`. Local coords are zone-centered: X in [-40, 39], Z in [-20, 19].
- **Visited vs cached:** `has_zone` = tile data exists (set after map generation). `is_visited` = full load sequence completed (set after enemies spawn). Items and enemies use `is_visited` to avoid skipping fresh spawns.
- **Off-screen simulation:** Enemies in `WorldState.off_screen_enemies` tick patrol movement every turn. No pathfinding or vision off-screen — they drift via patrol sequence only.
- **Zone transition order:** Enemy turns → serialize enemies → serialize items → clear TileRegistry state → clear GridMap → generate new zone → place items → spawn enemies → place player → mark visited.
