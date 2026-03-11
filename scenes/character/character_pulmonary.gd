extends Node

# Pulmonary system — respiratory component.
# Models lung volumes, respiratory rate, alveolar gas exchange (O2/CO2),
# and pulmonary oxygenation status.
# Feeds SpO2 back into cardiovascular to limit effective CO delivery under hypoxia.
# Supports tension pneumothorax with progressive pressure accumulation and venous return collapse.

# ── Baseline constants ────────────────────────────────────────────────────────
const BODY_MASS_KG: float = 75.0
const TIDAL_VOLUME_FACTOR: float = 7.0       # mL/kg — normal tidal volume per kg
const BASELINE_RR: float = 12.0              # breaths/min at rest
const MAX_RR: float = 40.0                   # physiological ceiling
const PATM: float = 760.0                    # mmHg atmospheric pressure
const PH2O: float = 47.0                     # mmHg water vapour at 37°C
const FIO2: float = 0.21                     # fraction inspired O2 (room air)
const RESPIRATORY_QUOTIENT: float = 0.8      # CO2 produced / O2 consumed

# Tension pneumothorax pressure accumulation
# Each tick with active pneumothorax, pleural_pressure rises by PRESSURE_PER_TICK.
# At MEDIASTINAL_SHIFT_THRESHOLD, mediastinal compression begins.
# At VENA_CAVA_COLLAPSE_THRESHOLD, venous return collapses fully.
const PRESSURE_PER_TICK: float = 2.0         # cmH2O per tick — one-way valve leak
const MEDIASTINAL_SHIFT_THRESHOLD: float = 10.0   # cmH2O — shift begins, contralateral TV impaired
const VENA_CAVA_COLLAPSE_THRESHOLD: float = 25.0  # cmH2O — venous return critically compromised

# ── Lung volumes (mL, both lungs combined) ───────────────────────────────────
var total_lung_capacity: float = 0.0         # TLC
var residual_volume: float = 0.0             # RV — air remaining after max exhale
var expiratory_reserve_volume: float = 0.0   # ERV
var inspiratory_reserve_volume: float = 0.0  # IRV
var functional_residual_capacity: float = 0.0 # FRC = RV + ERV
var vital_capacity: float = 0.0              # VC = IRV + TV + ERV
var tidal_volume: float = 0.0                # TV — per breath at current RR demand
var current_lung_volume: float = 0.0         # FRC + current tidal volume

# ── Respiratory mechanics ─────────────────────────────────────────────────────
var respiratory_rate: float = 12.0           # breaths/min
var minute_ventilation: float = 0.0          # mL/min = TV × RR
var alveolar_ventilation: float = 0.0        # mL/min = (TV - Vd) × RR
var anatomic_deadspace: float = 150.0        # mL — fixed anatomic deadspace

# ── Alveolar gas exchange ─────────────────────────────────────────────────────
var pio2: float = 150.0                      # mmHg inspired O2 partial pressure
var pao2: float = 104.0                      # mmHg alveolar O2
var paco2: float = 40.0                      # mmHg alveolar CO2
var pao2_spo2: float = 99.0                  # SpO2 % — derived from PAO2 via dissociation curve
var pulm_vein_o2: float = 100.0              # mmHg pulmonary vein O2 (post gas exchange)

# ── Disease states ────────────────────────────────────────────────────────────
var pneumothorax: bool = false               # Lung collapsed
var pneumothorax_side: String = ""           # "left" or "right"
var pleural_pressure: float = 0.0            # cmH2O — accumulated intrapleural pressure (tension mechanism)
var venous_return_fraction: float = 1.0      # 0.0–1.0 — fraction of normal venous return; fed into cardiovascular

var pulmonary_embolism: bool = false         # Clot obstructing pulmonary blood flow
var pe_severity: float = 0.0                # 0.0–1.0 — fraction of pulmonary arterial tree obstructed
var pe_rv_strain: float = 0.0               # 0.0–1.0 — progressive RV dilation/failure; accumulates each tick

# ── Internal refs ─────────────────────────────────────────────────────────────
var _organs: Node = null
var _levels: Node = null
var _vitals: Node = null


func setup(organ_registry: Node, levels: Node, vitals: Node = null) -> void:
	_organs = organ_registry
	_levels = levels
	_vitals = vitals
	_calculate_volumes()


func _calculate_volumes() -> void:
	# Standard proportions of TLC (based on body mass at 7 mL/kg tidal volume)
	var base_tv: float = BODY_MASS_KG * TIDAL_VOLUME_FACTOR
	total_lung_capacity = base_tv / 0.12          # TV is ~12% of TLC at rest
	residual_volume = total_lung_capacity * 0.20
	expiratory_reserve_volume = total_lung_capacity * 0.20
	inspiratory_reserve_volume = total_lung_capacity * 0.50
	functional_residual_capacity = residual_volume + expiratory_reserve_volume
	tidal_volume = base_tv
	vital_capacity = inspiratory_reserve_volume + tidal_volume + expiratory_reserve_volume
	current_lung_volume = functional_residual_capacity + tidal_volume


func tick() -> void:
	if _organs == null:
		return

	_update_pe_rv_strain()
	_update_tension_pressure()
	_update_respiratory_rate()
	_update_tidal_volume()
	_update_ventilation()
	_update_gas_exchange()
	_update_spo2()

	# Write SpO2 back into cardiovascular, and RR into vitals for HUD display.
	if _organs.get("cardiovascular") != null:
		_organs.cardiovascular.spo2 = pao2_spo2
	if _vitals != null:
		_vitals.rr = roundi(respiratory_rate)
		_vitals._refresh_ui()


func _update_pe_rv_strain() -> void:
	if _organs.get("cardiovascular") == null:
		return

	if not pulmonary_embolism:
		# RV recovers slowly after clot clears — strain drains at fixed rate
		pe_rv_strain = maxf(0.0, pe_rv_strain - 0.03)
	else:
		# RV strain accumulates proportional to obstruction — fast for massive PE, slow for submassive
		pe_rv_strain = minf(1.0, pe_rv_strain + pe_severity * 0.15)

	# Target venous_return_fraction from PE: falls to 0.2 at full RV strain.
	var pe_vrf_target: float = 1.0 - pe_rv_strain * 0.8

	# Lerp toward target — deterioration faster than recovery (asymmetric)
	var vrf: float = _organs.cardiovascular.venous_return_fraction
	var alpha: float = 0.4 if pe_vrf_target < vrf else 0.15
	_organs.cardiovascular.venous_return_fraction = lerpf(vrf, pe_vrf_target, alpha)


func _update_tension_pressure() -> void:
	if not pneumothorax:
		# Pressure dissipates quickly after decompression
		pleural_pressure = maxf(0.0, pleural_pressure - PRESSURE_PER_TICK * 3.0)
		venous_return_fraction = 1.0
		return

	# One-way valve: pressure rises each tick with active pneumothorax
	pleural_pressure += PRESSURE_PER_TICK

	# Venous return compression begins at mediastinal shift threshold.
	# Falls linearly from 1.0 at MEDIASTINAL_SHIFT_THRESHOLD to 0.1 at VENA_CAVA_COLLAPSE_THRESHOLD.
	if pleural_pressure <= MEDIASTINAL_SHIFT_THRESHOLD:
		venous_return_fraction = 1.0
	else:
		var compression_fraction: float = (pleural_pressure - MEDIASTINAL_SHIFT_THRESHOLD) / (VENA_CAVA_COLLAPSE_THRESHOLD - MEDIASTINAL_SHIFT_THRESHOLD)
		venous_return_fraction = maxf(0.1, 1.0 - compression_fraction * 0.9)

	# Feed venous return collapse into cardiovascular as a plasma_ratio penalty.
	# We reduce effective plasma seen by cardiovascular by suppressing plasma_fluid directly.
	# This collapses preload → SV → CO via Frank-Starling without touching actual fluid compartments.
	if _organs.get("cardiovascular") != null:
		_organs.cardiovascular.venous_return_fraction = venous_return_fraction


func _update_respiratory_rate() -> void:
	# RR scales with metabolic demand (demanded_co).
	# At rest: 12 bpm. At max exertion: up to 40 bpm.
	# Cardio stat improves ventilatory efficiency — same demand met at lower RR.
	var base_rr := BASELINE_RR
	if _organs.cardiovascular != null:
		var co_excess: float = maxf(0.0, _organs.cardiovascular.demanded_co_pre_decay - _organs.cardiovascular.BASELINE_CO)
		var co_fraction: float = co_excess / (_organs.cardiovascular.MAX_CO - _organs.cardiovascular.BASELINE_CO)
		var cardio_mod: float = 0.0
		if _levels != null:
			cardio_mod = _levels.stat_mod(_levels.cardio) * 0.1
		# Higher cardio → more efficient ventilation → lower RR for same demand
		var rr_range: float = (MAX_RR - BASELINE_RR) * maxf(0.0, 1.0 - cardio_mod)
		base_rr = BASELINE_RR + rr_range * co_fraction

	# Hypoxic drive: SpO2 < 90% → peripheral chemoreceptors → tachypnea.
	# Adds up to +28 bpm at SpO2=50% (full hypoxia). Takes the dominant driver.
	if _organs.cardiovascular != null:
		var spo2: float = _organs.cardiovascular.spo2
		if spo2 < 90.0:
			var hypoxic_rr: float = BASELINE_RR + (90.0 - spo2) / 40.0 * 28.0
			base_rr = maxf(base_rr, hypoxic_rr)

	# PE dead space drive: rising PaCO2 and falling PaO2 in dead space regions stimulate
	# central chemoreceptors directly — tachypnea is the first clinical sign of PE.
	# pe_rv_strain reflects cumulative RV stress; drive scales with obstruction + strain.
	# At 0.6 severity + early strain: pushes RR to ~22–26. At full strain: ~35+.
	if pulmonary_embolism:
		var pe_rr_drive: float = BASELINE_RR + pe_severity * 20.0 + pe_rv_strain * 8.0
		base_rr = maxf(base_rr, pe_rr_drive)

	base_rr = clampf(base_rr, BASELINE_RR, MAX_RR)

	# During pneumothorax the mechanical insult is monotonic — RR only ratchets upward.
	# Recovery only occurs after decompression.
	if pneumothorax:
		# Pressure-driven tachypnea: RR scales directly with pleural pressure toward MAX_RR.
		# At VENA_CAVA_COLLAPSE_THRESHOLD and beyond, RR should reach 40.
		var pressure_rr: float = BASELINE_RR + (pleural_pressure / VENA_CAVA_COLLAPSE_THRESHOLD) * (MAX_RR - BASELINE_RR)
		base_rr = maxf(base_rr, pressure_rr)
		base_rr = clampf(base_rr, BASELINE_RR, MAX_RR)
		respiratory_rate = maxf(respiratory_rate, base_rr)
	else:
		var rr_alpha: float = 0.5 if base_rr > respiratory_rate else 0.2
		respiratory_rate = lerpf(respiratory_rate, base_rr, rr_alpha)


func _update_tidal_volume() -> void:
	var base_tv: float = BODY_MASS_KG * TIDAL_VOLUME_FACTOR
	if not pneumothorax:
		tidal_volume = base_tv
	else:
		# Ipsilateral lung collapsed — start at 50% TV.
		# As mediastinal shift compresses contralateral lung, TV falls further.
		var contralateral_compression: float = 0.0
		if pleural_pressure > MEDIASTINAL_SHIFT_THRESHOLD:
			contralateral_compression = minf(1.0, (pleural_pressure - MEDIASTINAL_SHIFT_THRESHOLD) / (VENA_CAVA_COLLAPSE_THRESHOLD - MEDIASTINAL_SHIFT_THRESHOLD))
		# TV: 50% at shift onset, down to 25% at full collapse
		tidal_volume = base_tv * (0.5 - contralateral_compression * 0.25)
	current_lung_volume = functional_residual_capacity + tidal_volume


func _update_ventilation() -> void:
	minute_ventilation = tidal_volume * respiratory_rate
	alveolar_ventilation = maxf(0.0, tidal_volume - anatomic_deadspace) * respiratory_rate


func _update_gas_exchange() -> void:
	# Inspired O2 partial pressure: PIO2 = (Patm - PH2O) × FiO2
	pio2 = (PATM - PH2O) * FIO2

	if pneumothorax:
		# V/Q mismatch: ipsilateral lung is pure shunt (perfused but not ventilated).
		# As pressure rises, contralateral lung is also compressed → worsening hypoxia + hypercapnia.
		var shunt_fraction: float = 0.5  # ipsilateral lung = 50% of total perfusion, now shunt
		# Contralateral compression worsens gas exchange further
		if pleural_pressure > MEDIASTINAL_SHIFT_THRESHOLD:
			var extra_shunt: float = minf(0.35, (pleural_pressure - MEDIASTINAL_SHIFT_THRESHOLD) / (VENA_CAVA_COLLAPSE_THRESHOLD - MEDIASTINAL_SHIFT_THRESHOLD) * 0.35)
			shunt_fraction += extra_shunt

		# Ventilated fraction handles gas exchange; hyperventilation improves PACO2 but cannot
		# rescue the shunted fraction — shunted blood bypasses alveoli regardless of RR.
		var baseline_alv_vent: float = (BODY_MASS_KG * TIDAL_VOLUME_FACTOR - anatomic_deadspace) * BASELINE_RR
		var vent_ratio: float = alveolar_ventilation / baseline_alv_vent if baseline_alv_vent > 0.0 else 0.01
		paco2 = clampf(40.0 / vent_ratio, 20.0, 80.0)
		# PAO2 in ventilated alveoli — hyperventilation raises this but shunt dilutes the result
		var ventilated_pao2: float = clampf(pio2 - (paco2 / RESPIRATORY_QUOTIENT), 40.0, 130.0)
		# Mixed arterial PaO2: shunted blood is fixed at venous PO2 (~40 mmHg); no amount of
		# hyperventilation rescues it. Clamp ventilated_pao2 benefit to avoid RR-driven oscillation.
		var clamped_ventilated_pao2: float = minf(ventilated_pao2, 100.0)
		pao2 = clamped_ventilated_pao2 * (1.0 - shunt_fraction) + 40.0 * shunt_fraction
	else:
		# Alveolar gas equation: PAO2 = PIO2 - (PACO2 / R)
		# PACO2 driven by alveolar ventilation: higher ventilation → lower PACO2
		var baseline_alv_vent: float = (BODY_MASS_KG * TIDAL_VOLUME_FACTOR - anatomic_deadspace) * BASELINE_RR
		var vent_ratio: float = alveolar_ventilation / baseline_alv_vent if baseline_alv_vent > 0.0 else 1.0
		paco2 = clampf(40.0 / vent_ratio, 20.0, 80.0)
		pao2 = clampf(pio2 - (paco2 / RESPIRATORY_QUOTIENT), 40.0, 130.0)

	# Pulmonary embolism: dead space physiology — obstructed regions are ventilated but not perfused.
	# Blood is redistributed to remaining vessels → relative overperfusion → imperfect V/Q matching.
	# Hyperventilation lowers PACO2 (respiratory alkalosis) but cannot fully rescue PaO2.
	# RV strain reduces total pulmonary blood flow — the remaining perfused lung is overperfused
	# but cannot compensate fully. Net effect: PAO2 falls despite normal or elevated RR.
	if pulmonary_embolism:
		# Effective perfusion fraction: only (1 - pe_severity) of lung is perfused
		# Remaining lung is overperfused but V/Q ratio is still impaired
		# PAO2 in perfused regions is modestly elevated from hyperventilation
		# but overall mixed PAO2 falls because obstructed regions contribute no O2
		var perfused_fraction: float = 1.0 - pe_severity
		# Perfused lung PAO2 — slightly elevated from compensatory hyperventilation
		var perfused_pao2: float = minf(pao2 * 1.1, 130.0)
		# Obstructed regions contribute nothing (no blood flow, no gas exchange)
		# but atelectasis in poorly-perfused areas creates a small shunt component
		var atelectasis_shunt: float = pe_severity * 0.3
		pao2 = perfused_pao2 * perfused_fraction * (1.0 - atelectasis_shunt) + 40.0 * atelectasis_shunt

	# Pulmonary vein O2 accounts for physiologic shunt (~2% of CO bypasses alveoli)
	pulm_vein_o2 = pao2 * 0.98


func _update_spo2() -> void:
	# Simplified oxyhemoglobin dissociation curve approximation.
	# PaO2 → SpO2 (sigmoid relationship):
	# PaO2 ≥ 100: SpO2 ≈ 99%
	# PaO2 = 60: SpO2 ≈ 90%  (critical threshold)
	# PaO2 = 40: SpO2 ≈ 75%  (mixed venous)
	# PaO2 = 27: SpO2 ≈ 50%  (P50)
	if pulm_vein_o2 >= 100.0:
		pao2_spo2 = 99.0
	elif pulm_vein_o2 >= 60.0:
		# Linear approximation 60→100 maps to 90→99%
		pao2_spo2 = 90.0 + (pulm_vein_o2 - 60.0) / 40.0 * 9.0
	elif pulm_vein_o2 >= 27.0:
		# Steep part of curve 27→60 maps to 50→90%
		pao2_spo2 = 50.0 + (pulm_vein_o2 - 27.0) / 33.0 * 40.0
	else:
		pao2_spo2 = maxf(0.0, pulm_vein_o2 / 27.0 * 50.0)


# ── Disease API ───────────────────────────────────────────────────────────────

func trigger_pneumothorax(side: String = "right") -> void:
	pneumothorax = true
	pneumothorax_side = side


func resolve_pneumothorax() -> void:
	# Needle decompression / chest tube — pressure vented, lung re-expands
	pneumothorax = false
	pneumothorax_side = ""
	# pleural_pressure decays naturally in _update_tension_pressure each tick


func trigger_pe(severity: float = 0.4) -> void:
	pulmonary_embolism = true
	pe_severity = clampf(severity, 0.0, 1.0)


func resolve_pe() -> void:
	# Thrombolysis / anticoagulation — clot cleared
	pulmonary_embolism = false
	pe_severity = 0.0
