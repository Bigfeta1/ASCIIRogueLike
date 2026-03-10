# ChemRogueLite — Architecture Overview

A reference document for onboarding new developers. 
This covers project structure, core systems, data flow, and common patterns.

---

## 1. Project Summary

ChemRogueLite is a turn-based ASCII-style roguelike built in Godot 4.5. Key properties:

- 3D GridMap for tile space; all movement is on a discrete grid
- Component-based character architecture (one Node3D with many child scripts)
- Event-driven turn system (signal-based, not polling)
- Procedural zone generation with persistent state across zone transitions
- AI enemies with behavior states, vision cones, and sound detection

**Main scene**: `res://scenes/main/main_scene.tscn`
**Window**: 1920×1080 orthographic

---

## 2. Directory Structure

```
chem-rogue-lite/
├── project.godot
├── tile_registry.gd              # Autoload: tile data, overlay management
├── data/
│   ├── items.json                # All item definitions
│   ├── enemies.json              # Enemy templates
│   ├── tiles.json                # Tile properties
│   └── world_items.json          # World item spawn data
├── scripts/
│   ├── turn_order.gd             # Turn flow controller
│   ├── world_state.gd            # Zone persistence, enemy serialization
│   ├── scene_loader.gd           # Bootstrap: builds map, places enemies/items
│   ├── item_registry.gd          # Autoload: item lookup from items.json
│   └── camera.gd                 # Orthographic camera with zoom
├── scenes/
│   ├── character/                # All character component scripts
│   ├── look_cursor/              # Look mode overlay
│   ├── map/                      # Map generation and configuration
│   ├── main/                     # Main scene, UI modals
│   ├── items/                    # World item scenes
│   └── tree/                     # Destructible tree nodes
└── assets/
	└── images/                   # Sprites for characters, items, tiles
```

---

## 3. Autoloads / Singletons

| Name | File | Purpose |
|------|------|---------|
| `TileRegistry` | `tile_registry.gd` | Tile property lookup; manages vision and sound overlays on GridMap cells |
| `SceneLoader` | `scripts/scene_loader.gd` | Initializes each zone: generates map, places world items, spawns enemies |
| `WorldState` | `scripts/world_state.gd` | Persists zone tiles, items, trees, and enemy state across zone transitions |
| `ItemRegistry` | `scripts/item_registry.gd` | Loads `items.json`; provides `get_item(id)` lookup |

---

## 4. Scene Hierarchy

```
MainScene (Node3D)
├── DirectionalLight3D
├── Camera3D                    # camera.gd — 3 zoom levels: 230, 145, 60
├── CanvasLayer                 # All 2D UI
│   ├── TopBar                  # Vitals + level display (HP, BP, HR, RR, Temp)
│   ├── CharacterSheet          # Inventory / stats / equipment UI
│   ├── LootModal               # Loot UI for fallen enemies on tile
│   ├── InteractModal           # FillModal for tile actions and inspection
│   └── LookModeInfo            # Labels shown during look mode
├── GridMap                     # MAP_WIDTH=80, MAP_HEIGHT=40
│   ├── MapGenerator
│   ├── EnemyConfigurator
│   ├── ItemConfigurator
│   ├── MapParameters           # Per-zone time tracking
│   ├── OccupancyMap            # Spatial index: grid_pos → solid/passable occupants
│   └── [trees and world items spawn here at runtime]
├── Character (player)          # character.tscn — see §5
├── GameLogic (Node)
│   └── TurnOrder
└── [enemy instances spawn here at runtime]
```

---

## 5. Character Architecture

Every character (player and NPC) is a `Node3D` using `character.gd` as the base, with child nodes for each subsystem.

`character.gd` is a **component manifest**: it holds identity fields (`faction`, `action_state`, `defeated_sprite`, `corpse_item_id`) and `@onready` refs to every sibling component. External nodes access components through these refs rather than calling `get_node()` by name themselves. There are no delegate methods — callers go directly to the component (e.g. `character.interaction.open_inspect_modal(...)`).

### Child Components

| Node | Script | Responsibility |
|------|--------|---------------|
| `CharacterMovement` | `character_movement.gd` | Grid position, input handling, zone exit |
| `CharacterSprite` | `character_sprite.gd` | Visual mesh; `set_defeated()` swaps texture, spawns blood splatter |
| `CharacterVitals` | `character_vitals.gd` | HP, blood pressure, heart rate, respiration, temperature |
| `CharacterLevels` | `character_levels.gd` | 6 stats + modifiers, XP, leveling |
| `CharacterInventory` | `character_inventory.gd` | Item list, weight, durability, container liquid contents |
| `CharacterEquipment` | `character_equipment.gd` | 18 equipment slots, weight class calculation |
| `CharacterCombat` | `character_combat.gd` | Bump attack animation, damage calculation |
| `CharacterLifecycle` | `character_lifecycle.gd` | Transition controller: die, knock_out, enter_combat, restore_incapacitated |
| `CharacterAI` | `character_ai.gd` | Behavior state machine, patrol/investigate/combat routing, pathfinding (NPC only) |
| `CharacterVision` | `character_vision.gd` | LOS raycasting (`can_see`), vision cone, GridMap overlay tiles (NPC only) |
| `CharacterSound` | `character_sound.gd` | Sound wave propagation from movement |
| `CharacterActions` | `character_actions.gd` | Action economy; bonus turns via `time_credits` |
| `CharacterInteraction` | `character_interaction.gd` | Player-side UI coordination: input handling, modal wiring, target lock, interaction menu, pending action execution (player only) |
| `LookCursor` | `look_cursor/look_cursor.gd` | Tile/enemy inspection overlay |
| `InteractCursor` | `interact_cursor.gd` | Interaction menu cursor |
| `DamageLabel` | `damage_label.gd` | Floating 2D damage popup |

### Key Enums

```gdscript
# character.gd
enum ActionState { MOVEMENT, LOOK, MENU, INTERACTION }
enum CharacterType { SURGEON, ENEMY }
enum CharacterRole { PLAYER, NPC }

# character_interaction.gd
enum InteractionSubState { NONE, MOVE_CURSOR, INTERACTION_MENU, LOOT, COLLECT_LIQUID, INSPECTION, USE_ITEM }
```

---

## 6. Turn System (`scripts/turn_order.gd`)

Turn flow is **signal-driven**. The player takes an action → signals fire → enemies act → back to player.

### States
```gdscript
enum TurnState { PLAYER_TURN, MAP_TURN, IDLE }
```

### Flow

```
Player moves/waits
  → CharacterMovement emits `moved` or `waited`
  → TurnOrder begins MAP_TURN (after 0.1s delay for animation)
	  → All enemies with life_state == ALIVE call take_turn_step()
	  → WorldState.tick_off_screen_enemies()   (advance patrol state)
	  → MapParameters.advance_time(15)
	  → All characters: CharacterVitals.tick_regen()
  → TurnOrder returns to PLAYER_TURN
```

**Bonus turns**: If `CharacterActions.time_credits > 0` after MAP_TURN, player gets another move without consuming a turn.

---

## 7. Grid & World Space

- Zone size: **80×40 cells**
- GridMap cell: `Vector3i(x, 0, z)` — Y is always 0
- Local cell coords: `Vector2i(x, y)` (Y maps to GridMap Z)
- World origin of a cell:
  ```gdscript
  var local = grid_map.map_to_local(Vector3i(x, 0, y))
  var world  = grid_map.to_global(local)
  ```
- Zone transitions via `zone_exit(direction: Vector2i)` signal from `CharacterMovement`

---

## 8. Combat System (`character_combat.gd`)

### Bump Attack

Characters move toward a target (45% of the way), pause, then return. `attack_finished` signal fires when animation completes.

### Damage Resolution

```
Hit Roll = 1d20 + attacker_hit_mod + weapon_hit_bonus − weight_mismatch_penalty
Evasion  = 10 + defender_hit_mod
Miss if hit_roll < evasion

Damage = 1d{damage_die} + muscle_mod
Crit   = 5% + affect_mod × 2.5% → uses crit_damage_die instead

Defense (in order, only one applies):
  1. Parry  — certain weight combos only; roll 19+ vs attacker_parry
  2. Dodge  — light/medium armor only; roll 19+ vs defender_dodge
  3. Block  — all classes; roll 19+ blocks, 1d6 partial reduction

Weapon durability: −2 per attack
```

**Weight class mismatch penalties**: −4 to hit (1 category gap), −8 (2+ categories)

### CharacterLifecycle (`character_lifecycle.gd`)

`CharacterLifecycle` is a **transition controller**, not a state store. State lives in `CharacterAI` (`life_state`, `behavior_state`). Lifecycle owns the legal transitions between states and their cross-component side effects.

**Rule**: use `CharacterLifecycle` only when a transition crosses multiple sibling components. Purely internal AI transitions (patrol → investigate → return) stay in `CharacterAI`.

#### Methods

- `die(target)` — guards against duplicate death; sets `life_state = DEAD`; clears vision; disables AI/Movement/Combat processing; adds corpse item; calls `set_defeated()`; emits `died`
- `knock_out(target)` — sets `life_state = KNOCKED_OUT`; disables processing; clears vision; emits `knocked_out`
- `enter_combat(target)` — sets `behavior_state = COMBAT` if alive and not already in combat; emits `entered_combat`. Lives here because the trigger (player bump) originates in Movement while the state lives in AI.
- `restore_incapacitated(target, saved_life_state)` — used by `EnemyConfigurator` on zone load; applies state and disables components without re-triggering side effects (no corpse item add, no `set_defeated`)

#### Signals

```gdscript
signal died(character: Node)
signal knocked_out(character: Node)
signal revived(character: Node)
signal entered_combat(character: Node)
```

Future systems (UI, sound, quests) subscribe to these rather than being called directly.

#### Call sites

`CharacterCombat._apply_damage()` detects HP ≤ 0 → calls `lifecycle.die(target)`. Does not touch AI, Sprite, or Inventory directly.
`CharacterMovement._check_move()` detects a hostile bump → calls `lifecycle.enter_combat(target)`. Does not write `behavior_state` directly.

---

## 9. AI System (`character_ai.gd`)

### State Domains

`CharacterAI` uses two orthogonal enums to represent enemy state:

**`LifeState`** — physical condition; the primary gate for turn processing:
```
ALIVE → KNOCKED_OUT / DEAD
```

**`BehaviorState`** — activity/awareness; only meaningful when `life_state == ALIVE`:
```
RELAXED → SUSPICIOUS → INVESTIGATE → RETURN → RELAXED
				↓
			  ALERT → COMBAT
PATROL (loops independently)
SLEEPING
```

Incapacitation sets `life_state` to KNOCKED_OUT or DEAD. `behavior_state` retains its last value but is ignored while the enemy is not ALIVE.

### Vision (`character_vision.gd`)

Vision logic and overlay rendering live in `CharacterVision`, not in `CharacterAI`. AI calls `vision.can_see(pos)` and `vision.update(disposition)` — it does not touch the GridMap directly.

- Range: `sympathetic` stat (cells)
- Cone: ±(sympathetic × 3.5°) around facing direction (`CharacterAI.facing_vector()`)
- Raycasting via Bresenham; blocked by vision-blocking tiles and solid entities
- Overlay tiles: only drawn for HOSTILE enemies; `vision.clear()` is called by `CharacterLifecycle` on incapacitation

**Known limitation**: entity occlusion in `can_see` uses `has_method("take_damage")` as a proxy for "solid entity." This is a placeholder until an occupancy service exists.

### Player Reference Injection

`CharacterAI` does not climb the scene tree to find the player. `TurnOrder.register_enemy()` calls `ai.setup(player_node)` immediately after registration, injecting the reference directly.

### Sound
- Player movement emits sound waves (intensity = 5 − distance − tile_dampening)
- Reaches enemies in RELAXED/SUSPICIOUS/PATROL states
- Intensity ≥ 3 → escalates directly to INVESTIGATE; lower → goes to SUSPICIOUS first

### Pathfinding
- `AStarGrid2D` (80×40 grid), built once in `_ready()`
- Diagonal movement allowed if no obstacles
- **Known limitation**: static — does not update if tiles change (e.g. doors, destroyed trees). Deferred until destructible terrain is implemented.

---

## 10. Inventory & Equipment

### CharacterInventory
- `items: Array[String]` — item IDs (duplicates allowed)
- `item_uids: Array[int]` — unique ID per item instance
- `item_durability: Dictionary` — uid → current durability
- `container_contents: Dictionary` — uid → `{liquid: String, amount_liters: float}`
- Carry limit: `100.0 + muscle_mod × 5.0` kg

### CharacterEquipment
- 18 slots: head, face, neck, chest, shirt, shoulder, bracers, gloves, belt, legs, feet, outerwear, back, r_hand, l_hand, ring_1, ring_2, trinket_1, trinket_2
- Weight classes:
  - **Light**: <5 lbs (weapon) / <25 lbs (armor)
  - **Medium**: 5–15 lbs / 25–60 lbs
  - **Heavy**: ≥15 lbs / ≥60 lbs

---

## 11. Stats System (`character_levels.gd`)

### 6 Core Stats (default 10)

| Stat | Influences |
|------|-----------|
| `muscle` | Melee damage, block, parry, carry weight |
| `cardio` | Hit accuracy, HP regen |
| `adrenal` | Damage, crit damage, regen |
| `sympathetic` | Vision range, hit accuracy, parry, bonus turn speed |
| `parasympathetic` | Parry, regen |
| `affect` | Crit chance, dodge |

Modifier formula: `floor((stat - 10) / 2)`

### Derived Mods
```
hit_mod    = avg(cardio, adrenal, sympathetic, parasympathetic) mods
dodge_mod  = avg(cardio, adrenal, affect) mods
block_mod  = avg(muscle, sympathetic) mods
parry_mod  = avg(muscle, parasympathetic) mods
regen_mod  = avg(adrenal, cardio, parasympathetic) mods
```

### Leveling
- `xp_to_next = 25 × level²`
- Player earns 10 XP per kill

---

## 12. Zone Persistence (`world_state.gd`)

When the player exits a zone:
1. All enemy states are serialized to `off_screen_enemies` (position, AI state, patrol info, stats, HP, inventory with durability/liquids, blood splatter flag)
2. Tile layout, items, and tree positions stored in `zones[zone_id]`
3. On re-entry: `EnemyConfigurator` restores enemies from saved data; `MapGenerator` restores tiles and trees

Off-screen enemies have patrol movement simulated (1 step/turn) via `tick_off_screen_enemies()`.

---

## 13. Tile System (`tile_registry.gd`)

Each tile has:
```json
{
  "id": 0,
  "name": "Floor",
  "walkable": true,
  "blocks_vision": false,
  "sound_dampening": 0,
  "liquid": "water",
  "actions": ["Drink", "Collect"],
  "description": "..."
}
```

**Overlay tiles** (temporary, ref-counted):
- Tile ID 2: Sound propagation visual
- Tile ID 4: Vision range visual

Use `TileRegistry.get_original_tile(cell, current_tile_id)` to get the real tile under an overlay.

---

## 14. Data Files

### `data/items.json`
```json
{
  "id": "combat_knife",
  "name": "Combat Knife",
  "weight": 0.5,
  "category": "melee",
  "interaction": "equip",
  "sprite": "res://assets/...",
  "slot": "r_hand",
  "damage_die": 4,
  "hit_bonus": 8,
  "durability_max": 100,
  "capacity_liters": 0.25,
  "allowed_liquids": ["water", "alcohol"]
}
```

Categories: `melee`, `ranged`, `armor`, `clothes`, `medicine`, `container`, `camping`, `misc`

### `data/enemies.json`
```json
{
  "id": "soldier",
  "name": "Soldier",
  "faction": "military",
  "count": 5,
  "hp": 8,
  "defeated_sprite": "res://...",
  "corpse_item_id": "corpse_soldier",
  "inventory_items": ["field_bandage", "tinder_box"],
  "stats": { "muscle": 10, "cardio": 10, ... }
}
```

---

## 15. UI Systems

| UI Node | Script | Purpose |
|---------|--------|---------|
| `CharacterSheet` | `character_sheet.gd` | Tabbed view: STATS / INVENTORY / EQUIPMENT |
| `LootModal` | `loot_modal.gd` | Lists items from all incapacitated enemies on player's tile |
| `FillModal` | `fill_modal.gd` | Generic action picker; liquid filling; item inspection |
| `TopBar` | — | Live vitals display; updated by `CharacterVitals._refresh_ui()` |

**LootModal notes**: Tab or I while looting suspends the modal (`_loot_interrupted` flag); it restores when the character sheet closes. Taking the corpse item hides the CharacterSprite (the body is "picked up"); blood splatter stays.

---

## 16. Input Map

| Key | Action |
|-----|--------|
| Arrow keys / WASD | Move |
| Space | Wait (pass turn) |
| Tab / I | Open Character Sheet / Inventory |
| C | Toggle Look mode |
| E | Interact with tile |
| Q / Escape | Cancel / close modal |
| Mouse wheel | Camera zoom |

---

## 17. Common Patterns

### Accessing a sibling component

From **external nodes** (outside the character), use the `@onready` refs on `character.gd`:
```gdscript
var inventory = character.inventory
var ai = character.ai
```

From **child component scripts** during `_ready()`, `@onready` refs on the parent are not yet set — use `get_node()` directly for sibling lookups:
```gdscript
func _ready() -> void:
    var character = get_parent()
    var levels = character.get_node("CharacterLevels")  # sibling, safe
```

Scene-external refs (GridMap, Camera, UI nodes) are **never** looked up by components directly. They are injected via `setup()` called from `character.gd._ready()`:
```gdscript
func setup(grid_map: GridMap, canvas_layer: CanvasLayer, camera: Camera3D) -> void:
    _grid_map = grid_map
    _canvas_layer = canvas_layer
    _camera = camera
```

After `_ready()`, child components may safely use `get_parent().<ref>` for any `@onready` var on the character.

### GridMap cell → world position
```gdscript
var local = grid_map.map_to_local(Vector3i(x, 0, y))
var world  = grid_map.to_global(local)
```

### Checking tile properties
```gdscript
var tile_id = grid_map.get_cell_item(Vector3i(x, 0, y))
var real_id = TileRegistry.get_original_tile(cell, tile_id)
if TileRegistry.is_walkable(real_id):
    ...
```

### Item lookup
```gdscript
var data   = ItemRegistry.get_item("combat_knife")
var weight = data.get("weight", 0.0)
```

### Checking if an enemy is incapacitated
```gdscript
var ai = enemy.get_node("CharacterAI")
if ai.life_state != ai.LifeState.ALIVE:
    # skip this enemy in turn order
```

### Signal connections (always in _ready or at instantiation, never deferred)
```gdscript
func _ready() -> void:
    get_node("CharacterMovement").moved.connect(_on_moved)
```

---

## 18. Blood Splatter

Blood splatter is a `MeshInstance3D` named `"BloodSplatter"` added as a child of the Character node on death (by `character_sprite.gd`). It has no script. To find it:

```gdscript
var splatter := character.get_node_or_null("BloodSplatter")
```

The camera is top-down; sprites are horizontal `PlaneMesh` instances. Do **not** rotate sprites on X to show a defeated state — swap the texture instead.

---

## 19. Ownership Rules

These are hard rules about which node is the single authority for each piece of state. 
Do not read or mutate these from outside the owning node unless the rule explicitly permits it.

---

### Turn phase

**Owner: `TurnOrder`** (`scripts/turn_order.gd`)

`TurnOrder.current_turn_state` 
	is the only authoritative source for whether it is the player's turn or the map's turn. 
	No other node transitions this value. 
	The only triggers are the `moved` and `waited` signals from `CharacterMovement` 
		both are connected exclusively in `TurnOrder._ready()`. 
		Nothing else may call `turn_changed` or write `current_turn_state`.

---

### Action credit and bonus turns

**Owner: `CharacterActions`** (`scenes/character/character_actions.gd`)

`CharacterActions.time_credits` 
	is the only thing that determines whether the player gets a bonus turn. 
	`TurnOrder` calls `spend_action()`, `has_bonus_turn()`, and `consume_bonus_turn()` 
		— it does not read or write `time_credits` directly. 
		No other node touches this value.

---

### Current zone identity

**Owner: `WorldState`** (`scripts/world_state.gd`)

`WorldState.current_zone` is the authoritative zone ID. 
	`CharacterMovement` holds `zone` as a local copy of the player's zone, 
	but `WorldState.current_zone` is the truth used for serialization and persistence. 
	Zone coordinate math (`world_to_zone`, `world_to_local`, `local_to_world`) lives exclusively in `WorldState`.

---

### Enemy alive/dead/knocked-out state

**State owner: `CharacterAI`**. **Transition controller: `CharacterLifecycle`**.

`CharacterAI.life_state` is the single source of truth for whether an enemy is ALIVE, KNOCKED_OUT, or DEAD.
	The only code that writes `life_state` is `CharacterLifecycle` (`die`, `knock_out`, `restore_incapacitated`).
	`TurnOrder` reads `life_state` to skip non-alive enemies — it never writes it.
	`CharacterMovement._check_move()` reads it to decide whether to treat a body as a collision — it never writes it.
	Nobody else may write `life_state`.

`CharacterAI.behavior_state` is the single source of truth for current activity/awareness (PATROL, COMBAT, INVESTIGATE, etc.).
	`CharacterAI` owns all purely internal behavior transitions through `take_turn_step()` and its helpers.
	`CharacterLifecycle.enter_combat()` is the only external writer of `behavior_state` — it applies when a transition crosses components (Movement detects the bump, AI owns the state).
	`behavior_state` is meaningless and ignored when `life_state != ALIVE`.

---

### Character world position vs grid position

Two representations exist and each has one owner:

**Grid position — Owner: `CharacterMovement`** (`scenes/character/character_movement.gd`)

`CharacterMovement.grid_pos` (`Vector2i`) is the authoritative grid cell. It is the only value used for game logic (collision checks, AI pathfinding, sound propagation, loot checks). It is written only by `CharacterMovement` itself (`_check_move`, `place`, `step`).

**3D world position — Owner: `CharacterCombat` during bump animation; `CharacterMovement` at all other times**

`character.position` (the Node3D transform) is a visual representation derived from `grid_pos` via `_snap()`. During a bump attack animation, `CharacterCombat._process()` interpolates `character.position` directly. When the animation finishes, control returns to `CharacterMovement`, which snaps position back to `grid_pos` on the next move. Nothing else may write `character.position`.

---

### Tile properties (walkability, vision blocking, sound dampening)

**Owner: `TileRegistry`** — read-only for tile definitions

`TileRegistry._tiles` (loaded from `tiles.json`) is immutable after `_ready()`. Any code that needs to know if a tile is walkable, blocks vision, or dampens sound must call `TileRegistry.is_walkable()`, `TileRegistry.blocks_vision()`, or `TileRegistry.get_sound_dampening()`. Nobody reads `tiles.json` directly.

---

### Tile cell contents (what is placed on the GridMap)

**Owner: the system that has semantic responsibility for that cell type**

Direct `grid_map.set_cell_item()` calls are permitted only from:

- `WorldState` — restoring persisted zone tiles (`load_zone_tiles`)
- `MapGenerator` — generating a new zone
- `CharacterVision` — placing and releasing vision overlay tiles (via `TileRegistry.vision_claim/release`)
- `CharacterSound` — placing and releasing sound overlay tiles (via `TileRegistry.sound_claim/release`)
- `TileRegistry` itself — restoring the original tile when an overlay is released

No other node may call `grid_map.set_cell_item()`. If you need to change a tile, go through `TileRegistry`'s overlay API or `WorldState`'s persistence API.

---

### Player interaction and UI sub-state

**Owner: `CharacterInteraction`** (`scenes/character/character_interaction.gd`) — player only

`CharacterInteraction.interaction_sub_state` is the single source of truth for what UI sub-mode the player is in (cursor moving, menu open, looting, inspecting, etc.). Only `CharacterInteraction` writes it. `CharacterMovement` reads it to decide how to route directional input — it never writes it.

`character.gd`'s `action_state` (`MOVEMENT / LOOK / MENU / INTERACTION`) is the coarse gate used by multiple systems (camera, movement, AI). `CharacterInteraction` is the only node that transitions `action_state` for player UI events. `CharacterMovement` transitions it only for wait/move input.

`pending_action` and `pending_target` on `CharacterInteraction` are the authority for what locked-on action is queued. `CharacterMovement` reads `pending_target` to decide whether a bump is an attack; it never writes these vars.

---

### Grid cell occupancy

**Owner: `OccupancyMap`** (`scenes/map/occupancy_map.gd`) — child of GridMap

`OccupancyMap` is the single source of truth for what physical entities occupy each grid cell. It has two tiers:

- **Solid** (`_solid: Dictionary`): one node per cell. Alive characters and trees. Blocks movement and vision. Written by `CharacterMovement` (`register_solid`, `move_solid`) and `tree.gd` (`register_solid`/`unregister_solid`). `CharacterLifecycle` moves a character from solid to passable on death/KO.
- **Passable** (`_passable: Dictionary`): array per cell. KO/dead enemies. Does not block movement or vision. Multiple nodes may share a cell (e.g. player standing on a corpse tile).

`OccupancyMap.clear()` is called by `SceneLoader` on zone exit, alongside `TileRegistry.clear_state()`.

No system may track occupancy independently. `CharacterVision.can_see()` and `CharacterMovement._check_move()` query `OccupancyMap` exclusively — no scene-tree scanning.

---

### Off-screen enemy state

**Owner: `WorldState`** (`scripts/world_state.gd`)

`WorldState.off_screen_enemies` is the only authoritative record of enemies that are not currently loaded in the scene. `WorldState.serialize_enemy()` is the only way to write a record into it. `WorldState.tick_off_screen_enemies()` is the only place that advances their state. `EnemyConfigurator` reads from it on zone load and removes records via `remove_enemies_in_zone()`. No other node reads or writes `off_screen_enemies`.

---

---

## 20. Known Limitations and Future Pressure Points

### Scene-name coupling in component lookup — ~~resolved~~

All scene-external refs (GridMap, Camera3D, CanvasLayer, UI modals, TurnOrder) are now injected via `setup()` calls from `character.gd._ready()`. No component hardcodes a scene path to a node outside the character subtree.

Sibling lookups (`get_parent().get_node("CharacterX")`) in component `_ready()` methods are still present but limited to the initialization phase, where they are guaranteed safe. These are the only remaining scene-name dependencies.

---

### Provisional occupancy and pathfinding

`OccupancyMap` (`scenes/map/occupancy_map.gd`) is a child of GridMap that tracks solid and passable occupants per cell. It replaced the scene-tree scan hacks in `CharacterVision.can_see()` and `CharacterMovement._check_move()`.

- **Vision occlusion** — ~~resolved~~. `can_see()` queries `OccupancyMap.is_solid()`. Dead/KO bodies are passable and do not block LOS.
- **Pathfinding** (`AStarGrid2D`) is still built once in `_ready()` and never updated. Destroyed trees, opened doors, or any tile change will not be reflected. This is still a known placeholder.

---

### CharacterInteraction as a future god object

`CharacterInteraction` is a good extraction now, but player-side UI coordination is the category most likely to re-accumulate complexity. It currently owns: input state, cursor flow, modal restoration, pending actions, target locking, interaction menu construction, and item-use execution. Each of those is individually small; together they can become a second god object.

Watch for the signal that it is happening: functions that check `interaction_sub_state` at the top before doing anything else, or modal open/close sequences that require tracking multiple booleans simultaneously.

**Mitigation path**: if `CharacterInteraction` grows past ~400 lines of real logic, consider splitting cursor/targeting (what the player is pointing at and why) from modal flow (what UI is open and how it restores). Those two concerns are already loosely separable.
