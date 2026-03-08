# Combat Resolution Reference

## Full Resolution Order (`_apply_damage`)

```
0. Weight class matchup → hit_penalty (0, -4, or -8)

1. Hit roll
   attacker: d20 + stat_hit_mod + weapon_hit_bonus - hit_penalty vs 10 + defender_hit_mod
   └─ Miss → "Miss!" label, return

2. Damage roll + crit check (simultaneous)
   ├─ Crit  → damage = weapon_die + floor((adrenal_mod + muscle_mod + sympathetic_mod) / 3)
   └─ Normal → damage = max(1, 1dWeaponDie + muscle_mod)

3. Parry (defender)
   d20 + parry_mod vs 19 + attacker parry_mod
   └─ Success → 1 reflected to attacker, "Parry!" label, return

4. Dodge (defender)
   d20 + dodge_mod vs 19
   └─ Success → "Dodge!" label, adrenal debt, return

5. Block (defender)
   d20 + block_mod vs 19 → d6 + block_mod reduction
   └─ Success → damage = max(1, damage - block_roll)

6. Damage lands → hp reduced, label spawned, death check
```

---

## 0. Weight Class Matchup

Attack weight class = computed from combined r_hand + l_hand item weights.
Armor weight class = computed from total weight of all non-hand armor slots.

| Total Attack Weight | Class |
|---------------------|-------|
| < 5 lbs | Light |
| 5 – 15 lbs | Medium |
| > 15 lbs | Heavy |

| Total Armor Weight | Class |
|--------------------|-------|
| < 25 lbs | Light |
| 25 – 60 lbs | Medium |
| > 60 lbs | Heavy |

**Hit penalty:**

| Attacker \ Defender | Light | Medium | Heavy |
|---------------------|-------|--------|-------|
| Light | 0 | -4 | -8 |
| Medium | -4 | 0 | -4 |
| Heavy | -8 | -4 | 0 |

**Available defenses after a hit lands:**

| Attacker \ Defender | Light | Medium | Heavy |
|---------------------|-------|--------|-------|
| Light | parry, dodge, block | parry, block | block |
| Medium | parry, dodge | parry, dodge, block | parry, block |
| Heavy | dodge | parry, dodge | parry, dodge, block |

Defenses not in the available set are skipped entirely for that exchange.
Unarmed = light attack. Unarmored = light defense.

---

## 1. Hit Roll

| Component | Formula |
|-----------|---------|
| Attacker roll | `d20 + stat_hit_mod + weapon_hit_bonus - weight_penalty` |
| Defender threshold | `10 + defender stat_hit_mod` |
| Stat hit mod | `floor((cardio_mod + adrenal_mod + sympathetic_mod + parasympathetic_mod) / 4)` |
| Weapon hit bonus | per-item `hit_bonus` field (e.g. combat knife = +1) |

At all-10 stats, matched weight, no weapon: hits on 10+, ~55% baseline.
Miss → gray "Miss!" label, return.

---

## 2. Damage Roll + Crit Check

| Component | Formula |
|-----------|---------|
| Weapon die | per-item `damage_die` field (unarmed = 3) |
| Crit chance | `0.05 + affect_mod * 0.025` |
| Crit damage | `weapon_die + floor((adrenal_mod + muscle_mod + sympathetic_mod) / 3)` |
| Normal damage | `max(1, 1d[weapon_die] + muscle_mod)` |

Both rolled simultaneously. Crit uses max die value instead of rolling. Gold "CRIT -NHP" label.

Crit chance examples: affect 10 → 5%, affect 14 → 10%, affect 18 → 15%

---

## 3. Parry

| Component | Formula |
|-----------|---------|
| Defender roll | `d20 + parry_mod` |
| Threshold | `19 + attacker parry_mod` (contested) |
| Parry mod | `floor((muscle_mod + parasympathetic_mod) / 2)` |

Success: 0 damage, 1 HP reflected to attacker, cyan "Parry!" label, return. No stat debt.

---

## 4. Dodge

| Component | Formula |
|-----------|---------|
| Defender roll | `d20 + dodge_mod` |
| Threshold | `19` (flat) |
| Dodge mod | `floor((cardio_mod + adrenal_mod + affect_mod) / 3)` |

Success: 0 damage, green "Dodge!" label, return.
Adrenal debt: `vitals.stat_debt["adrenal"] += adrenal_mod` (if mod > 0).

---

## 5. Block

| Component | Formula |
|-----------|---------|
| Activation roll | `d20 + block_mod` vs `19` |
| Block mod | `floor((muscle_mod + sympathetic_mod) / 2)` |
| Reduction roll | `1d6 + block_mod` |
| Damage floor | `1` |

Reduces damage from step 2 (including crit). Cannot fully negate.

---

## 6. Damage Lands

- `vitals.hp = max(0, vitals.hp - damage)`
- Spawns red "-NHP" or gold "CRIT -NHP" label
- `_refresh_ui()` called if target is player
- If `hp <= 0`: player attacker gains 10 XP, `target.queue_free()`

---

## TODO

- **Unarmed viability**: unarmed needs a distinct advantage once weapons exist (extra attack, parry bonus, stronger muscle scaling, or crit debuff) — design TBD

---

## Stat Reference

| Roll | Stats Used | Formula |
|------|-----------|---------|
| Stat hit mod | cardio, adrenal, sympathetic, parasympathetic | avg of 4 mods |
| Parry mod | muscle, parasympathetic | avg of 2 mods |
| Dodge mod | cardio, adrenal, affect | avg of 3 mods |
| Block mod | muscle, sympathetic | avg of 2 mods |
| Crit chance | affect | `0.05 + affect_mod * 0.025` |
| Crit damage | adrenal, muscle, sympathetic | avg of 3 mods + weapon_die |
| Normal damage | muscle | `1d[weapon_die] + muscle_mod` |

## Item Fields (combat-relevant)

| Field | Type | Description |
|-------|------|-------------|
| `weight` | float | Weight in lbs, contributes to attack/armor class computation |
| `damage_die` | int | Die size for damage roll (e.g. 4 = 1d4). Unarmed default = 3 |
| `hit_bonus` | int | Flat bonus to hit roll. Unarmed default = 0 |
