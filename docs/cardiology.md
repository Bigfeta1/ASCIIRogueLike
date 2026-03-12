# Cardiovascular System

**File:** `scenes/character/organs/character_cardiovascular.gd`

Full cardiac cycle simulation. Tick entry point: `tick(delta: float)` — called from `turn_order.gd` with `delta=0.016` on every player move/wait.

---

## Tick Order

Order matters — each step sees the previous step's output.

```
_step_sa_node(delta)
_step_electrical_pathway(delta)
_step_heart()
_step_atrial_sweep(delta)
_tick_atrial_myocytes(delta)
_step_left_ventricle(delta)   ← before LA so mitral logic sees current LV pressure
_step_left_atria(delta)
_step_aorta(delta)
_step_right_atria()
_step_right_ventricle(delta)
```

---

## SA Node

**States:** `PHASE_4 → PHASE_0 → PHASE_3`

Membrane potential: `Vm = -130 + ic_na + ic_ca + ic_k`

| Phase | Role |
|---|---|
| PHASE_4 | Slow diastolic depolarization. Na⁺ influx raises Vm toward -40, then Ca²⁺ influx drives it to +10. |
| PHASE_0 | Threshold reached. Fires `beat_initiated` signal. Transitions to PHASE_3. |
| PHASE_3 | Repolarization. K⁺ efflux decays. Resets all currents to baseline → back to PHASE_4. |

`force_fire_sa_node()` — debug helper: sets `Vm=10`, `sa_state=PHASE_0` to manually trigger a beat.

---

## Electrical Pathway

**States:** `ATRIAL_DEPOLARIZATION → AV_DELAY → VENTRICULAR_DEPOLARIZATION → EARLY_REPOLARIZATION → T_WAVE → ISOVOLUMETRIC_RELAXATION → DIASTOLIC_FILLING`

Delta-based timer. One state advance per tick.

| State | Duration | Notes |
|---|---|---|
| ATRIAL_DEPOLARIZATION | 0.08s | Triggers atrial sweep |
| AV_DELAY | 0.06s | AV node conduction delay |
| VENTRICULAR_DEPOLARIZATION | 0.03s | QRS complex; `ep_cardiac_phase1 = true` |
| EARLY_REPOLARIZATION | 0.03s | ST segment |
| T_WAVE | 0.15s | Ventricular repolarization |
| ISOVOLUMETRIC_RELAXATION | 0.03s | Both valves closed; elastance decays; emits `v_wave_peak` |
| DIASTOLIC_FILLING | 0.21s | Mitral opens; LV fills; emits `y_descent_start` |

**Key flags:**
- `ep_cardiac_phase1` — true during VENTRICULAR_DEPOLARIZATION, EARLY_REPOLARIZATION, T_WAVE
- `ep_cycle_reset` — true for exactly one tick at end of DIASTOLIC_FILLING
- `ep_running` — false until `beat_initiated` fires; set false again at cycle end

---

## Atrial Sweep

Triggered on `beat_initiated` via `_run_atrial_depolarization()`.

- `atrial_regions = 3`
- `time_to_depolarize_node = 0.08s / 3 ≈ 0.027s` per region
- Timer-driven: each region's `electrical` state set to DEPOLARIZED in sequence
- Each depolarization emits `atrial_region_depolarized(region)` which arms that region's myocyte at PHASE_0 and sets mechanical state to CONTRACTION immediately

---

## Atrial Myocytes

Per-region action potential. Triggered by `atrial_region_depolarized` signal.

| Phase | Duration | Force | Mechanical | Notes |
|---|---|---|---|---|
| PHASE_0 | 0.002s | 0.15 | CONTRACTION | Fast Na⁺ depolarization; force just beginning |
| PHASE_1 | 0.005s | 0.50 | CONTRACTION | Transient K⁺; rising force |
| PHASE_2 | 0.073s | 1.00 | CONTRACTION | Ca²⁺ plateau; peak force |
| PHASE_3 | 0.060s | 0.20 | RELAXATION | K⁺ repolarization; tapering force |
| PHASE_4 | ∞ | 0.00 | RELAXATION | Resting |

Force multiplier applied to ejection: `(LA_CONTRACTION_RATE / atrial_regions) * force * delta`

- `LA_CONTRACTION_RATE = 250.0` mL/s — peak rate; actual output shaped by force profile
- Ejection only occurs when `mitral_valve_open = true`
- Produces a crude rise → peak → taper force envelope rather than a rectangular on/off profile

Atrial state (`SYSTOLE`/`DIASTOLE`) derived each tick: SYSTOLE if any region is in CONTRACTION.

---

## Left Atria — Volume Model

PCWP is never set directly. It is always derived from `la_volume` using an exponential compliance curve:

```
x = max(0, la_volume - LA_UNSTRESSED_VOLUME)
pcwp = 2.0 * (exp(x / 20.0) - 1.0) + c_wave_pressure
```

Nonlinear — very compliant at low volumes, stiffens sharply at high volumes:
- LA=35 mL (x=25): ~5 mmHg — normal
- LA=50 mL (x=40): ~17 mmHg — elevated
- LA=70 mL (x=60): ~38 mmHg — pulmonary edema

| Constant | Value | Meaning |
|---|---|---|
| `LA_UNSTRESSED_VOLUME` | 10.0 mL | Volume at zero transmural pressure |
| `LA_VENOUS_RETURN_RATE_SYSTOLE` | 120.0 mL/s | Pulmonary venous return during reservoir phase (mitral closed) |
| `LA_VENOUS_RETURN_RATE_DIASTOLE` | 50.0 mL/s | Pulmonary venous return during conduit/booster phase |
| `LA_CONTRACTION_RATE` | 250.0 mL/s | Peak atrial ejection rate |
| `MITRAL_CONDUCTANCE` | 25.0 mL/s/mmHg | Passive mitral flow rate during diastole |

Venous return is cycle-dependent: `120.0 mL/s` when `ep_cardiac_phase1` (LA filling against closed mitral), `50.0 mL/s` otherwise.

Passive mitral flow (diastole only): `(pcwp - lv_pressure) * MITRAL_CONDUCTANCE * delta`

---

## Mitral Valve

Valve state owned entirely by `_step_left_atria`. Never set elsewhere.

**Ventricular closure phases:** `VENTRICULAR_DEPOLARIZATION`, `EARLY_REPOLARIZATION`, `T_WAVE`

**Close condition:** inside ventricular closure phases AND `lv_pressure > pcwp + 1.0`

**Open condition:** outside ventricular closure phases only — resets `mitral_valve_diameter = 1.0`, clears `c_wave_pressure`

### C-Wave (leaflet bulge)

Modeled as a direct pressure addition to PCWP — LA volume stays physically honest.

```
pcwp = passive_pcwp + c_wave_pressure
```

1. On `mitral_valve_closing`: resets `mitral_valve_diameter = 1.0`, `c_wave_pressure = 0.0`
2. `_resolve_c_wave(delta)`: decrements diameter at `MITRAL_CLOSE_RATE = 33.3/s` → fully closed in ~0.03s
3. While closing: `c_wave_pressure = C_WAVE_PEAK_PRESSURE * (1.0 - diameter)` — peaks at 3 mmHg
4. After full closure: `c_wave_pressure` decays at `C_WAVE_DECAY_RATE = 100.0 mmHg/s`
5. On full close: emits `mitral_valve_closed`

---

## Left Ventricle — Time-Varying Elastance Model

LV pressure is fully emergent from volume and elastance. No EP state drives pressure directly.

```
lv_pressure = lv_elastance * max(0, lv_volume - LV_V0)
```

| Constant | Value | Meaning |
|---|---|---|
| `LV_E_MIN` | 0.1 mmHg/mL | Diastolic (passive) elastance |
| `LV_E_MAX` | 2.5 mmHg/mL | Systolic (active) elastance |
| `LV_E_RISE_RATE` | 30.0 /s | Elastance rise rate during `ep_cardiac_phase1` |
| `LV_E_DECAY_RATE` | 8.0 /s | Elastance decay rate outside `ep_cardiac_phase1` |
| `LV_V0` | 10.0 mL | Dead volume — pressure = 0 at this volume |

- Aortic valve opens/closes emergently: opens when `lv_pressure >= aorta_pressure`, closes when it falls below
- Ejection flow: `(lv_pressure - aorta_pressure) * 3.0 * delta`, capped at `lv_volume - LV_V0`
- Mitral valve closure is fully emergent — LV pressure vs PCWP comparison in `_step_left_atria`

---

## Signals

| Signal | When fired |
|---|---|
| `beat_initiated` | SA node PHASE_0 threshold reached |
| `atrial_region_depolarized(region)` | Sweep reaches each atrial region |
| `mitral_valve_closing` | Mitral first closes; c-wave starts |
| `mitral_valve_closed` | Mitral fully shut |
| `v_wave_peak(pcwp)` | PCWP turns over after systolic rise — waveform-detected, not phase-tagged |
| `y_descent_start(pcwp)` | PCWP falls after mitral opens — waveform-detected, not phase-tagged |

All connections established in `_ready()`.

---

## Compatibility

Other organs reference these vars from cardiovascular:

- `bp_systolic`, `bp_diastolic` — aliases for `systolic_bp`/`diastolic_bp`
- `demanded_co`, `demanded_co_pre_decay`
- `BASELINE_CO = 5.0`, `MAX_CO = 20.0`
- `spo2 = 99.0`
- `set_demand(co)` — sets demanded cardiac output

---

## Debug

- **F12** — toggles cardiovascular debug panel (wired in `character_interaction.gd`)
- **Numpad 4** — calls `force_fire_sa_node()` + 12 manual ticks to observe full cascade
- Tick print format:
  ```
  EP=... SA=... | atria=... [R0:... R1:... R2:...] | LA=...mL PCWP=...mmHg mitral=O/X | LV=...mL LVp=... aortic=O/X
  ```

---

## Accuracy Rating

| Context | Rating |
|---|---|
| Game-ready left atrial model | **highly accurate** |
| Simplified physiology simulator | high end of moderate to low end of high |
| Research-grade atrial hemodynamics | not highly accurate |

The left atrium now behaves as a chamber with timed excitation, phased mechanical contribution, nonlinear compliance, reservoir/conduit/booster roles, and waveform features tied to chamber behavior.

### Remaining Limitations

| Limitation | Why it matters |
|---|---|
| V-wave and y-descent are still partly heuristic detections | more emergent than before, but not fully flow-physics derived |
| Pulmonary venous return is phase-switched | real return is more continuous |
| Mitral reopening is partly phase-permissive | not purely pressure-gradient governed |
| Atrial force is bucket-weighted | good approximation, not continuous activation-tension coupling |
| LV remains the downstream determinant of atrial emptying | unavoidable in a coupled chamber model |

---

## Pending

- Right heart is placeholder only
- LV volume coupling to LA: currently uses Frank-Starling preload model (`EDV`/`ESV`) rather than direct LA→LV volume transfer
