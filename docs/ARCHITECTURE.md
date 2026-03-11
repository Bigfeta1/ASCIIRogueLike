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
│   ├── items.json                # All item definitions (including structure items like military_chest)
│   ├── enemies.json              # Enemy templates
│   ├── tiles.json                # Tile properties
│   └── structures.json           # Structure definitions (trees, chests, etc.)
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
│   ├── ItemConfigurator        # Restores dropped world items on zone re-entry
│   ├── MapParameters           # Per-zone time tracking
│   ├── OccupancyMap            # Spatial index: grid_pos → solid/passable occupants
│   ├── StructureConfigurator   # Spawns/restores structure entities from structures.json
│   └── [dropped world items (MeshInstance3D) spawn here at runtime]
├── Character (player)          # character.tscn — see §5
├── GameLogic (Node)
│   └── TurnOrder
└── [enemy instances spawn here at runtime]
```

---

## 5. Character Architecture

Every character (player, NPC, and structure) is a `Node3D` using `character.gd` as the base, with child nodes for each subsystem.

`character.gd` is a **component manifest**: it holds identity fields (`faction`, `action_state`, `defeated_sprite`, `corpse_item_id`) and `@onready` refs to every sibling component. External nodes access components through these refs rather than calling `get_node()` by name themselves. There are no delegate methods — callers go directly to the component (e.g. `character.interaction.open_inspect_modal(...)`).

### CharacterType routing in `_ready()`

`character.gd._ready()` routes setup based on `character_type`:

- **`SURGEON` / `ENEMY`**: full setup — movement, lifecycle, combat, vision, sound, cursors. PLAYER additionally sets up vitals UI, inventory, interaction, and levels. NPC additionally calls `ai.setup()` to register with TurnOrder.
- **`STRUCTURE`**: minimal setup — movement, lifecycle, combat, vision only. Returns early. No AI, sound, interaction, inventory, equipment, or cursors. Structures are never registered with TurnOrder and take no autonomous turns.

This means structures can be transitioned to `CharacterRole.PLAYER` in the future (e.g. a "control a tree" powerup) by extending the STRUCTURE branch without touching the rest of the system.

### Child Components

| Node | Script | Responsibility |
|------|--------|---------------|
| `CharacterMovement` | `character_movement.gd` | Grid position, input handling, zone exit |
| `CharacterSprite` | `character_sprite.gd` | Visual mesh; `set_defeated()` swaps texture, spawns blood splatter; `set_texture()` for structures |
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
enum CharacterType { SURGEON, ENEMY, STRUCTURE }
enum CharacterRole { PLAYER, NPC }

# character_interaction.gd
enum InteractionSubState { NONE, MOVE_CURSOR, INTERACTION_MENU, LOOT, COLLECT_LIQUID, INSPECTION, USE_ITEM, DROPPING_ITEM }
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
						   ↓ (spot player mid-investigate: roll)
						 ALERT → COMBAT (chases + attacks)
PATROL (loops independently)
SLEEPING
```

**Transition rules:**
- `PATROL` → `SUSPICIOUS`: player spotted in outer 50% of vision range (yellow `?` popup)
- `PATROL` → `ALERT`: player spotted in inner 50% of vision range (red `!` popup)
- `SUSPICIOUS` → `INVESTIGATE`: always, after 1 turn wait; roll determines likelihood based on spotted distance
- `SUSPICIOUS` → `PATROL`: roll fails (enemy stands down)
- `INVESTIGATE` → `ALERT`: player spotted mid-investigation; roll based on current distance — fail → ALERT (red `!`), pass → update investigate target to player's current position and continue
- `INVESTIGATE` → `RETURN`: reached investigate target or no path found
- `RETURN` → `PATROL`: reached patrol origin or no path found
- `ALERT`: chases player via A*; attacks if adjacent. No exit — persistent until combat resolves.
- Vision check runs after facing update in PATROL, INVESTIGATE, and RETURN branches so the correct facing direction is used.

Incapacitation sets `life_state` to KNOCKED_OUT or DEAD. `behavior_state` retains its last value but is ignored while the enemy is not ALIVE.

### Awareness Popups (`suspicion_label.gd`)

Floating labels spawned above the enemy's head on state transitions:
- `?` (yellow) — enemy becomes SUSPICIOUS
- `!` (red) — enemy becomes ALERT

Uses a fixed `custom_minimum_size.x` for frame-0 centering (avoids the `size.x == 0` issue on the first process frame). Font size and float offset scale with camera zoom to match damage labels.

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
- Reaches enemies in RELAXED/PATROL states only (SUSPICIOUS/INVESTIGATE/ALERT/COMBAT ignore sound)
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
- `chest_contents: Dictionary` — uid → `Array[String]` of item IDs for carried structure items (e.g. a picked-up chest)
- Carry limit: `100.0 + muscle_mod × 5.0` kg
- `_item_weight(index)` — returns base item weight plus contents weight for chest items

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
| `cardio` | Hit accuracy, HP regen, **baseline stroke volume** (+12 mL per stat_mod point) |
| `adrenal` | Damage, crit damage, regen |
| `sympathetic` | Vision range, hit accuracy, parry, bonus turn speed |
| `parasympathetic` | Parry, regen, **post-exertion HR recovery rate** |
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

## 12. Organ Systems

Organ nodes are dynamically instantiated in `character.gd._ready()` for all non-STRUCTURE characters. They are not in the scene file. Each is added as a child and registered in `CharacterOrganRegistry`, which is the single access point for all organ refs. External systems (TurnOrder, cardiovascular) read organs through the registry rather than reaching into character directly.

### CharacterOrganRegistry (`character_organ_registry.gd`)

Holds refs: `renal`, `hypothalamus`, `cardiovascular`, `pulmonary`. Populated immediately after instantiation in `character.gd._ready()`.

### Turn Order Integration

Each player action triggers the organ tick pipeline in `TurnOrder` in this order:

```
1. cardiovascular.tick()   — computes CO, BP, HR; adds exertion fluid cost to renal.pending_plasma_cost
2. pulmonary.tick()        — reads demanded_co → RR/TV/gas exchange → writes SpO2 back to cardiovascular
3. renal.consume_action_cost()  — deducts pending cost from plasma, cascades to compartments
4. renal.tick()            — recalculates concentrations, osmolality, GFR, creatinine
5. hypothalamus.tick()     — reads plasma_osmolality, emits thirst signals
```

Order rationale:
- Cardiovascular ticks first so `demanded_co` and `spo2` are available to pulmonary.
- Pulmonary ticks second so SpO2 is written before renal reads MAP-adjusted CO.
- Renal consumes after both so the full exertion fluid cost (base + CO surcharge) is deducted together.

---

### Renal System (`character_renal.gd`)

Models fluid compartments, plasma solutes, GFR, and creatinine.

**Fluid compartments (mL):**
```
TBW = 60% of body_mass (kg) × 1000
ICF = 2/3 × TBW
ECF = 1/3 × TBW
  interstitial = 3/4 × ECF
  plasma       = 1/4 × ECF
```
Baseline at 75 kg: TBW=45,000 mL, ICF=30,000, ECF=15,000, interstitial=11,250, plasma=3,750.

**Fluid loss per action (`consume_action_cost`):**
1. `plasma_fluid -= pending_plasma_cost` (base 0.434 mL + cardiovascular exertion surcharge)
2. Plasma osmolality rises as plasma shrinks (fixed solute totals, shrinking volume)
3. Elevated ECF osmolality pulls water from ICF proportional to the osmotic gradient
4. ECF redistributes: interstitial stays at 3:1 ratio within ECF

**Plasma solutes (fixed totals, rising concentration as volume falls):**
- `total_plasma_sodium` → `plasma_sodium` (mEq/L)
- `total_plasma_glucose` → `plasma_glucose` (mg/dL)
- `total_plasma_bun` → `plasma_bun` (mg/dL)
- Osmolality: `Posm = 2×Na + glucose/18 + BUN/2.8`

**RPF and GFR** are jointly modulated by plasma volume, MAP, and sympathetic tone:

```
base_RPF = plasma_fluid × 0.176          (660 mL/min at baseline 3750 mL plasma)

sympathetic_suppression = co_excess / (MAX_CO − BASELINE_CO)
rpf_ceiling = lerp(1.0, 0.7, sympathetic_suppression)

if MAP < 70:   map_ratio = MAP / 70        (shock — linear fall to zero)
else:          map_ratio = min(1.0, rpf_ceiling)

RPF = base_RPF × map_ratio
GFR = RPF × filtration_fraction + filtration_correction
```

Three regimes:
- **MAP ≥ 70, at rest** (`demanded_co` = resting): `rpf_ceiling` = 1.0, `map_ratio` = 1.0 → RPF and GFR at full baseline (~130 mL/min). Autoregulation holds regardless of where in the 70–180 range MAP sits.
- **MAP ≥ 70, in combat** (high `demanded_co`): sympathetic vasoconstriction suppresses `rpf_ceiling` toward 0.7 → GFR 90–110 mL/min despite high systemic BP. Blood is redistributed to muscle.
- **MAP < 70** (shock/severe dehydration): no autoregulation — RPF falls linearly to zero, GFR crashes (prerenal azotemia, creatinine rises).

**Creatinine:** steady-state production 0.324 mg/turn; clearance = `GFR × plasma_creatinine × 0.25 min`. Rises when GFR falls.

---

### Hypothalamus (`character_hypothalamus.gd`)

Reads `plasma_osmolality` from renal each tick. Emits signals at threshold crossings:

| Signal | Trigger | Resolves |
|--------|---------|---------|
| `thirst_triggered` | osmolality > 290 | < 287 |
| `dehydrated_triggered` | osmolality > 295 | < 292 |
| `severely_dehydrated_triggered` | osmolality > 310 | < 306 |

---

### Cardiovascular System (`character_cardiovascular.gd`)

Models HR, stroke volume, cardiac output, SVR, and blood pressure from plasma volume and metabolic demand.

**Metabolic demand (`demanded_co`):**
- Actions set a target CO via `set_demand(co: float)` — snaps up instantly if higher than current
- Decays toward `BASELINE_CO` (7.5 L/min) each tick at rate `0.5 + parasympathetic_mod × 0.1` L/min/turn — decay happens at the very end of `tick()`, after all this-turn calculations are complete
- Vagal reactivation (parasympathetic stat) drives post-exertion recovery — higher parasympathetic = faster decay
- `demanded_co_pre_decay` is a snapshot of `demanded_co` taken immediately before the decay step. Pulmonary reads this value (not `demanded_co`) so it sees the demand that actually drove HR this turn, not the already-decayed value

**Action CO demands:**
| Action | demanded_co |
|--------|------------|
| Wait | — (decays toward resting) |
| Walk | 8.0 L/min → HR ≈ 80 bpm |
| Combat bump | 17.0 L/min → HR ≈ 170 bpm, elevated SBP |

**Stroke volume** scales with plasma (Frank-Starling) and cardio stat:
```
SV = (BASELINE_SV_ML + cardio_stat_mod × 12) × plasma_ratio
```
Higher cardio → larger SV → same CO demand met at lower HR. At cardio=16 (mod=+3), SV=136 mL; resting HR drops to 55 bpm, combat HR drops from 150 to 110 bpm. Leveling cardio produces a visibly quieter resting heart rate.

**Heart rate** takes the dominant driver:
```
baroreflex_hr = BASELINE_HR / plasma_ratio   (compensation for hypovolemia)
demand_hr     = demanded_co × 1000 / SV       (metabolic demand)
heart_rate    = max(baroreflex_hr, demand_hr), capped at 180
```

**MAP and BP:**
```
CO  = HR × SV / 1000
SVR = BASELINE_SVR / plasma_ratio   (sympathetic vasoconstriction with dehydration)
MAP = CO × SVR / 80
PP  = 40 × (SV / BASELINE_SV)
DBP = MAP − PP/3
SBP = DBP + PP
```
Baseline values: HR=75, SV=100 mL, CO=7.5 L/min, SVR=1000, MAP=93 mmHg, BP≈120/80.

**Exertion fluid cost:** added to `renal.pending_plasma_cost` each tick:
```
co_excess      = max(0, demanded_co − BASELINE_CO)
co_fraction    = co_excess / (MAX_CO − BASELINE_CO)   # MAX_CO = 20 L/min
co_fluid_cost  = DEFAULT_ACTION_COST_ML × 3.0 × co_fraction
```
Zero at resting, up to 3× base cost (1.302 mL/turn) at max exertion. Stacks on top of the 0.434 mL/turn insensible baseline.

**Cardiovascular → Renal feedback loop:**

Cardiovascular feeds two values into the renal system each tick:
1. `demanded_co` → drives sympathetic suppression of RPF ceiling (combat redistributes blood away from kidneys)
2. `mean_arterial_pressure` → drives RPF map_ratio (shock crushes renal perfusion)

This creates a bidirectional cascade: dehydration drops plasma → drops SV and MAP → raises HR and SVR → sympathetic tone suppresses renal flow → GFR falls → creatinine rises → osmolality climbs → thirst intensifies. Combat accelerates the loop by simultaneously spiking demanded_co and MAP.

---

### Pulmonary System (`character_pulmonary.gd`)

Models lung volumes, respiratory mechanics, alveolar gas exchange (O2/CO2), and oxygenation status. Ported and simplified from the per-frame lung simulation in the GameMaker medical project into a turn-based organ tick.

**Lung volumes** (derived from body mass at 7 mL/kg tidal volume factor):
```
TLC   = tidal_volume / 0.12
RV    = TLC × 0.20
ERV   = TLC × 0.20
IRV   = TLC × 0.50
FRC   = RV + ERV
TV    = body_mass × 7.0 mL/kg
VC    = IRV + TV + ERV
```

**Respiratory rate** scales with metabolic demand:
```
rr_range = (MAX_RR − BASELINE_RR) × (1.0 − cardio_mod × 0.1)
RR = BASELINE_RR + rr_range × co_fraction    (co_fraction = (demanded_co_pre_decay − BASELINE_CO) / (MAX_CO − BASELINE_CO))
```
Reads `cardiovascular.demanded_co_pre_decay` — the pre-decay snapshot — so it sees the demand that drove HR this turn, not the already-decayed value. Higher cardio stat → more efficient ventilation → lower RR for same demand. Pneumothorax adds compensatory tachypnea (×1.5 RR, capped at 40 bpm).

**Gas exchange** (simplified alveolar gas equation):
```
PIO2  = (760 − 47) × 0.21 = 149.7 mmHg
PACO2 = 40 / vent_ratio    (rises with hypoventilation, falls with hyperventilation)
PAO2  = PIO2 − (PACO2 / 0.8)
```
Pneumothorax forces PAO2=50, PACO2=55 (hypoxia + hypercapnia).

**SpO2** derived from PAO2 via simplified oxyhemoglobin dissociation curve:
| PAO2 | SpO2 |
|------|------|
| ≥ 100 mmHg | 99% |
| 60 mmHg | 90% (critical threshold) |
| 27 mmHg | 50% (P50) |

**Vitals wiring:** After each tick, `respiratory_rate` is written to `CharacterVitals.rr` (displayed in the top bar as "RR: N bpm"). `CharacterVitals._refresh_ui()` is called immediately after to update the HUD. Pulmonary receives the vitals node via `setup(organs, levels, vitals)`.

**Cardiovascular feedback:** SpO2 written to `cardiovascular.spo2` each tick. Below 90%, effective CO is reduced linearly (50% CO at SpO2=50%). This means pneumothorax → hypoxia → impaired O2 delivery → effective CO falls despite high HR.

**Disease API:**
- `trigger_pneumothorax(side)` — collapses one lung; TV halved, PAO2=50, tachypnea
- `resolve_pneumothorax()` — needle decompression / chest tube; full volumes restore

---

## 13. Structure System

Structures (trees, chests, and in future: walls, doors, boulders, etc.) are `character.tscn` instances with `CharacterType.STRUCTURE`. They are not tiles — the GridMap cell underneath is always Floor. Structures own their traversal properties directly.

### `data/structures.json`
```json
{
  "id": "military_chest",
  "name": "Military Chest",
  "hp": 50,
  "muscle": 20,
  "description": "A military-issue storage chest.",
  "sprite": "res://assets/images/world_items/chests/spr_chest1.png",
  "sound_dampening": 0,
  "blocks_vision": false,
  "drops": [],
  "contents": ["combat_knife", "field_bandage"],
  "actions": ["Open", "Take Chest"]
}
```

The `actions` array is data-driven — any string listed here appears in the interaction menu for that structure. Adding a new action only requires a new `elif` handler in `_on_tile_action_selected`. No code changes needed to expose it in the menu.

### Structure fields on `character.gd`
| Field | Type | Purpose |
|-------|------|---------|
| `structure_id` | `String` | Matches the `id` in `structures.json` |
| `display_name` | `String` | Human-readable name shown in interaction menus |
| `description` | `String` | Shown in inspect modal |
| `sprite_path` | `String` | Path to sprite texture; stored for inspect modal display |
| `sound_dampening` | `int` | Added to sound wave attenuation when the wave passes through this cell |
| `blocks_vision` | `bool` | Whether LOS rays are stopped at this cell (true for all alive characters by default) |
| `drops` | `Array` | Item IDs added to the attacker's inventory on destruction |
| `structure_actions` | `Array` | Action strings shown in the interaction menu (from `actions` in structures.json) |

### `StructureConfigurator` (`scenes/map/structure_configurator.gd`)
- Reads `structures.json` on `_ready()`
- `spawn_one(id, pos, hp_override, inventory_override)` — instantiates `character.tscn`, sets all structure fields, calls `CharacterSprite.set_texture()`, calls `movement.place()`. Populates `CharacterInventory` from `contents` (fresh spawn) or `inventory_override` (zone restore). Returns the spawned node.
- `scatter_trees(home_rects)` — called by `MapGenerator`; picks random floor cells outside houses
- `scatter_chests(home_interiors)` — called by `MapGenerator`; 50% chance per home interior to spawn a `military_chest`
- Structures are added to the `"structures"` group for zone serialization

### Traversal
- **Movement blocking**: solid registration in `OccupancyMap` — `CharacterMovement._check_move()` sees the structure as a solid occupant and blocks or routes to attack
- **Vision blocking**: `CharacterVision.can_see()` checks `solid.blocks_vision` per cell
- **Sound dampening**: `CharacterSound._build_rings()` adds `solid.sound_dampening` to attenuation per neighbour cell

### Combat against structures
- Requires `pending_target` lock (player must select "Chop" or "Lock On" first)
- `CharacterCombat._apply_damage()` detects `CharacterType.STRUCTURE` and routes to `_apply_damage_to_structure()`
- No evasion, no equipment — fixed DC 10 hit roll; block uses structure's `muscle` stat
- On death: drops are added to attacker inventory, `CharacterLifecycle.die()` calls `queue_free()` (no corpse, no splatter)

### Zone persistence
`WorldState.save_zone_structures()` records `{ id, grid_pos, hp, inventory }` per structure. The `inventory` field is the current item list of the structure's `CharacterInventory`. On re-entry, `MapGenerator` calls `StructureConfigurator.spawn_one()` with `inventory_override`, so looted chests stay looted.

---

## 14. Zone Persistence (`world_state.gd`)

When the player exits a zone:
1. All enemy states are serialized to `off_screen_enemies` (position, AI state, patrol info, stats, HP, inventory with durability/liquids, blood splatter flag)
2. Tile layout, dropped world items, and structure states stored in `zones[zone_id]`
3. On re-entry: `EnemyConfigurator` restores enemies; `MapGenerator` restores tiles and calls `StructureConfigurator` for structures; `ItemConfigurator` restores dropped world items

**Structure persistence** includes inventory (`{ id, grid_pos, hp, inventory }`), so chest contents survive zone transitions.

**World item persistence** (`{ id, local_pos }`) covers items dropped by the player via the drop system. Identified by `item_id` property on the `world_item.gd` script.

Off-screen enemies have patrol movement simulated (1 step/turn) via `tick_off_screen_enemies()`.

---

## 15. Tile System (`tile_registry.gd`)

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

## 16. Data Files

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

### `data/structures.json`
```json
{
  "id": "tree",
  "name": "Oak Tree",
  "hp": 100,
  "muscle": 14,
  "description": "A sturdy oak tree.",
  "sprite": "res://assets/images/tiles/spr_tree1.png",
  "sound_dampening": 1,
  "blocks_vision": true,
  "drops": ["logs"],
  "actions": ["Chop"]
}
```

`actions` is the exhaustive list of interaction menu options for that structure. `"Inspect"`, `"Lock On"`, and `"Unlock Target"` are always appended automatically — do not include them here.

See §13 for full structure system documentation.

### World Items (`scenes/items/world_item.tscn`)

World items are `MeshInstance3D` nodes with `world_item.gd` attached, placed as children of the GridMap at runtime. They represent items dropped by the player.

- Identified by the `item_id: String` property (set on spawn; not `node.name`, which Godot may deduplicate)
- Sprite set via `material_override` (per-instance `StandardMaterial3D`) — never via the shared mesh material
- Detected in `_open_interaction_menu` by `child.get("item_id") != null`
- Picking up: `inventory.add_item(world_item.item_id)` then `queue_free()`
- Zone persistence: `ItemConfigurator.place()` restores them on re-entry from `WorldState`; `SceneLoader` serializes them on zone exit via `child.get("item_id") != null` filter

**Dropping items** (`DROPPING_ITEM` sub-state): selecting "Drop" from the inventory opens the interact cursor. WASD moves it; E confirms the drop. If the item has `chest_contents` (i.e. it is a carried structure), dropping spawns a full structure via `StructureConfigurator.spawn_one()` with the saved contents — not a world item.

---

## 17. UI Systems

| UI Node | Script | Purpose |
|---------|--------|---------|
| `CharacterSheet` | `character_sheet.gd` | Tabbed view: STATS / INVENTORY / EQUIPMENT |
| `LootModal` | `loot_modal.gd` | Lists items from incapacitated enemies, open chests, or carried chest contents |
| `FillModal` | `fill_modal.gd` | Generic action picker; liquid filling; item inspection |
| `TopBar` | — | Live vitals display; updated by `CharacterVitals._refresh_ui()` |

**LootModal notes**: Tab or I while looting suspends the modal (`_loot_interrupted` flag); it restores when the character sheet closes. Taking the corpse item hides the CharacterSprite (the body is "picked up"); blood splatter stays. The modal accepts any node with `items: Array[String]` and `remove_item(id)` — including `ChestInventoryProxy` for viewing carried chest contents.

**ChestInventoryProxy** (`scenes/items/chest_inventory_proxy.gd`): lightweight node that wraps a `chest_contents` entry in `CharacterInventory` with the loot modal's expected interface. `remove_item` syncs removals back to `chest_contents` on the real inventory. Created on demand by `open_chest_contents()` in `CharacterInteraction`, freed when the loot modal closes.

---

## 18. Input Map

| Key | Action |
|-----|--------|
| Arrow keys / WASD | Move / move interaction cursor |
| Space | Wait (pass turn) |
| Tab / I | Open Character Sheet / Inventory |
| C | Toggle Look mode |
| E | Interact with tile / confirm cursor action / confirm drop |
| Q / Escape | Cancel / close modal / cancel drop |
| Mouse wheel | Camera zoom |

---

## 19. Common Patterns

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

## 20. Blood Splatter

Blood splatter is a `MeshInstance3D` named `"BloodSplatter"` added as a child of the Character node on death (by `character_sprite.gd`). It has no script. To find it:

```gdscript
var splatter := character.get_node_or_null("BloodSplatter")
```

The camera is top-down; sprites are horizontal `PlaneMesh` instances. Do **not** rotate sprites on X to show a defeated state — swap the texture instead.

---

## 21. Ownership Rules

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

## 22. Known Limitations and Future Pressure Points

### Scene-name coupling in component lookup — ~~resolved~~

All scene-external refs (GridMap, Camera3D, CanvasLayer, UI modals, TurnOrder) are now injected via `setup()` calls from `character.gd._ready()`. No component hardcodes a scene path to a node outside the character subtree.

Sibling lookups (`get_parent().get_node("CharacterX")`) in component `_ready()` methods are still present but limited to the initialization phase, where they are guaranteed safe. These are the only remaining scene-name dependencies.

---

### Provisional occupancy and pathfinding

`OccupancyMap` (`scenes/map/occupancy_map.gd`) is a child of GridMap that tracks solid and passable occupants per cell. It replaced the scene-tree scan hacks in `CharacterVision.can_see()` and `CharacterMovement._check_move()`.

- **Vision occlusion** — ~~resolved~~. `can_see()` checks `solid.blocks_vision` per cell via OccupancyMap. Dead/KO bodies are passable and do not block LOS. Structures set `blocks_vision` from their data definition.
- **Pathfinding** (`AStarGrid2D`) is still built once in `_ready()` and never updated. It marks unwalkable tiles as solid but does not account for structure entities (trees, future walls). Enemies can pathfind through cells occupied by structures. This is a known placeholder — the fix is to also mark OccupancyMap solid cells as obstacles when building the grid.

---

### CharacterInteraction as a future god object

`CharacterInteraction` is a good extraction now, but player-side UI coordination is the category most likely to re-accumulate complexity. It currently owns: input state, cursor flow, modal restoration, pending actions, target locking, interaction menu construction, and item-use execution. Each of those is individually small; together they can become a second god object.

Watch for the signal that it is happening: functions that check `interaction_sub_state` at the top before doing anything else, or modal open/close sequences that require tracking multiple booleans simultaneously.

**Mitigation path**: if `CharacterInteraction` grows past ~400 lines of real logic, consider splitting cursor/targeting (what the player is pointing at and why) from modal flow (what UI is open and how it restores). Those two concerns are already loosely separable.
