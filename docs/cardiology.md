# Cardiovascular System

**Coordinator:** `scenes/character/organs/character_cardiovascular.gd`

Full cardiac cycle simulation. Entry point: `tick_turn()` — called once per player action (move or wait) from `character_organ_registry.gd`. Internally runs 750 simulation steps at `SIM_STEP=0.020s` over `TURN_DURATION=15s`. Each step calls `tick(0.020)`.

---

## Scene Node Hierarchy

```
CharacterOrgans/
└── CharacterCardiovascular          ← coordinator (character_cardiovascular.gd)
	├── CardiacMonitor               ← cardiac_monitor.gd  (sampled/derived metrics — snapshot only)
	├── HeartElectricalSystem        ← plain Node (no script)
	│   ├── AtrialComponents         ← atrial_components.gd
	│   │   ├── SAnode               ← sa_node.gd
	│   │   └── AtrialTract          ← conduction_component.gd  (0.08s)
	│   └── Ventricularcomponents    ← electrical_pathway.gd
	│       ├── AVnode               ← conduction_component.gd  (0.06s)
	│       ├── BundleOfHis          ← conduction_component.gd  (0.01s)
	│       └── PurkinjeFibers       ← conduction_component.gd  (0.02s)
	├── RightHeart
	│   ├── VenaCava                 ← vena_cava.gd
	│   ├── Atria                    ← cardiac_chamber.gd
	│   │   ├── Myocytes             ← chamber_myocytes.gd  (electrical_source=atrial)
	│   │   └── TricuspidValve       ← cardiac_valve.gd
	│   ├── Ventricle                ← cardiac_chamber.gd
	│   │   ├── Myocytes             ← chamber_myocytes.gd  (electrical_source=ventricular)
	│   │   └── PulmoniclValve       ← cardiac_valve.gd
	│   └── PulmonaryArtery          ← pulmonary_artery.gd
	└── LeftHeart
		├── PulmonaryVein            ← pulmonary_vein.gd
		├── Atria                    ← cardiac_chamber.gd
		│   ├── Myocytes             ← chamber_myocytes.gd  (electrical_source=atrial)
		│   └── MitralValve          ← cardiac_valve.gd
		├── Ventricle                ← cardiac_chamber.gd
		│   ├── Myocytes             ← chamber_myocytes.gd  (electrical_source=ventricular)
		│   └── AorticlValve         ← cardiac_valve.gd
		└── Aorta                    ← aorta.gd
```

---

## tick_turn() Flow

Called once per player action. Runs the full turn simulation then updates sympathetic tone.

```
tick_turn():
	for 750 steps (15s / 0.020s):
		if _beat_phase >= 1.0:
			sa_node.force_fire()     ← triggers beat at computed HR
			_beat_phase -= 1.0
		tick(0.020)
		_beat_phase += SIM_STEP / (60.0 / heart_rate)
	_apply_sympathetic_tone()        ← reads CO from completed beats, updates params for next turn
```

## tick(delta) Order

Order matters — each step sees the previous step's output.

```
_atrial.tick(delta)          ← SA node + AtrialTract conduction
_ventricular.tick(delta)     ← AVnode + BundleOfHis + PurkinjeFibers conduction

lv.tick(delta)               ← myocytes.step_chamber() + step_elastance() (ventricles first)
rv.tick(delta)
la.tick(delta)
ra.tick(delta)

_step_valves(delta)          ← venous return, all 4 valve ticks, aorta fill
[pressure recompute]         ← all 4 chambers recomputed after flow
_aorta.tick(delta)           ← Windkessel runoff, dicrotic notch; returns outflow to vena_cava
_pulmonary_artery.tick(delta)

_step_heart()                ← SV/EF/CO/MAP/vitals written to CardiacMonitor last
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

`force_fire()` — primary HR control mechanism used by `tick_turn()`. Sets `Vm=10`, `state=PHASE_0`, triggering the beat immediately. The natural SA node firing rate is ~103 bpm at these sim parameters; `force_fire()` is used to impose the HR computed by the sympathetic tone controller.

`cardioplegia: bool` — when true, clamps `ic_k=500` (hyperpolarized, no firing). Accessed directly via `cardio.sa_node.cardioplegia`.

---

## Electrical Conduction Chain

### ConductionComponent

**File:** `scenes/character/organs/conduction_component.gd`

Generic timer node. All four conduction nodes share this script.

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

```
SAnode.fired ──► AtrialTract.activate()
AtrialTract.conducted ──► depolarized.emit()
```

**Signal:** `depolarized` — atria fully activated; triggers LA/RA myocyte sweeps and starts ventricular chain.

### ElectricalPathway (VentricularComponents)

**File:** `scenes/character/organs/electrical_pathway.gd`

```
AtrialComponents.depolarized ──► AVnode.activate()
AVnode.conducted             ──► BundleOfHis.activate()
BundleOfHis.conducted        ──► PurkinjeFibers.activate()
PurkinjeFibers.conducted     ──► ventricular_depolarization_started.emit()
```

**Signal:** `ventricular_depolarization_started` — triggers aortic valve latch reset and LV/RV myocyte sweeps (self-wired in ChamberMyocytes._ready()).

---

## CardiacChamber

**File:** `scenes/character/organs/cardiac_chamber.gd`

All 4 chambers are separate scene nodes in `character_cardiovascular.tscn`, each with their own `@export` values.

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

### Runtime State

| Property | Meaning |
|---|---|
| `volume` | current chamber volume mL |
| `pressure` | `elastance * max(0, volume - v0)` mmHg |
| `elastance` | current E(t) mmHg/mL |

### Elastance + Pressure Model

```
normalized_force = _myocytes.active_force / region_count
if normalized_force > 0:
    elastance = min(e_max, elastance + normalized_force * e_rise_rate * delta)
else:
    elastance = max(e_min, elastance - e_decay_rate * delta)

pressure = elastance * max(0, volume - v0)
```

`tick(delta)` calls `_myocytes.step_chamber(delta)` then `step_elastance(delta)`.

---

## ChamberMyocytes

**File:** `scenes/character/organs/chamber_myocytes.gd`

Child of each chamber as `Myocytes`. Owns all action potential phase logic, regional sweep, and electrical source wiring.

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

```
electrical_source == 0 (atrial):
    HeartElectricalSystem/AtrialComponents.depolarized → trigger_sweep()

electrical_source == 1 (ventricular):
    HeartElectricalSystem/Ventricularcomponents.ventricular_depolarization_started → trigger_sweep()
```

### Electrical Sweep

`trigger_sweep()` — resets all regions to resting, starts sweep.

- Atria: 1 fascicle × 3 regions = 3 regions
- Ventricles: 3 fascicles × 3 regions = 9 regions; fascicles fire sequentially over `sweep_duration=0.0375s`

### Myocyte Action Potential Phases (ventricular, from tscn)

`myocyte_durations = [0.0025, 0.00625, 0.125, 0.1, 0.0]`
`myocyte_force     = [0.1, 0.4, 1.0, 0.25, 0.0]`

| Phase | Duration | Force |
|---|---|---|
| 0 | 0.0025s | 0.10 |
| 1 | 0.00625s | 0.40 |
| 2 | 0.125s | 1.00 |
| 3 | 0.100s | 0.25 |
| 4 | ∞ (resting) | 0.00 |

Total active duration per myocyte: ~0.234s

---

## Chamber Constants (from `character_cardiovascular.tscn`)

| Chamber | e_min | e_max | e_rise | e_decay | v0 | vol_init | valve_cond | fascicles | sweep |
|---|---|---|---|---|---|---|---|---|---|
| LA | (default) | (default) | 4.0 | 2.4 | 10 mL | 70 mL | 20.0 | 1 | (default) |
| LV | 0.06 | 2.5 | 20.0 | 48.0 | 10 mL | 120 mL | 40.0 | 3 | 0.0375s |
| RA | 0.25 | 0.67 | 4.0 | 2.4 | 8 mL | 22 mL | 48.0 | 1 | (default) |
| RV | 0.05 | (default) | 4.8 | 4.8 | 10 mL | 120 mL | 40.0 | 3 | 0.0375s |

Note: `lv.e_max` is overridden at runtime by `_apply_sympathetic_tone()`. Scene value 2.5 = BASELINE_LV_EMAX.

---

## CardiacValve

**File:** `scenes/character/organs/cardiac_valve.gd`

Single configurable script shared by all 4 valves.

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

### Per-Valve Configuration (from tscn)

| Valve | Key exports |
|---|---|
| MitralValve | `contraction_rate=96`, `use_systole_guard=true`, `use_c_wave=true`, `use_pcwp_detection=true` |
| AorticlValve | `use_latch=true`, `use_waveform_tracking=true`, `notch_dip=2.0` |
| TricuspidValve | `contraction_rate=144`, `use_systole_guard=true` |
| PulmoniclValve | `pressure_clamp_max=60.0` |

### Signals

| Signal | When |
|---|---|
| `upstream_closed(volume)` | valve closes — carries EDV (mitral) or ESV (aortic) |
| `waveform_peak(pressure)` | v-wave PCWP peak (mitral) or SBP (aortic) |
| `waveform_trough(pressure)` | y-descent PCWP (mitral) or DBP (aortic) |

### Setup

`setup(upstream: CardiacChamber, downstream: CardiacChamber)` — called from coordinator `_ready()`. Semilunar valves pass `null` for downstream.

Signal connections (`upstream_closed`, `waveform_peak`, `waveform_trough`) wired in coordinator `_ready()`, write into `CardiacMonitor`.

### tick()

`tick(delta, downstream_pressure, ventricular_systole, downstream_valve_open)`

### Valve Behavior

**AV valves (mitral, tricuspid) — pressure-driven with systolic stability guard:**
- Closes when `ventricular_systole=true` AND `downstream.pressure > upstream.pressure + 1.0`
- Opens when `ventricular_systole=false` AND `downstream.pressure <= upstream.pressure + 1.0`
- Flow when open: active (`contraction_rate × atrial_force × delta`) + passive (`pressure_gradient × conductance × delta`)

**Semilunar valves (aortic, pulmonic) — fully emergent, pure pressure differential:**
- Opens when `upstream.pressure >= downstream_pressure + open_threshold`
- Closes when `upstream.pressure < downstream_pressure`
- Flow when open: `(upstream.pressure - downstream_pressure) × conductance × delta`

**Aortic latch (`use_latch=true`):** Cannot reopen after closing until next `ventricular_depolarization_started`.

**Waveform tracking (aortic):** Tracks downstream pressure peak → `waveform_peak(SBP)` on valve close; trough → `waveform_trough(DBP)` on valve reopen.

**PCWP detection (mitral):** v-wave peak and y-descent trough emitted from LA pressure waveform.

---

## Venous Return

### Pulmonary Venous Reservoir — `pulmonary_vein.gd`

| Parameter | Value |
|---|---|
| `volume` | 430 mL initial |
| `UNSTRESSED_VOLUME` | 300 mL |
| `COMPLIANCE` | 10 mL/mmHg |
| `TO_LA_CONDUCTANCE` | 23 mL/(s·mmHg) |

### Systemic Venous Reservoir — `vena_cava.gd`

| Parameter | Value |
|---|---|
| `volume` | 3665 mL initial |
| `BASELINE_UNSTRESSED_VOLUME` | 3000 mL |
| `unstressed_volume` | 3000 mL (var — modulated by sympathetic tone) |
| `COMPLIANCE` | 50 mL/mmHg |
| `BASELINE_TO_RA_CONDUCTANCE` | 14.3 mL/(s·mmHg) |
| `to_ra_conductance` | 14.3 mL/(s·mmHg) (var — modulated by sympathetic tone) |

---

## Aorta — Two-Element Windkessel — `aorta.gd`

`P = (volume - UNSTRESSED_VOLUME) / COMPLIANCE`

| Parameter | Value |
|---|---|
| `volume` | 620 mL initial |
| `COMPLIANCE` | 1.55 mL/mmHg |
| `UNSTRESSED_VOLUME` | 550 mL |
| `BASELINE_SYSTEMIC_RESISTANCE` | 1.295 mmHg·s/mL |
| `systemic_resistance` | 1.295 mmHg·s/mL (var — modulated by sympathetic tone) |

Each tick: pressure derived from volume → outflow = `pressure / systemic_resistance * delta` → drains into vena_cava → pressure rederived → dicrotic notch applied if `_aortic_valve.notch_fired`.

---

## Pulmonary Artery — `pulmonary_artery.gd`

Pressure-only model (no volume). Decays at 4.0 mmHg/s when pulmonic valve closed. Clamped `[8.0, 30.0]` mmHg.

---

## CardiacMonitor — `cardiac_monitor.gd`

Snapshot of derived metrics. Written by coordinator each tick. **Does not drive simulation.** Nothing should write to this to affect sim behavior.

| Variable | Source |
|---|---|
| `EDV` | `lv.volume` at mitral closure |
| `ESV` | `lv.volume` at aortic closure |
| `SV` | `EDV - ESV` |
| `EF` | `(SV / EDV) × 100` |
| `cardiac_output` | `(SV × heart_rate) / 1000` L/min |
| `bp_systolic` | aortic valve `waveform_peak` |
| `bp_diastolic` | aortic valve `waveform_trough` |
| `mean_arterial_pressure` | `DBP + (SBP - DBP) / 3` |
| `pulse_pressure` | `SBP - DBP` |
| `pcwp` | `la.pressure` at top of `_step_valves()` |
| `aorta_pressure` | `_aorta.pressure` each tick |
| `aorta_blood_flow` | true while aortic valve open |
| `aorta_blood_flow_end` | true the tick aortic valve closes |

External access: `cardio.monitor.bp_systolic`, `cardio.monitor.cardiac_output`, etc.

---

## Sympathetic Tone Controller

Two-channel closed-loop CO controller. `_apply_sympathetic_tone()` is called at the **end** of `tick_turn()`, after all beats have run, so it reads real measured CO and applies updated parameters to the **next** turn.

**Channels:**
- `_sym_tone_fast` — neural (HR, inotropy): rise alpha=0.6, decay alpha=0.25
- `_sym_tone_slow` — humoral (SVR, venous tone): rise alpha=0.5, decay alpha=0.15

**Error signal:** `co_error = demanded_co - monitor.cardiac_output`
`error_fraction = co_error / (MAX_CO - BASELINE_CO)` where `MAX_CO=20.0`, `BASELINE_CO=5.0`

**Modulated parameters:**

| Parameter | Range |
|---|---|
| `heart_rate` | lerpf(60, 180, tone_fast) |
| `lv.e_max` | lerpf(2.5, 4.5, pow(tone_fast, 0.4)) — concave inotropy curve |
| `lv.e_rise_rate` | lerpf(20, 130, tone_fast) |
| `lv.e_decay_rate` | lerpf(60, 120, tone_fast) |
| `rv.e_max` | lerpf(1.2, 2.0, tone_fast) |
| `la.valve_conductance` | lerpf(25, 55, tone_fast) |
| `aorta.systemic_resistance` | lerpf(1.295, 0.479, pow(tone_slow, 0.4)) |
| `vena_cava.unstressed_volume` | lerpf(3000, 2550, pow(tone_slow, 0.4)) |
| `vena_cava.to_ra_conductance` | lerpf(14.3, 28.6, pow(tone_slow, 0.4)) |

**Demanded CO by action (set via `set_demand()` in `character_movement.gd`):**

| Action | demanded_co |
|---|---|
| Wait (space) | 4.66 L/min |
| Normal move | 6.5 L/min |
| Structure attack | 15.0 L/min |
| Combat bump | 17.0 L/min |

**Steady-state at rest (tone→0, demand=4.66):** BP ~120/80, HR 60, CO ~4.84 L/min.
**Walking (demand=6.5, turns 1-8):** BP ~128-131/80-82, HR ~63-70, SV ~88-93, EDV ~138-145, ESV ~45-52.

---

## Signals (coordinator-level)

| Signal | When fired |
|---|---|
| `v_wave_peak(pcwp)` | re-emitted from `_mitral_valve.waveform_peak` |
| `y_descent_start(pcwp)` | re-emitted from `_mitral_valve.waveform_trough` |

---

## Signal Flow — Full Cardiac Cycle

```
sa_node.force_fire()  ← called by tick_turn() beat loop
	│
	└─► fired ──► AtrialTract.activate()
				  │  0.08s
				  ▼
			  AtrialTract.conducted ──► AtrialComponents.depolarized
				  │
				  ├─► [LA/RA Myocytes.trigger_sweep() — self-wired]
				  │       la/ra elastance rises → la.pressure rises → passive mitral flow
				  │
				  └─► AVnode.activate()
						  │  0.06s → BundleOfHis 0.01s → PurkinjeFibers 0.02s
						  ▼
					  ventricular_depolarization_started
						  │
						  └─► [LV/RV Myocytes.trigger_sweep() — self-wired]
								  lv fascicles fire over 0.0375s
								  lv myocytes: total active ~0.234s
								  lv.pressure rises → mitral closes (systole guard)
								  lv.pressure >= aorta_pressure → aortic valve opens
								  ejection → aorta_volume rises → SBP recorded on close
								  lv.pressure < aorta_pressure → aortic valve closes + latch
								  notch_fired → dicrotic notch applied
								  waveform_peak(SBP), waveform_trough(DBP)
								  lv.pressure < la.pressure → mitral opens (diastole)
```

---

## External API

**Simulation state on `cardio`:**
- `heart_rate`, `TPR`, `spo2`, `demanded_co`, `demanded_co_pre_decay`
- `BASELINE_CO = 5.0`, `MAX_CO = 20.0`
- `set_demand(co: float)` — sets demanded cardiac output
- `sa_node` — direct access to SANode; `sa_node.cardioplegia = true` for arrest
- `tick_turn()` — advance one full turn (750 steps + sympathetic update)
- `tick(delta)` — advance one simulation step (used by KP_4 debug)

**Snapshot metrics on `cardio.monitor`:**
- `bp_systolic`, `bp_diastolic`, `mean_arterial_pressure`, `pulse_pressure`
- `cardiac_output`, `SV`, `EDV`, `ESV`, `EF`
- `pcwp`, `aorta_pressure`, `aorta_blood_flow`, `aorta_blood_flow_end`

---

## Debug

- **KP_4** — `sa_node.force_fire()` + one beat worth of `tick(SIM_STEP)` calls (`ceili(60/heart_rate/SIM_STEP)` steps). Does NOT call `tick_turn()` or `_apply_sympathetic_tone()`. Runs at current parameters. Produces 120/80 at game start (pure baseline, no tone). Prints [WAVEFORM] per-tick and [BEAT] summary.
- **F12** — toggles cardiovascular debug panel (wired in `character_interaction.gd`)

---

## Accuracy

All 4 chambers use time-varying elastance. Pressure is always emergent from `E(t) * (V - V0)`. Semilunar valves are fully pressure-driven. AV valves use a systolic stability guard (not a physiological gate) to prevent mid-systole flutter.

### Remaining Limitations

| Limitation | Why it matters |
|---|---|
| Venous reservoir capacitance is lumped, not distributed | real pulmonary/systemic compliance is distributed |
| Pulmonary artery is pressure-only (no volume model) | no pulmonary vascular resistance curve |
| No interventricular septal coupling | RV/LV interact mechanically in reality |
| Right heart constants less validated than left heart | right-sided pressures may drift |

---

## Pending

- Verify resting equilibrium at 120/80 after sympathetic tone controller moved to end of tick_turn()
