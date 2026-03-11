extends Node

# Pulmonary system — respiratory component.
# Models lung volumes, respiratory rate, alveolar gas exchange (O2/CO2),
# and pulmonary oxygenation status.
# Feeds SpO2 back into cardiovascular to limit effective CO delivery under hypoxia.
# Supports pneumothorax state and needle decompression treatment.

# ── Baseline constants ────────────────────────────────────────────────────────
const BODY_MASS_KG: float = 75.0
const TIDAL_VOLUME_FACTOR: float = 7.0       # mL/kg — normal tidal volume per kg
const BASELINE_RR: float = 12.0              # breaths/min at rest
const MAX_RR: float = 40.0                   # physiological ceiling
const PATM: float = 760.0                    # mmHg atmospheric pressure
const PH2O: float = 47.0                     # mmHg water vapour at 37°C
const FIO2: float = 0.21                     # fraction inspired O2 (room air)
const RESPIRATORY_QUOTIENT: float = 0.8      # CO2 produced / O2 consumed

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
var pneumothorax: bool = false               # Lung collapsed — tidal volume → 0
var pneumothorax_side: String = ""           # "left" or "right"

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

	if pneumothorax:
		# Compensatory tachypnea — breathe faster to compensate for lost volume
		base_rr = minf(base_rr * 1.5, MAX_RR)

	respiratory_rate = clampf(base_rr, BASELINE_RR, MAX_RR)


func _update_tidal_volume() -> void:
	if pneumothorax:
		# Collapsed lung — tidal volume halved (one lung working)
		tidal_volume = (BODY_MASS_KG * TIDAL_VOLUME_FACTOR) * 0.5
	else:
		tidal_volume = BODY_MASS_KG * TIDAL_VOLUME_FACTOR
	current_lung_volume = functional_residual_capacity + tidal_volume


func _update_ventilation() -> void:
	minute_ventilation = tidal_volume * respiratory_rate
	alveolar_ventilation = (tidal_volume - anatomic_deadspace) * respiratory_rate


func _update_gas_exchange() -> void:
	# Inspired O2 partial pressure: PIO2 = (Patm - PH2O) × FiO2
	pio2 = (PATM - PH2O) * FIO2

	if pneumothorax:
		# Collapsed lung — alveolar O2 falls sharply, CO2 rises
		pao2 = 50.0
		paco2 = 55.0
	else:
		# Alveolar gas equation: PAO2 = PIO2 - (PACO2 / R)
		# PACO2 driven by alveolar ventilation: higher ventilation → lower PACO2
		var baseline_alv_vent: float = (BODY_MASS_KG * TIDAL_VOLUME_FACTOR - anatomic_deadspace) * BASELINE_RR
		var vent_ratio: float = alveolar_ventilation / baseline_alv_vent if baseline_alv_vent > 0.0 else 1.0
		paco2 = clampf(40.0 / vent_ratio, 20.0, 80.0)
		pao2 = clampf(pio2 - (paco2 / RESPIRATORY_QUOTIENT), 40.0, 130.0)

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
	# Needle decompression / chest tube — lung re-expands
	pneumothorax = false
	pneumothorax_side = ""
