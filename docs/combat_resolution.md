# Combat Resolution Reference

## Full Resolution Order (`_apply_damage`)

```
1. Hit roll
   └─ Miss → "Miss!" label, return

2. Damage roll + crit check (simultaneous)
   ├─ Crit  → damage = 3 + floor((adrenal_mod + muscle_mod + sympathetic_mod) / 3)
   └─ Normal → damage = max(1, 1d3 + muscle_mod)

3. Parry (defender)
   └─ Success → 1 reflected to attacker, "Parry!" label, return

4. Dodge (defender)
   └─ Success → "Dodge!" label, adrenal debt, return

5. Block (defender)
   └─ Success → damage = max(1, damage - (1d6 + block_mod))

6. Damage lands → hp reduced, label spawned, death check
```

---

## 1. Hit Roll

| Component | Formula |
|-----------|---------|
| Attacker roll | `d20 + hit_mod` |
| Defender threshold | `10 + defender hit_mod` |
| Hit mod | `floor((cardio_mod + adrenal_mod + sympathetic_mod + parasympathetic_mod) / 4)` |
| Each stat mod | `floor((stat - 10) / 2)` |

At all-10 stats: hits on 10+, ~55% baseline.
Miss → gray "Miss!" label, function returns.

---

## 2. Parry

| Component | Formula |
|-----------|---------|
| Defender roll | `d20 + parry_mod` |
| Threshold | `19 + attacker parry_mod` |
| Parry mod | `floor((muscle_mod + parasympathetic_mod) / 2)` |

- Baseline: 10% chance (19–20 on d20 with 0 mods each side)
- Success: 0 damage to defender, 1 HP reflected to attacker, cyan "Parry!" label
- No stat debt

---

## 3. Dodge

| Component | Formula |
|-----------|---------|
| Defender roll | `d20 + dodge_mod` |
| Threshold | `19` (flat) |
| Dodge mod | `floor((cardio_mod + adrenal_mod + affect_mod) / 3)` |

- Baseline: 10% chance (19–20 on d20)
- Success: 0 damage, green "Dodge!" label
- **Adrenal debt**: `vitals.stat_debt["adrenal"] += adrenal_mod` (only if mod > 0)

---

## 4. Crit Check

| Component | Formula |
|-----------|---------|
| Crit chance | `0.05 + affect_mod * 0.025` |
| Crit damage | `3 + floor((adrenal_mod + muscle_mod + sympathetic_mod) / 3)` |
| Normal damage | `max(1, 1d3 + muscle_mod)` |

Crit chance examples:
- Affect 10 (mod 0) → 5%
- Affect 14 (mod +2) → 10%
- Affect 18 (mod +4) → 15%

Crit uses max die value (3) instead of rolling. Gold "CRIT -NHP" label.

---

## 5. Block

| Component | Formula |
|-----------|---------|
| Activation roll | `d20 + block_mod` vs threshold `19` |
| Block mod | `floor((muscle_mod + sympathetic_mod) / 2)` |
| Reduction roll | `1d6 + block_mod` |
| Damage floor | `1` (block cannot fully negate) |

Block reduces the damage value from step 4 — including crit damage.

---

## 6. Damage Lands

- `vitals.hp = max(0, vitals.hp - damage)`
- Spawns red "-NHP" or gold "CRIT -NHP" label
- `_refresh_ui()` called if target is player
- If `hp <= 0`: player attacker gains 10 XP, `target.queue_free()`

---

## Stat Reference Summary

| Defense | Mod Stats | Notes |
|---------|-----------|-------|
| Hit | cardio, adrenal, sympathetic, parasympathetic | avg of 4 |
| Parry | muscle, parasympathetic | avg of 2, contested |
| Dodge | cardio, adrenal, affect | avg of 3 |
| Block | muscle, sympathetic | avg of 2 |
| Crit chance | affect | flat scaling |
| Crit damage | adrenal, muscle, sympathetic | avg of 3 |
| Normal damage | muscle | flat mod |
