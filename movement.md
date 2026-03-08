# Grid Movement

## Scene structure

`main_scene.tscn` contains:
- `GridMap` — uses `TileMeshLibrary.tres`, `cell_size = Vector3(5, 5, 5)`. Can be positioned anywhere in the editor without breaking character logic.
- `Character` — a `MeshInstance3D` with `character.gd` attached.

## How GridMap works

The GridMap is a single node — there are no child nodes per tile.
Every tile is a record in one flat `PackedInt32Array`.
Each tile is uniquely identified by its `(x, z)` integer cell coordinates — that is how a tile at top-left `(-5, -8)` is told apart from one at bottom-right `(10, 6)`.

The array stores every placed tile as a triplet: `(x, z, encoded_item)`.
`encoded_item` encodes which mesh from the MeshLibrary to render there.
We only have one mesh: item ID `0`, named `"Tile"`, a flat `PlaneMesh`.

Negative coordinates are stored as unsigned 16-bit wraparound: `x=-1` → `65535`, `x=-2` → `65534`.
This is internal serialization only — `get_cell_item(Vector3i(-1, 0, -1))` works as expected in code.

## How the character communicates with the grid

The character holds `grid_pos: Vector2i` — the cell it currently occupies.
It gets a reference to the GridMap in `_ready` and uses the GridMap's own methods for all coordinate conversion.
This means the GridMap can be moved or resized in the editor without breaking character placement.

## Initialization

On `_ready`, the character starts at cell `(0, 0)` and immediately snaps to it:

```gdscript
_grid_map = get_parent().get_node("GridMap")
grid_pos = Vector2i.ZERO
_snap()
```

## Snapping to a cell center

`map_to_local` converts a cell coordinate to a position in the GridMap's local space.
`to_global` converts that local position to world space, accounting for wherever the GridMap is placed in the scene.

```gdscript
func _snap() -> void:
	var local := _grid_map.map_to_local(Vector3i(grid_pos.x, 0, grid_pos.y))
	var world := _grid_map.to_global(local)
	position.x = world.x
	position.z = world.z
```

Y is never changed — the character stays at its scene height.

## Input

`_unhandled_input` is used so UI can consume input first if needed.
`ui_*` actions are skipped — Godot only maps them to arrow keys by default, not WASD.
`event.echo` is filtered out so holding a key does not repeat movement.

```gdscript
if not event is InputEventKey or not event.pressed or event.echo:
	return
match event.keycode:
	KEY_D, KEY_RIGHT: _try_move(Vector2i(1, 0))   # +X
	KEY_A, KEY_LEFT:  _try_move(Vector2i(-1, 0))  # -X
	KEY_S, KEY_DOWN:  _try_move(Vector2i(0, 1))   # +Z
	KEY_W, KEY_UP:    _try_move(Vector2i(0, -1))  # -Z
```

Grid X maps to world X.
Grid Y maps to world Z.
One keypress = one cell.
