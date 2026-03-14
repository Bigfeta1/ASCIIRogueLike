# CardiacChamber

**File:** `scenes/character/organs/cardiac_chamber.gd`

`class_name CardiacChamber extends RefCounted`

Reusable class used by all four cardiac chambers (LA, LV, RA, RV). Each instance is configured with chamber-specific constants before `init_regions()` is called. The coordinator (`character_cardiovascular.gd`) owns all four instances and handles everything that requires knowledge of two chambers at once — valve logic, volume transfers, venous return.

---

## Concept

A chamber has three coupled layers:

```
Electrical sweep
	  ↓
Regional myocyte action potentials → mechanical force
	  ↓
Elastance E(t) rises with force, decays without it
	  ↓
pressure = E(t) × max(0, volume − V0)
```

Volume is manipulated externally by the coordinator (inflow from upstream chamber, outflow through valve). Pressure is always a consequence of current volume and elastance — never set directly.

---

## Construction

Set all configuration vars, then call `init_regions()`. Do not call any step functions before `init_regions()`.

```gdscript
var la := CardiacChamber.new()
la.fascicle_count    = 1
la.e_min             = 0.20
# ... all other config ...
la.init_regions()
la.region_depolarized.connect(my_handler)
```

`init_regions()` derives `region_count = fascicle_count * regions_per_fascicle`, allocates the region array, and sets `volume`, `elastance`, `pressure` from initial values.

---

## Configuration Properties

All must be set before `init_regions()`.

### Sweep Structure

| Property | Type | Default | Meaning |
|---|---|---|---|
| `fascicle_count` | int | 1 | Number of fascicles. 1 for atria (single wavefront), 3 for ventricles (anterior, posterior, septal) |
| `regions_per_fascicle` | int | 3 | Myocyte regions per fascicle. Always 3 |
| `sweep_duration` | float | 0.08s | Total time to fire all fascicles. Atria: 0.08s, ventricles: 0.03s |

`region_count` is derived: `fascicle_count × regions_per_fascicle`. Atria = 3 total, ventricles = 9 total.

### Myocyte Action Potential

| Property | Type | Meaning |
|---|---|---|
| `myocyte_durations[5]` | Array[float] | Duration of each AP phase 0–4. Phase 4 = 0.0 (resting, no timer) |
| `myocyte_force[5]` | Array[float] | Normalized force (0.0–1.0) produced during each phase |

### Elastance

| Property | Type | Meaning |
|---|---|---|
| `e_min` | float | Passive diastolic elastance mmHg/mL. Chamber pressure at rest |
| `e_max` | float | Peak systolic elastance mmHg/mL. Ceiling during active contraction |
| `e_rise_rate` | float | /s. How fast elastance rises when regions are contracting |
| `e_decay_rate` | float | /s. How fast elastance falls when no regions are contracting |

### Volume

| Property | Type | Meaning |
|---|---|---|
| `v0` | float | Dead volume mL. `pressure = 0` when `volume = v0` |
| `initial_volume` | float | Starting volume set by `init_regions()` |

### Valve

| Property | Type | Meaning |
|---|---|---|
| `valve_open` | bool | Outflow valve state. Set by coordinator each tick |
| `valve_conductance` | float | mL/s/mmHg. Used by coordinator for passive flow calculations |

---

## Runtime State (read-only for external code)

| Property | Meaning |
|---|---|
| `region_count` | Total regions = `fascicle_count × regions_per_fascicle` |
| `volume` | Current chamber volume mL. Written by coordinator |
| `elastance` | Current E(t) mmHg/mL. Written by `step_elastance()` |
| `pressure` | `elastance × max(0, volume − v0)`. Always derived |
| `in_systole` | True if any region is mechanically CONTRACTION |
| `sweep_active` | True while depolarization wave is propagating |

---

## Per-Tick Call Order

The coordinator calls these in this order each tick:

```
chamber.step_sweep(delta)      — advance depolarization wave
chamber.step_myocytes(delta)   — advance AP phases, get active force
chamber.step_elastance(delta)  — update E(t) from force, derive pressure
```

`step_myocytes` must run before `step_elastance` so mechanical states are current when elastance is computed.

---

## Electrical Sweep

### `trigger_sweep()`

Called by the coordinator when the EP pathway delivers a depolarization signal:
- Atria: triggered on `beat_initiated`
- Ventricles: triggered on EP transition to `VENTRICULAR_DEPOLARIZATION`

Resets all regions to PHASE_4 / RELAXATION, then starts the sweep.

### `step_sweep(delta)`

Advances the sweep timer. Fires fascicles sequentially — all regions in a fascicle depolarize simultaneously when their fascicle's time slot is reached.

```
time_per_fascicle = sweep_duration / fascicle_count

For each fascicle when timer elapses:
    for each region in fascicle:
        region.myocyte    = PHASE_0
        region.mechanical = CONTRACTION
        emit region_depolarized(region_index)
```

Uses a `while` loop so multiple fascicles can fire in the same delta if needed.

**Atria (fascicle_count=1):** All 3 regions fire at once at `sweep_duration = 0.08s`.

**Ventricles (fascicle_count=3):** Fascicle 0 fires at `0.01s`, fascicle 1 at `0.02s`, fascicle 2 at `0.03s` — modeling apex-to-base Purkinje activation.

---

## Myocyte Action Potential

### `step_myocytes(delta) → float`

Advances each non-resting region through its AP phases. Returns the summed active force across all regions this tick — the coordinator uses this to compute active contraction volume transfer.

**Phase progression:**

```
PHASE_0 → PHASE_1 → PHASE_2 → PHASE_3 → PHASE_4

Each phase advances when myocyte_timer >= myocyte_durations[phase].
PHASE_3 → PHASE_4: mechanical state set to RELAXATION.
PHASE_4: resting, skipped entirely each tick.
```

**Force per region:** `myocyte_force[current_phase]`. Summed across all active regions and returned.

After advancing all regions, calls `_update_systole_state()` which sets `in_systole` and emits `systole_started` / `diastole_started` on transitions.

### Atrial vs Ventricular AP Durations

| Phase | Atrial | Ventricular | Notes |
|---|---|---|---|
| 0 | 0.002s | 0.002s | Fast Na⁺ depolarization |
| 1 | 0.005s | 0.005s | Transient K⁺ outward |
| 2 | 0.073s | 0.100s | Ca²⁺ plateau — ventricular plateau is longer |
| 3 | 0.060s | 0.080s | K⁺ repolarization |
| 4 | ∞ | ∞ | Resting |

Ventricular total active time ≈ 0.187s, spanning the full `ep_cardiac_phase1` window (VENTRICULAR_DEPOLARIZATION + EARLY_REPOLARIZATION + T_WAVE = 0.21s).

### Force Envelope

| Phase | Atrial force | Ventricular force | Notes |
|---|---|---|---|
| 0 | 0.15 | 0.10 | Depolarization just beginning |
| 1 | 0.50 | 0.40 | Rising |
| 2 | 1.00 | 1.00 | Peak plateau |
| 3 | 0.20 | 0.25 | Tapering off |
| 4 | 0.00 | 0.00 | Resting |

---

## Elastance + Pressure

### `step_elastance(delta)`

Reads the current mechanical state of all regions, computes a normalized force, then drives elastance up or lets it decay:

```
active_force    = sum of myocyte_force[phase] for all CONTRACTION regions
normalized_force = active_force / region_count

if normalized_force > 0:
    elastance = min(e_max, elastance + normalized_force × e_rise_rate × delta)
else:
    elastance = max(e_min, elastance - e_decay_rate × delta)

pressure = elastance × max(0, volume - v0)
```

Normalization by `region_count` means a chamber with all regions contracting at peak force (normalized=1.0) rises at the full `e_rise_rate`. Partial activation rises proportionally.

`pressure` is updated at the end of every `step_elastance` call — always current.

### Why elastance and not compliance

All four chambers use the same time-varying elastance model. Compliance curves (like the old LA exponential) are a diastolic-only simplification. Elastance handles both systole and diastole cleanly: low E(t) at rest gives a compliant chamber, high E(t) during contraction gives a stiff pressurized one. The same math works whether the chamber is thin-walled (RA) or thick-walled (LV) — just different constants.

---

## Signals

| Signal | When |
|---|---|
| `region_depolarized(region: int)` | `step_sweep` fires a region |
| `systole_started` | First region enters CONTRACTION (transition from all-relaxed) |
| `diastole_started` | Last region exits CONTRACTION (transition to all-relaxed) |

Signals are on the chamber instance. Connect in `_init_chambers()` during character initialization.

---

## What CardiacChamber Does NOT Do

- No valve logic — the coordinator compares upstream and downstream pressures and sets `valve_open`
- No volume transfer — the coordinator writes to `chamber.volume` directly
- No venous return — coordinator adds to `chamber.volume` each tick
- No knowledge of other chambers — fully decoupled
- No signals to the coordinator about pressure thresholds — coordinator reads `chamber.pressure` directly

---

## Chamber Configurations

| | LA | LV | RA | RV |
|---|---|---|---|---|
| `fascicle_count` | 1 | 3 | 1 | 3 |
| `regions_per_fascicle` | 3 | 3 | 3 | 3 |
| `region_count` | 3 | 9 | 3 | 9 |
| `sweep_duration` | 0.08s | 0.03s | 0.08s | 0.03s |
| `e_min` | 0.20 | 0.10 | 0.25 | 0.05 |
| `e_max` | 0.60 | 2.50 | 0.67 | 0.60 |
| `e_rise_rate` | 5.0 | 30.0 | 5.0 | 15.0 |
| `e_decay_rate` | 3.0 | 8.0 | 3.0 | 6.0 |
| `v0` | 10 mL | 10 mL | 8 mL | 10 mL |
| `initial_volume` | 35 mL | 100 mL | 28 mL | 100 mL |
| `valve_conductance` | 25.0 | 3.0 | 20.0 | 3.0 |
| `valve` | mitral | aortic | tricuspid | pulmonic |

**Rationale for e_min differences:**
- LV (0.10) is the most compliant at rest — it must accept large volumes at low filling pressure
- RA (0.25) is slightly stiffer than LA — thinner wall, less reservoir function
- RV (0.05) is the most compliant — very thin wall, handles high volume at very low pressure

**Rationale for e_max differences:**
- LV (2.50) is by far the stiffest at peak — must generate 120+ mmHg systolic pressure
- RV (0.60) and LA (0.60) are similar — generate ~25 mmHg and ~12 mmHg peak respectively
- RA (0.67) is slightly higher than LA — smaller volume so same pressure requires higher E
