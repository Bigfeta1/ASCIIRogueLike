# Cardiovascular System

**Coordinator:** `scenes/character/organs/character_cardiovascular.gd`

Full cardiac cycle simulation. Tick entry point: `tick(delta: float)` — called from `turn_order.gd` with `delta=0.016` on every player move/wait.

---

## Scene Node Hierarchy

```
CharacterOrgans/
└── CharacterCardiovascular          ← coordinator (character_cardiovascular.gd)
    ├── HeartElectricalSystem        ← plain Node (no script)
    │   ├── AtrialComponents         ← atrial_components.gd
    │   │   ├── SAnode               ← sa_node.gd
    │   │   └── AtrialTract          ← conduction_component.gd  (0.08s)
    │   └── Ventricularcomponents    ← electrical_pathway.gd
    │       ├── AVnode               ← conduction_component.gd  (0.06s)
    │       ├── BundleOfHis          ← conduction_component.gd  (0.01s)
    │       └── PurkinjeFibers       ← conduction_component.gd  (0.02s)
    ├── RightHeart
    │   ├── VenaCava
    │   ├── Atria                    ← cardiac_chamber.gd
    │   │   ├── Myocytes             ← chamber_myocytes.gd  (electrical_source=atrial)
    │   │   └── TricuspidValve       ← cardiac_valve.gd
    │   ├── Ventricle                ← cardiac_chamber.gd
    │   │   ├── Myocytes             ← chamber_myocytes.gd  (electrical_source=ventricular)
    │   │   └── PulmoniclValve       ← cardiac_valve.gd
    │   └── PulmonaryArtery
    └── LeftHeart
        ├── PulmonaryVein
        ├── Atria                    ← cardiac_chamber.gd
        │   ├── Myocytes             ← chamber_myocytes.gd  (electrical_source=atrial)
        │   └── MitralValve          ← cardiac_valve.gd
        ├── Ventricle                ← cardiac_chamber.gd
        │   ├── Myocytes             ← chamber_myocytes.gd  (electrical_source=ventricular)
        │   └── AorticlValve         ← cardiac_valve.gd
        └── Aorta
```

---

## Tick Order

Order matters — each step sees the previous step's output.

```
_atrial.tick(delta)          ← SA node + AtrialTract conduction
_ep.tick(delta)              ← AVnode + BundleOfHis + PurkinjeFibers conduction
_step_heart()                ← SV/EF/CO/MAP/vitals update

la.step_sweep(delta)         ← sweep only if triggered by AtrialComponents.depolarized
ra.step_sweep(delta)
lv.step_sweep(delta)         ← sweep only if triggered by Ventricularcomponents.ventricular_depolarization_started
rv.step_sweep(delta)

lv.step_myocytes(delta)      ← ventricles before atria (LV pressure must be current for valve logic)
rv.step_myocytes(delta)
la.step_myocytes(delta)
ra.step_myocytes(delta)

lv.step_elastance(delta)
rv.step_elastance(delta)
la.step_elastance(delta)
ra.step_elastance(delta)

_step_valves(delta)          ← venous return, all 4 valve ticks, aorta fill
[pressure recompute]         ← all 4 chambers after flow
_step_aorta(delta)           ← Windkessel runoff, dicrotic notch
_step_pulmonary_artery(delta)
```

---

## SA Node

**File:** `scenes/character/organs/sa_node.gd`

**States:** `PHASE_4 → PHASE_0 → PHASE_3`

Membrane potential: `Vm = -130 + ic_na + ic_ca + ic_k`

| Phase | Role |
|---|---|
| PHASE_4 | Slow diastolic depolarization. Na⁺ influx raises Vm toward -40, then Ca²⁺ influx drives it to +10. |
| PHASE_0 | Threshold reached. Emits `fired` signal. Transitions to PHASE_3. |
| PHASE_3 | Repolarization. K⁺ efflux decays. Resets all currents to baseline → back to PHASE_4. |

`force_fire()` — debug helper: sets `Vm=10`, `state=PHASE_0`.

`cardioplegia: bool` — when true, clamps `ic_k=500` (hyperpolarized, no firing).

---

## Electrical Conduction Chain

### ConductionComponent

**File:** `scenes/character/organs/conduction_component.gd`

Generic timer node. All four conduction nodes (AtrialTract, AVnode, BundleOfHis, PurkinjeFibers) share this script.

```
activate()  →  conducting=true, _timer=0
tick(delta) →  _timer += delta; if >= conduction_duration: conducted.emit()
```

| Node | Duration |
|---|---|
| AtrialTract | 0.08s |
| AVnode | 0.06s |
| BundleOfHis | 0.01s |
| PurkinjeFibers | 0.02s |

### AtrialComponents

**File:** `scenes/character/organs/atrial_components.gd`

Coordinator for the atrial electrical system. Wires SA node → AtrialTract → `depolarized`.

```
SAnode.fired ──► AtrialTract.activate()
AtrialTract.conducted ──► depolarized.emit()
```

Ticked by the cardiovascular coordinator: `_atrial.tick(delta)` calls `_sa_node.tick(delta)` and `_atrial_tract.tick(delta)`.

**Signal:** `depolarized` — atria fully activated; triggers myocyte sweeps and starts ventricular chain.

### ElectricalPathway (VentricularComponents)

**File:** `scenes/character/organs/electrical_pathway.gd`

Pure chain coordinator. No state machine.

```
AtrialComponents.depolarized ──► AVnode.activate()
AVnode.conducted             ──► BundleOfHis.activate()
BundleOfHis.conducted        ──► PurkinjeFibers.activate()
PurkinjeFibers.conducted     ──► ventricular_depolarization_started.emit()
```

Ticked by the cardiovascular coordinator: `_ep.tick(delta)` calls tick on all three ventricular conduction nodes.

**Signal:** `ventricular_depolarization_started` — triggers aortic valve latch reset and cycle flag resets.

---

## CardiacChamber

**File:** `scenes/character/organs/cardiac_chamber.gd`

Scene Node. All 4 chambers are separate scene nodes (`LeftHeart/Atria`, `LeftHeart/Ventricle`, `RightHeart/Atria`, `RightHeart/Ventricle`), each with their own `@export` values set in the tscn.

Contains only elastance/pressure logic. All myocyte and sweep logic lives in the child `Myocytes` node (see ChamberMyocytes below).

### Configuration (@export, set in scene)

| Property | Type | Meaning |
|---|---|---|
| `e_min` | float | passive diastolic elastance mmHg/mL |
| `e_max` | float | peak systolic elastance mmHg/mL |
| `e_rise_rate` | float | elastance rise rate /s |
| `e_decay_rate` | float | elastance decay rate /s |
| `v0` | float | dead volume mL (pressure = 0 here) |
| `initial_volume` | float | starting volume mL |
| `valve_open` | bool | outflow valve state — set by CardiacValve |
| `valve_conductance` | float | outflow valve conductance mL/s/mmHg |

### Runtime State (read by coordinator)

| Property | Meaning |
|---|---|
| `volume` | current chamber volume mL |
| `pressure` | `elastance * max(0, volume - v0)` mmHg |
| `elastance` | current E(t) mmHg/mL |

### Delegates

All sweep/myocyte operations delegate to the child `Myocytes` node:

- `step_sweep(delta)` / `step_myocytes(delta)` / `trigger_sweep()` — pass-through to `_myocytes`
- `get_active_force() -> float` — returns `_myocytes.active_force`
- `get_region_count() -> int` — returns `_myocytes.region_count`

### Elastance + Pressure Model

```
normalized_force = _myocytes.active_force / region_count
if normalized_force > 0:
    elastance = min(e_max, elastance + normalized_force * e_rise_rate * delta)
else:
    elastance = max(e_min, elastance - e_decay_rate * delta)

pressure = elastance * max(0, volume - v0)
```

---

## ChamberMyocytes

**File:** `scenes/character/organs/chamber_myocytes.gd`

Scene Node, child of each chamber as `Myocytes`. Owns all action potential phase logic, regional sweep, and electrical source wiring.

### Configuration (@export, set in scene)

| Property | Type | Meaning |
|---|---|---|
| `electrical_source` | enum (atrial=0, ventricular=1) | which signal to listen for |
| `fascicle_count` | int | 1 for atria, 3 for ventricles |
| `regions_per_fascicle` | int | always 3 |
| `sweep_duration` | float | seconds to traverse all fascicles |
| `myocyte_durations[5]` | Array[float] | AP phase durations (phases 0–4) |
| `myocyte_force[5]` | Array[float] | force envelope per phase (0.0–1.0) |

### Self-Wiring in _ready()

Each `ChamberMyocytes` node wires itself to the electrical system on `_ready()` — no external wiring needed:

```
electrical_source == 0 (atrial):
    HeartElectricalSystem/AtrialComponents.depolarized → trigger_sweep()

electrical_source == 1 (ventricular):
    HeartElectricalSystem/Ventricularcomponents.ventricular_depolarization_started → trigger_sweep()
```

### Signals

| Signal | When |
|---|---|
| `region_depolarized(region)` | sweep reaches each region |
| `systole_started` | first region enters CONTRACTION |
| `diastole_started` | last region exits CONTRACTION |

### Electrical Sweep

`trigger_sweep()` — resets all regions to PHASE_4/resting, starts sweep.

`step_sweep(delta)` — fires fascicles sequentially over `sweep_duration`. All regions in a fascicle depolarize simultaneously.

- Atria: 1 fascicle × 3 regions = 3 regions
- Ventricles: 3 fascicles × 3 regions = 9 regions; fascicles fire sequentially

### Myocyte Action Potential Phases

`step_myocytes(delta)` — advances each active region through phases 0→1→2→3→4.

| Phase | Atrial duration | Ventricular duration | Force (atrial/ventricular) |
|---|---|---|---|
| 0 | 0.002s | 0.002s | 0.15 / 0.10 |
| 1 | 0.005s | 0.005s | 0.50 / 0.40 |
| 2 | 0.073s | 0.100s | 1.00 |
| 3 | 0.060s | 0.080s | 0.20 / 0.25 |
| 4 | ∞ (resting) | ∞ | 0.00 |

---

## Chamber Constants

Values set as `@export` in `character.tscn`:

| Chamber | e_min | e_max | e_rise | e_decay | v0 | vol_init | valve_cond | fascicles | sweep |
|---|---|---|---|---|---|---|---|---|---|
| LA | 0.20 | 0.60 | 5.0 | 3.0 | 10 mL | 50 mL | 25.0 | 1 | 0.08s |
| LV | 0.083 | 2.5 | 25.0 | 60.0 | 10 mL | 100 mL | 50.0 | 3 | 0.03s |
| RA | 0.25 | 0.67 | 5.0 | 3.0 | 8 mL | 22 mL | 20.0 | 1 | 0.08s |
| RV | 0.05 | 0.60 | 6.0 | 6.0 | 10 mL | 60 mL | 50.0 | 3 | 0.03s |

---

## CardiacValve

**File:** `scenes/character/organs/cardiac_valve.gd`

Single configurable script shared by all 4 valves. All per-valve behavior is controlled via `@export` flags and floats set in the scene.

### Configuration (@export)

| Property | Default | Meaning |
|---|---|---|
| `contraction_rate` | 0.0 | mL/s active upstream ejection (AV valves only; 0 = semilunar) |
| `open_threshold` | 0.0 | extra mmHg upstream must exceed downstream to open |
| `pressure_clamp_max` | 200.0 | mmHg ceiling on upstream chamber pressure |
| `use_systole_guard` | false | AV valves: guard open/close on ventricular_systole argument |
| `use_latch` | false | aortic: cannot reopen after closing in same beat |
| `use_c_wave` | false | mitral: elastance boost on upstream closure |
| `use_pcwp_detection` | false | mitral: v-wave and y-descent waveform detection |
| `use_waveform_tracking` | false | aortic: SBP/DBP from pressure waveform peak/trough |
| `notch_dip` | 0.0 | aortic: pressure dip on closure (dicrotic notch) |

### Per-Valve Configuration

| Valve | Key exports |
|---|---|
| MitralValve | `contraction_rate=120`, `use_systole_guard=true`, `use_c_wave=true`, `use_pcwp_detection=true` |
| AorticlValve | `open_threshold=2.0`, `use_latch=true`, `use_waveform_tracking=true`, `notch_dip=2.0` |
| TricuspidValve | `contraction_rate=180`, `use_systole_guard=true` |
| PulmoniclValve | `pressure_clamp_max=60.0` |

### Signals

| Signal | When |
|---|---|
| `upstream_closed(volume)` | valve closes — carries EDV (mitral) or ESV (aortic) |
| `waveform_peak(pressure)` | v-wave PCWP peak (mitral) or SBP (aortic) |
| `waveform_trough(pressure)` | y-descent PCWP (mitral) or DBP (aortic) |

### Setup

`setup(upstream: CardiacChamber, downstream: CardiacChamber)` — called from coordinator `setup()`. Semilunar valves pass `null` for downstream (they use `downstream_pressure` float argument instead).

### tick()

`tick(delta, downstream_pressure, ventricular_systole, downstream_valve_open)`

- `downstream_pressure` — aorta_pressure / pulmonary_pressure for semilunar; ignored for AV valves
- `ventricular_systole` — used only by AV valves with `use_systole_guard=true`
- `downstream_valve_open` — used only by mitral with `use_pcwp_detection=true` (needs aortic valve state)

Exposes after tick: `notch_fired: bool`, `flow: float` (eject_flow this tick for semilunar valves).

### Valve Behavior

**AV valves (mitral, tricuspid) — `use_systole_guard=true`:**
- Closes when `ventricular_systole=true` AND `downstream.pressure > upstream.pressure + 1.0`
- Opens when `ventricular_systole=false` AND `downstream.pressure <= upstream.pressure + 1.0`
- Flow when open: active (`contraction_rate × atrial_force × delta`) + passive (`pressure_gradient × conductance × delta`)

**Semilunar valves (aortic, pulmonic) — pure pressure differential:**
- Opens when `upstream.pressure >= downstream_pressure + open_threshold`
- Closes when `upstream.pressure < downstream_pressure`
- Flow when open: `(upstream.pressure - downstream_pressure) × conductance × delta` → stored in `flow`

**C-wave (mitral only — `use_c_wave=true`):**
- On close: `_valve_diameter = 1.0`, begins closing at 33.3/s
- While closing: `la.e_max` boosted by up to +0.30 mmHg/mL
- After full closure: boost decays at 10.0/s
- On reopen: `la.e_max` restored to baseline 0.60

**Aortic latch (`use_latch=true`):**
- `reset_latch()` — called by coordinator on `ventricular_depolarization_started`
- Once latched, valve cannot reopen until next ventricular depolarization

**Waveform tracking (aortic — `use_waveform_tracking=true`):**
- Tracks downstream pressure peak → `waveform_peak(SBP)` on valve close
- Tracks downstream pressure trough → `waveform_trough(DBP)` on valve reopen

**PCWP detection (mitral — `use_pcwp_detection=true`):**
- `waveform_peak(pcwp)` — fired when `upstream.pressure` turns over while mitral closed and aortic closed
- `waveform_trough(pcwp)` — fired when `upstream.pressure` turns over while mitral open

---

## Venous Return

Two reservoir compartments; all returns are pressure-gradient driven.

### Pulmonary Venous Reservoir (LA fill)

| Parameter | Value |
|---|---|
| `pulmonary_venous_volume` | 380 mL initial |
| `PULMONARY_VENOUS_UNSTRESSED` | 300 mL |
| `PULMONARY_VENOUS_COMPLIANCE` | 10 mL/mmHg |
| `PULMONARY_VENOUS_TO_LA_CONDUCTANCE` | 23 mL/(s·mmHg) |

RV ejects into this reservoir via `_pulmonic_valve.flow`. LA draws from it continuously via pressure gradient.

### Systemic Venous Reservoir (RA fill)

| Parameter | Value |
|---|---|
| `systemic_venous_volume` | 3500 mL initial |
| `SYSTEMIC_VENOUS_UNSTRESSED` | 3000 mL |
| `SYSTEMIC_VENOUS_COMPLIANCE` | 50 mL/mmHg |
| `SYSTEMIC_VENOUS_TO_RA_CONDUCTANCE` | 14.3 mL/(s·mmHg) |

Aortic runoff drains here. RA draws from it continuously via pressure gradient.

---

## Aorta — Two-Element Windkessel

`P = (aorta_volume - AORTA_UNSTRESSED_VOLUME) / AORTA_COMPLIANCE`

| Parameter | Value |
|---|---|
| `aorta_volume` | 700 mL initial |
| `AORTA_COMPLIANCE` | 2.0 mL/mmHg |
| `AORTA_UNSTRESSED_VOLUME` | 540 mL → baseline P = (700-540)/2 = 80 mmHg |
| `SYSTEMIC_RESISTANCE` | 1.0 mmHg·s/mL |

Each tick: pressure derived from volume → outflow = `aorta_pressure / SYSTEMIC_RESISTANCE * delta` drains into systemic venous reservoir → pressure rederived → dicrotic notch applied if `_aortic_valve.notch_fired`.

`aorta_blood_flow: bool` — true while aortic valve open.
`aorta_blood_flow_end: bool` — true the tick the aortic valve closes (`notch_fired`).

---

## Pulmonary Artery

Single-compartment pressure variable (no volume model).

Decays at 4.0 mmHg/s when pulmonic valve is closed. Clamped to `[8.0, 30.0]` mmHg.

---

## Derived Heart Metrics

Updated each tick in `_step_heart()`:

| Variable | Source |
|---|---|
| `EDV` | `lv.volume` at mitral closure (`upstream_closed` signal) |
| `ESV` | `lv.volume` at aortic closure (`upstream_closed` signal) |
| `SV` | `EDV - ESV` |
| `EF` | `(SV / EDV) × 100` |
| `cardiac_output` | `(SV × heart_rate) / 1000` |
| `systolic_bp` / `bp_systolic` | aortic valve `waveform_peak` signal |
| `diastolic_bp` / `bp_diastolic` | aortic valve `waveform_trough` signal |
| `mean_arterial_pressure` | `DBP + (SBP - DBP) / 3` |
| `pulse_pressure` | `SBP - DBP` |
| `pcwp` | `la.pressure` (alias, updated at top of `_step_valves`) |

---

## Signals (coordinator-level)

| Signal | When fired |
|---|---|
| `v_wave_peak(pcwp)` | re-emitted from `_mitral_valve.waveform_peak` |
| `y_descent_start(pcwp)` | re-emitted from `_mitral_valve.waveform_trough` |

`beat_initiated` is gone — the SA node now emits `fired` directly to `AtrialComponents`, which drives the chain. The coordinator listens to `_atrial.depolarized` for debug/reset purposes.

---

## Signal Flow — Full Cardiac Cycle

```
SA Node (PHASE_4 slow depolarization)
    │  Vm reaches +10
    ▼
SA Node PHASE_0
    │
    └─► fired ──► AtrialTract.activate()
                      │  0.08s
                      ▼
                  AtrialTract.conducted ──► AtrialComponents.depolarized
                      │
                      ├─► [coordinator: debug print]
                      │
                      ├─► [LA/RA Myocytes.trigger_sweep() — self-wired in _ready()]
                      │       la/ra step_sweep fires regions over sweep_duration
                      │       la/ra myocytes: PHASE_4→0→1→2→3→4
                      │       la/ra elastance rises → la.pressure rises → passive mitral flow
                      │
                      └─► AVnode.activate()
                              │  0.06s
                              ▼
                          AVnode.conducted ──► BundleOfHis.activate()
                              │  0.01s
                              ▼
                          BundleOfHis.conducted ──► PurkinjeFibers.activate()
                              │  0.02s
                              ▼
                          PurkinjeFibers.conducted ──► ventricular_depolarization_started
                              │
                              ├─► [coordinator: reset_latch(), reset_cycle_flags()]
                              │
                              └─► [LV/RV Myocytes.trigger_sweep() — self-wired in _ready()]
                                      lv/rv fascicles fire over 0.03s
                                      lv/rv myocytes: PHASE_0→1→2→3→4 (~0.187s total)
                                      lv elastance rises → lv.pressure rises
                                      lv.pressure > la.pressure → mitral closes (systole guard)
                                      c-wave boost on la.e_max
                                      lv.pressure >= aorta_pressure+2 → aortic valve opens
                                      aortic ejection → aorta_volume rises → systolic_bp
                                      lv myocytes PHASE_3→4, force tapering
                                      lv.pressure < aorta_pressure → aortic valve closes
                                      notch_fired → dicrotic notch applied
                                      waveform_peak(SBP), waveform_trough(DBP)
                                      lv.pressure < la.pressure → mitral opens (diastole)
                                      pcwp v-wave, y-descent
```

---

## Compatibility

Other organs reference these vars from the cardiovascular coordinator:

- `bp_systolic`, `bp_diastolic` — SBP/DBP aliases
- `demanded_co`, `demanded_co_pre_decay`
- `BASELINE_CO = 5.0`, `MAX_CO = 20.0`
- `spo2 = 99.0`
- `set_demand(co)` — sets demanded cardiac output
- `pcwp` — alias for `la.pressure`
- `aorta_blood_flow: bool`, `aorta_blood_flow_end: bool`
- `cardiac_output`, `mean_arterial_pressure`, `pulse_pressure`, `heart_rate`

---

## Debug

- **F12** — toggles cardiovascular debug panel (wired in `character_interaction.gd`)
- **Numpad 4** — calls `force_fire_sa_node()` + 12 manual ticks
- Tick print format:
  ```
  [CARDIO] at=C/. av=C/. his=C/. purk=C/. | LA=...mL p=... mitral=O/X | LV=...mL p=... aortic=O/X aorta=... | RA=...mL p=... | RV=...mL p=... | pulm_v=... sys_v=... | SBP=... DBP=...
  ```
  Where `C` = conducting, `.` = idle.

`force_fire_sa_node()` routes to `_atrial._sa_node.force_fire()`.
`sa_node_cardioplegia` property on coordinator sets `_atrial._sa_node.cardioplegia`.

---

## Accuracy Rating

| Context | Rating |
|---|---|
| Game-ready cardiac model | **high** |
| Simplified physiology simulator | moderate-high |
| Research-grade hemodynamics | not intended |

All 4 chambers share the same time-varying elastance model with regional myocyte activation and sweeping depolarization. Pressure is always emergent from `E(t) * (V - V0)`. All valve open/close is emergent from pressure differentials — no hardcoded phase flags.

### Remaining Limitations

| Limitation | Why it matters |
|---|---|
| Venous return is continuous pressure-gradient, but reservoir capacitance is simplified | real pulmonary/systemic compliance is distributed |
| Pulmonary artery is a single-compartment pressure var (no volume model) | no pulmonary vascular resistance curve |
| No interventricular septal coupling | RV/LV interact mechanically in reality |
| Right heart constants less validated than left heart | right-sided pressures may drift |

---

## Pending

- Feed `lv.volume` EDV/ESV sampling back into `_step_heart` to replace or validate Frank-Starling preload model
- Right heart valve constant tuning
