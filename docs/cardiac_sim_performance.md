# Cardiac Simulation Performance Architecture

## Background

Every character in ChemRogueLite runs a full cardiovascular simulation: SA node electrophysiology, conduction system, four chambers with time-varying elastance, four valves, aortic Windkessel model, vena cava, pulmonary vein, and a two-channel sympathetic tone controller. One turn = 15 seconds of simulated time, stepped at 20ms intervals — **750 steps per character per turn**.

With 10 enemies on the map, this became a performance problem.

---

## The Problem

The original GDScript simulation ran all 750 steps synchronously on the main thread. With 10 enemies:

- Each enemy: ~200ms of GDScript math
- All enemies: potentially 2 seconds of blocking work per player turn
- Result: severe frame drops every time the player moved

### First fix: spread enemies across frames

Added `await get_tree().process_frame` between each enemy in `turn_order.gd`. This eliminated the hard freeze — enemies processed one per frame — but each enemy's frame still spiked above 16ms (60fps budget), causing visible stuttering.

---

## The Solution

### Step 1: C++ GDExtension

Ported the entire cardiac simulation to C++ as a GDExtension. The `CardiacSim` node (`cardiac_sim/src/`) is a native Godot node that exposes `tick_turn()`, `set_demand()`, and output getters to GDScript.

**Build:**
```bash
# From WSL, close Godot first
cd cardiac_sim
scons platform=windows target=template_release arch=x86_64
```

The `windows.debug.x86_64` entry in `cardiac_sim.gdextension` points at the release DLL so the editor always uses optimized code.

**Player vs enemy split:**
- **Player** uses the original GDScript simulation — it drives UI signals, the pressure graph, waveform tracking, and PCWP events. Full fidelity pipeline.
- **Enemies** use the C++ `CardiacSim` node. Only HR/BP/CO/SV are read back for vitals display.

### Step 2: Parallel background threads

The C++ sim is pure math with zero Godot API calls, making it safe to run off the main thread. Rather than processing enemies sequentially, all cardiac sims launch simultaneously at the start of the map turn:

```
Turn start
│
├─ Launch thread: enemy 1 cardiac sim  ─┐
├─ Launch thread: enemy 2 cardiac sim   │  All running in parallel
├─ Launch thread: enemy 3 cardiac sim   │  on background threads
│  ...                                  │
├─ Launch thread: enemy N cardiac sim  ─┘
│
├─ Main thread: AI pathfinding (enemy 1)   ~1.5ms
├─ Main thread: AI pathfinding (enemy 2)   ~1.5ms
│  ...                                     (sequential, cheap)
│
├─ Wait for all threads to finish          (usually already done)
│
└─ Collect results + run pulmonary/renal/etc per enemy
```

With 16 CPU cores available, 10 threads complete in roughly the same time as 1. The AI loop (~15ms total) runs concurrently, so by the time it finishes the cardiac threads are usually already done — the wait loop rarely yields even once.

### Key threading rules

- Never call any Godot API from inside `tick_turn()` — no signals, no print, no Node methods
- Never read from a `CardiacSim` node while `is_done()` returns false
- Always join the thread in the destructor

---

## File Map

| File | Role |
|------|------|
| `cardiac_sim/src/cardiac_sim.h` | C++ struct definitions + CardiacSim class |
| `cardiac_sim/src/cardiac_sim.cpp` | Full simulation + threading |
| `cardiac_sim/src/register_types.cpp` | GDExtension entry point |
| `cardiac_sim/SConstruct` | SCons build script |
| `cardiac_sim.gdextension` | DLL paths for Godot |
| `scenes/character/organs/character_cardiovascular.gd` | Player GDScript sim + enemy delegation |
| `scenes/character/organs/character_organ_registry.gd` | `tick()` / `tick_non_cardiac()` split |
| `scripts/turn_order.gd` | Parallel launch + wait loop |

---

## Result

10 enemies with full cardiovascular simulation running at stable 60fps.
