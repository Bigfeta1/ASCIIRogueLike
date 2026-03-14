# Cardiovascular System

**Files:**
- `scenes/character/organs/character_cardiovascular.gd` — coordinator: SA node, EP pathway, valve logic, volume transfers, aorta, pulmonary artery
- `scenes/character/organs/cardiac_chamber.gd` — reusable chamber class (all 4 chambers)

Full cardiac cycle simulation. Tick entry point: `tick(delta: float)` — called from `turn_order.gd` with `delta=0.016` on every player move/wait.

---

## Tick Order

Order matters — each step sees the previous step's output.

```
_step_sa_node(delta)
_step_electrical_pathway(delta)
_step_heart()
la.step_sweep(delta)       ← triggered on beat_initiated
ra.step_sweep(delta)
lv.step_sweep(delta)       ← triggered on VENTRICULAR_DEPOLARIZATION
rv.step_sweep(delta)
lv.step_myocytes(delta)    ← ventricles before atria (LV pressure must be current for valve logic)
rv.step_myocytes(delta)
la.step_myocytes(delta)
ra.step_myocytes(delta)
lv.step_elastance(delta)
rv.step_elastance(delta)
la.step_elastance(delta)
ra.step_elastance(delta)
_step_valves(delta)        ← all 4 valves + volume transfers + PCWP waveform detection
_step_aorta(delta)
_step_pulmonary_artery(delta)
```

---

## CardiacChamber

**File:** `scenes/character/organs/cardiac_chamber.gd`

All 4 chambers are instances of `CardiacChamber` (RefCounted). The coordinator holds `la`, `lv`, `ra`, `rv`.

### Configuration (set before `init_regions()`)

| Property | Type | Meaning |
|---|---|---|
| `fascicle_count` | int | 1 for atria, 3 for ventricles |
| `regions_per_fascicle` | int | always 3 |
| `sweep_duration` | float | seconds to traverse all fascicles |
| `myocyte_durations[5]` | Array[float] | AP phase durations (phases 0–4) |
| `myocyte_force[5]` | Array[float] | force envelope per phase (0.0–1.0) |
| `e_min` | float | passive diastolic elastance mmHg/mL |
| `e_max` | float | peak systolic elastance mmHg/mL |
| `e_rise_rate` | float | elastance rise rate /s |
| `e_decay_rate` | float | elastance decay rate /s |
| `v0` | float | dead volume mL (pressure = 0 here) |
| `initial_volume` | float | starting volume mL |
| `valve_conductance` | float | outflow valve conductance mL/s/mmHg |

### Runtime State (read by coordinator)

| Property | Meaning |
|---|---|
| `volume` | current chamber volume mL |
| `pressure` | `elastance * max(0, volume - v0)` mmHg |
| `elastance` | current E(t) mmHg/mL |
| `in_systole` | true if any region is in CONTRACTION |
| `valve_open` | outflow valve state — set by coordinator |

### Signals

| Signal | When |
|---|---|
| `region_depolarized(region)` | sweep reaches each region |
| `systole_started` | first region enters CONTRACTION |
| `diastole_started` | last region exits CONTRACTION |

### Electrical Sweep

`trigger_sweep()` — resets all regions to PHASE_4/RELAXATION, starts sweep.

`step_sweep(delta)` — advances sweep timer. Fires fascicles sequentially; all regions in a fascicle depolarize simultaneously. Each fired region: myocyte→PHASE_0, mechanical→CONTRACTION, emits `region_depolarized`.

- Atria: 1 fascicle × 3 regions = 3 regions total
- Ventricles: 3 fascicles × 3 regions = 9 regions total; fascicles fire sequentially over `sweep_duration`

### Myocyte Action Potential

`step_myocytes(delta)` — advances each active region through phases 0→1→2→3→4. Returns summed active force (used by coordinator for active contraction volume transfer). On PHASE_3→4: mechanical→RELAXATION.

| Phase | Atrial duration | Ventricular duration | Force |
|---|---|---|---|
| 0 | 0.002s | 0.002s | 0.15 / 0.10 |
| 1 | 0.005s | 0.005s | 0.50 / 0.40 |
| 2 | 0.073s | 0.100s | 1.00 |
| 3 | 0.060s | 0.080s | 0.20 / 0.25 |
| 4 | ∞ (resting) | ∞ | 0.00 |

### Elastance + Pressure Model

`step_elastance(delta)` — sums active force across all contracting regions, normalizes by `region_count`, drives elastance up or lets it decay:

```
normalized_force = active_force / region_count
if normalized_force > 0:
    elastance = min(e_max, elastance + normalized_force * e_rise_rate * delta)
else:
    elastance = max(e_min, elastance - e_decay_rate * delta)

pressure = elastance * max(0, volume - v0)
```

This replaces both the old LA compliance curve and the old LV `ep_cardiac_phase1` flat elastance ramp. Pressure is always fully emergent from volume and elastance.

---

## Chamber Constants

| Chamber | e_min | e_max | e_rise | e_decay | v0 | vol_init | fascicles | sweep |
|---|---|---|---|---|---|---|---|---|
| LA | 0.20 | 0.60 | 5.0 | 3.0 | 10 mL | 35 mL | 1 | 0.08s |
| LV | 0.10 | 2.50 | 30.0 | 8.0 | 10 mL | 100 mL | 3 | 0.03s |
| RA | 0.25 | 0.67 | 5.0 | 3.0 | 8 mL | 28 mL | 1 | 0.08s |
| RV | 0.05 | 0.60 | 15.0 | 6.0 | 10 mL | 100 mL | 3 | 0.03s |

---

## SA Node

**States:** `PHASE_4 → PHASE_0 → PHASE_3`

Membrane potential: `Vm = -130 + ic_na + ic_ca + ic_k`

| Phase | Role |
|---|---|
| PHASE_4 | Slow diastolic depolarization. Na⁺ influx raises Vm toward -40, then Ca²⁺ influx drives it to +10. |
| PHASE_0 | Threshold reached. Fires `beat_initiated` signal. Transitions to PHASE_3. |
| PHASE_3 | Repolarization. K⁺ efflux decays. Resets all currents to baseline → back to PHASE_4. |

`force_fire_sa_node()` — debug helper: sets `Vm=10`, `sa_state=PHASE_0`.

---

## Electrical Pathway

**States:** `ATRIAL_DEPOLARIZATION → AV_DELAY → VENTRICULAR_DEPOLARIZATION → EARLY_REPOLARIZATION → T_WAVE → ISOVOLUMETRIC_RELAXATION → DIASTOLIC_FILLING`

Delta-based timer. One state advance per tick.

| State | Duration | Notes |
|---|---|---|
| ATRIAL_DEPOLARIZATION | 0.08s | Triggers `la.trigger_sweep()` and `ra.trigger_sweep()` |
| AV_DELAY | 0.06s | AV node conduction delay |
| VENTRICULAR_DEPOLARIZATION | 0.03s | QRS; `ep_cardiac_phase1 = true`; triggers `lv.trigger_sweep()` and `rv.trigger_sweep()` |
| EARLY_REPOLARIZATION | 0.03s | ST segment |
| T_WAVE | 0.15s | Ventricular repolarization |
| ISOVOLUMETRIC_RELAXATION | 0.03s | Both valves closed; elastance decays; resets `_v_wave_emitted` |
| DIASTOLIC_FILLING | 0.21s | Mitral opens; LV fills; resets `_y_descent_emitted` |

**Key flags:**
- `ep_cardiac_phase1` — true during VENTRICULAR_DEPOLARIZATION, EARLY_REPOLARIZATION, T_WAVE
- `ep_cycle_reset` — true for exactly one tick at end of DIASTOLIC_FILLING
- `ep_running` — false until `beat_initiated` fires; set false again at cycle end

---

## Valves + Volume Transfer (`_step_valves`)

All valve logic lives in the coordinator. Chambers are dumb — they expose `valve_open` (bool) which the coordinator sets each tick.

### Venous Return

- Pulmonary veins → LA: `120.0 mL/s` when `ep_cardiac_phase1` (reservoir phase), `50.0 mL/s` otherwise
- Systemic veins → RA: `40.0 mL/s` / `30.0 mL/s` same logic

### Mitral Valve (LA → LV)

**Close condition:** inside ventricular closure phases (`VENTRICULAR_DEPOLARIZATION`, `EARLY_REPOLARIZATION`, `T_WAVE`) AND `lv.pressure > la.pressure + 1.0`

**Open condition:** outside ventricular closure phases — resets `_mitral_valve_diameter = 1.0`, clears c-wave boost

When open, two flow components:
1. **Active** — sum of LA regional forces drives `LA_CONTRACTION_RATE = 250.0 mL/s` proportionally
2. **Passive** — `(la.pressure - lv.pressure) * la.valve_conductance * delta` (conductance = 25.0 mL/s/mmHg)

Both flows clamp against `la.volume - la.v0`.

### C-Wave (mitral closure transient)

Modeled as a transient boost to `la.e_max` rather than a direct pressure addition — keeps the pressure model physically consistent.

1. On mitral close: `_mitral_valve_diameter = 1.0`, `_c_wave_boost = 0.0`
2. Diameter decrements at `MITRAL_CLOSE_RATE = 33.3/s` → fully closed in ~0.03s
3. While closing: `_c_wave_boost = C_WAVE_ELASTANCE_BOOST * (1 - diameter)` → peaks at +0.30 mmHg/mL on `la.e_max`
4. After full closure: boost decays at `C_WAVE_DECAY_RATE = 10.0/s`
5. `la.e_max` restored to 0.60 on mitral open

### Aortic Valve (LV → aorta)

Opens emergently when `lv.pressure >= aorta_pressure`, closes when it falls below.

Ejection flow: `(lv.pressure - aorta_pressure) * lv.valve_conductance * delta` (conductance = 3.0), capped at `lv.volume - lv.v0`. Ejected volume raises `aorta_pressure` at 0.5 mmHg/mL.

### Tricuspid Valve (RA → RV)

Same pattern as mitral — closes during ventricular closure when `rv.pressure > ra.pressure + 1.0`, opens outside it. Active + passive flow.

### Pulmonic Valve (RV → pulmonary artery)

Same pattern as aortic — opens when `rv.pressure >= pulmonary_pressure`, closes when it falls below. Ejected volume raises `pulmonary_pressure` at 0.1 mmHg/mL.

---

## Aorta

Pressure decays at 25.0 mmHg/s when aortic valve closed. Clamped to `[diastolic_bp, systolic_bp]` (from `_step_heart`).

`aorta_blood_flow` — true while aortic valve open
`aorta_blood_flow_end` — true when valve just closed during `ep_cardiac_phase1`

## Pulmonary Artery

Pressure decays at 4.0 mmHg/s when pulmonic valve closed. Clamped to `[8.0, 30.0]` mmHg.

---

## PCWP

`pcwp` on the coordinator is an alias: updated to `la.pressure` at the top of `_step_valves` each tick. Used for signal payloads and external readers.

### V-wave and Y-descent detection

Both are waveform-detected (not phase-tagged) inside `_step_valves`:

- **v_wave_peak**: fired when `pcwp < _pcwp_prev` while mitral is closed and outside `ep_cardiac_phase1` — PCWP peak as LA fills against closed mitral
- **y_descent_start**: fired when `pcwp < _pcwp_prev` while mitral just opened — LA begins draining into LV

---

## Signals (coordinator-level)

| Signal | When fired |
|---|---|
| `beat_initiated` | SA node PHASE_0 threshold reached |
| `v_wave_peak(pcwp)` | PCWP turns over after systolic rise |
| `y_descent_start(pcwp)` | PCWP falls after mitral opens |

Chamber-level signals (`region_depolarized`, `systole_started`, `diastole_started`) are on each `CardiacChamber` instance. The coordinator connects to `la.region_depolarized` for debug prints.

All connections established in `_ready()` (coordinator self-signals) or `_init_chambers()` (chamber signals), called from `setup()` during character initialization.

---

## Signal Flow — Full Cardiac Cycle

```
SA Node (PHASE_4 slow depolarization)
    │
    │  Vm reaches +10
    ▼
SA Node PHASE_0
    │
    ├─► beat_initiated ──────────────────────────────────────────────────────┐
    │                                                                         │
    ▼                                                                         ▼
SA Node PHASE_3 (repolarize, reset)              _on_beat_initiated()
                                                      │
                                                      ├─► _ep_transition(ATRIAL_DEPOLARIZATION)
                                                      ├─► la.trigger_sweep()
                                                      └─► ra.trigger_sweep()

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EP: ATRIAL_DEPOLARIZATION (0.08s)
    │
    │  la.step_sweep(delta) fires regions 0,1,2
    │      │
    │      └─► la.region_depolarized(0) → _on_la_region_depolarized (debug print)
    │          la.region_depolarized(1) → _on_la_region_depolarized
    │          la.region_depolarized(2) → _on_la_region_depolarized
    │          (ra fires same pattern, no handler connected)
    │
    │  la/ra myocytes: PHASE_4 → 0 → 1 → 2 → 3 → 4
    │  la/ra elastance rises → la.pressure rises → passive mitral flow LA→LV
    │
    │  0.08s elapsed
    ▼
EP: AV_DELAY (0.06s)
    │  (atrial myocytes finishing, elastance decaying back toward e_min)
    │
    │  0.06s elapsed
    ▼
EP: VENTRICULAR_DEPOLARIZATION (0.03s)
    │
    ├─► ep_cardiac_phase1 = true
    ├─► lv.trigger_sweep()   (3 fascicles fire over 0.03s)
    │       └─► lv.region_depolarized(0..8) — 9 regions armed
    └─► rv.trigger_sweep()
    │
    │  lv/rv myocytes: PHASE_0→1→2→3→4 (~0.187s total)
    │  lv elastance rises → lv.pressure rises
    │  lv.pressure > la.pressure+1 → mitral closes → c-wave boost on la.e_max
    │  lv.pressure >= aorta_pressure → aortic valve opens → ejection begins
    │
    │  0.03s elapsed
    ▼
EP: EARLY_REPOLARIZATION (0.03s)
    │  ep_cardiac_phase1 = true
    │  lv ejecting, elastance near e_max
    │
    │  0.03s elapsed
    ▼
EP: T_WAVE (0.15s)
    │  ep_cardiac_phase1 = true
    │  lv myocytes entering PHASE_3→4, force tapering
    │  elastance decaying, lv.pressure falling
    │  lv.pressure < aorta_pressure → aortic valve closes
    │
    │  0.15s elapsed
    ▼
EP: ISOVOLUMETRIC_RELAXATION (0.03s)
    │
    ├─► ep_cardiac_phase1 = false
    ├─► _v_wave_emitted = false   (arm v-wave detection)
    │
    │  lv elastance decaying → lv.pressure falling
    │  la filling from pulmonary veins → la.pressure rising
    │  _step_valves detects: pcwp < _pcwp_prev while mitral closed
    │      └─► v_wave_peak.emit(pcwp)
    │
    │  0.03s elapsed
    ▼
EP: DIASTOLIC_FILLING (0.21s)
    │
    ├─► _y_descent_emitted = false   (arm y-descent detection)
    │
    │  ventricular_closure = false → mitral opens
    │  la.pressure > lv.pressure → passive flow LA→LV
    │  _step_valves detects: pcwp < _pcwp_prev while mitral open
    │      └─► y_descent_start.emit(pcwp)
    │
    │  0.21s elapsed
    ▼
ep_cycle_reset = true, ep_running = false

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SA Node has been slow-depolarizing this whole time → next beat_initiated fires
```

**Key observations:**
- `beat_initiated` is the only signal that escapes the SA node — everything else is direct function calls or internal state transitions
- The 3 coordinator-level signals (`beat_initiated`, `v_wave_peak`, `y_descent_start`) are the only ones external organs can subscribe to
- Chamber signals (`region_depolarized`, `systole_started`, `diastole_started`) are self-contained — only the debug print handler is connected to `la.region_depolarized` currently
- The c-wave has no signal — it is a side effect of mitral closure detected inside `_step_valves`

---

## Compatibility

Other organs reference these vars from the cardiovascular coordinator:

- `bp_systolic`, `bp_diastolic` — aliases for `systolic_bp`/`diastolic_bp`
- `demanded_co`, `demanded_co_pre_decay`
- `BASELINE_CO = 5.0`, `MAX_CO = 20.0`
- `spo2 = 99.0`
- `set_demand(co)` — sets demanded cardiac output
- `pcwp` — alias for `la.pressure`

---

## Debug

- **F12** — toggles cardiovascular debug panel (wired in `character_interaction.gd`)
- **Numpad 4** — calls `force_fire_sa_node()` + 12 manual ticks
- Tick print format:
  ```
  EP=... SA=... | LA=...mL p=...mmHg mitral=O/X | LV=...mL p=... aortic=O/X | RA=...mL p=... | RV=...mL p=...
  ```

---

## Accuracy Rating

| Context | Rating |
|---|---|
| Game-ready cardiac model | **high** |
| Simplified physiology simulator | moderate-high |
| Research-grade hemodynamics | not intended |

All 4 chambers now share the same time-varying elastance model with regional myocyte activation and sweeping depolarization. Pressure is always emergent from `E(t) * (V - V0)`.

### Remaining Limitations

| Limitation | Why it matters |
|---|---|
| Frank-Starling preload still used for CO/SV in `_step_heart` | lv.volume not yet feeding back into SV/EF/CO calculation |
| Venous return is phase-switched, not continuous | real return is more continuous |
| Mitral/tricuspid reopening is partly phase-permissive | not purely pressure-gradient governed |
| Pulmonary artery is a single-compartment pressure var | no pulmonary vascular resistance model |
| No interventricular septal coupling | RV/LV interact mechanically in reality |

---

## Pending

- Feed `lv.volume` EDV/ESV sampling back into `_step_heart` to replace Frank-Starling preload model
- Right heart valve logic is functional but constants are less validated than left heart
