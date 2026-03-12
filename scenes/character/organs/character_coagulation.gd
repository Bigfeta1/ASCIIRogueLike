extends Node

# Coagulation cascade — Virchow's Triad model.
#
# Clot formation is driven by three inputs:
#   1. Stasis         — waiting increases stasis_score; moving clears it
#   2. Endothelial injury — taking damage raises injury score; decays over time
#   3. Hypercoagulable state — dehydration + hypoxia amplify cascade rate
#
# Extrinsic pathway (injury-triggered):
#   VII → VIIa → TF-VIIa → Xa
# Common pathway:
#   Xa + Va → Thrombin → Fibrinogen → Fibrin → Crosslinked clot
# Intrinsic pathway (contact activation, feeds common pathway):
#   XII → XIIa → XIa → IXa → (amplifies Xa)
#
# Plasmin runs continuously at baseline — slower than active clotting so clot grows,
# but wins once heparin halts cascade progression.
# When crosslinkage reaches EMBOLISM_THRESHOLD, a PE is triggered via pulmonary.

const EMBOLISM_THRESHOLD: float = 60.0

# ── Virchow inputs ────────────────────────────────────────────────────────────
var stasis_score: float = 0.0            # 0–100 — accumulates on wait, clears on move
var endothelial_injury: float = 0.0      # 0–100 — set by taking damage, decays each tick

# ── Extrinsic pathway factors (0–100) ────────────────────────────────────────
var factor_7: float = 100.0
var factor_7a: float = 0.0
var tissue_factor: float = 0.0
var tf_viia: float = 0.0
var factor_10: float = 100.0
var factor_10a: float = 0.0
var factor_5a: float = 1.0

# ── Common pathway ────────────────────────────────────────────────────────────
var prothrombin: float = 100.0
var thrombin: float = 0.0
var fibrinogen: float = 100.0
var fibrin: float = 0.0
var factor_13a: float = 1.0
var crosslinkage: float = 0.0            # 0–100 — clot formation progress

# ── Intrinsic pathway factors (0–100) ────────────────────────────────────────
var factor_12: float = 100.0
var factor_12a: float = 0.0
var factor_11: float = 100.0
var factor_11a: float = 0.0
var factor_9: float = 100.0
var factor_9a: float = 0.0

# ── Fibrinolytic system ───────────────────────────────────────────────────────
var plasmin: float = 1.5                 # baseline fibrinolysis — loses to active cascade (~2.5/tick), wins when heparin stops it; clears 60% clot in ~40 turns

# ── State ─────────────────────────────────────────────────────────────────────
var heparin_active: bool = false
var embolism_triggered: bool = false

var _organs: Node = null


func setup(organ_registry: Node) -> void:
	_organs = organ_registry


func tick() -> void:
	# ── Virchow: stasis decays slowly each tick (time passing while idle)
	stasis_score = clampf(stasis_score + 2.0, 0.0, 100.0)

	# ── Virchow: endothelial injury decays toward 0 — wounds heal over time
	endothelial_injury = maxf(0.0, endothelial_injury - 1.0)

	# ── Hypercoagulable modifier: dehydration + hypoxia amplify cascade
	var hypercoag: float = 1.0
	if _organs != null:
		if _organs.get("renal") != null:
			var plasma_ratio: float = _organs.renal.plasma_fluid / 3750.0
			hypercoag += maxf(0.0, 1.0 - plasma_ratio) * 1.5
		if _organs.get("cardiovascular") != null:
			var spo2: float = _organs.cardiovascular.spo2
			if spo2 < 90.0:
				hypercoag += (90.0 - spo2) / 40.0 * 1.0

	# ── Cascade activation rate: product of all three Virchow inputs
	# Tissue factor is released proportional to stasis × injury × hypercoag.
	# At rest with no injury, rate is near zero. Injury + immobility = rapid cascade.
	var activation_rate: float = (stasis_score / 100.0) * (endothelial_injury / 100.0) * hypercoag
	tissue_factor = minf(100.0, tissue_factor + activation_rate * 5.0)

	var f: float = (10.0 / 13.5) * activation_rate

	var xa_inhibited: bool = heparin_active
	var thrombin_inhibited: bool = heparin_active

	# ── Extrinsic pathway ─────────────────────────────────────────────────────
	if factor_7 > 0.0:
		factor_7 -= f
		factor_7a += f

	if factor_7a > 0.0 and tissue_factor > 0.0:
		var step: float = f / 2.0
		factor_7a -= step
		tissue_factor -= step
		tf_viia += step

	if tf_viia > 0.0 and factor_10 > 0.0:
		var step: float = f / 3.0
		factor_10 -= step
		factor_10a += step

	# ── Common pathway ────────────────────────────────────────────────────────
	if factor_10a > 0.0 and prothrombin > 0.0 and not xa_inhibited:
		var step: float = (f / 4.0) * factor_5a
		prothrombin -= step
		thrombin += step

	if thrombin > 0.0 and fibrinogen > 0.0 and not thrombin_inhibited:
		var step: float = (f / 5.0) * factor_5a
		fibrinogen -= step
		fibrin += step

	if fibrin > 0.0 and not thrombin_inhibited:
		var step: float = (f / 6.0) * factor_13a * factor_5a * 20.0
		fibrin -= step
		crosslinkage += step

	# ── Intrinsic pathway ─────────────────────────────────────────────────────
	if thrombin > 0.0 and factor_11 > 0.0 and not thrombin_inhibited:
		factor_11 -= f
		factor_11a += f

	if factor_11a > 0.0 and factor_9 > 0.0:
		var step: float = f / 2.0
		factor_9 -= step
		factor_9a += step

	# ── Fibrinolysis ──────────────────────────────────────────────────────────
	crosslinkage = maxf(0.0, crosslinkage - plasmin)
	if embolism_triggered and crosslinkage < EMBOLISM_THRESHOLD:
		embolism_triggered = false
		if _organs != null and _organs.get("pulmonary") != null:
			_organs.pulmonary.resolve_pe()

	# ── Floor all factors ─────────────────────────────────────────────────────
	factor_7 = maxf(0.0, factor_7)
	factor_7a = maxf(0.0, factor_7a)
	tissue_factor = maxf(0.0, tissue_factor)
	tf_viia = maxf(0.0, tf_viia)
	factor_10 = maxf(0.0, factor_10)
	factor_10a = maxf(0.0, factor_10a)
	prothrombin = maxf(0.0, prothrombin)
	thrombin = maxf(0.0, thrombin)
	fibrinogen = maxf(0.0, fibrinogen)
	fibrin = maxf(0.0, fibrin)
	factor_11 = maxf(0.0, factor_11)
	factor_11a = maxf(0.0, factor_11a)
	factor_9 = maxf(0.0, factor_9)
	factor_9a = maxf(0.0, factor_9a)
	crosslinkage = clampf(crosslinkage, 0.0, 100.0)

	# ── Embolism trigger ──────────────────────────────────────────────────────
	if not embolism_triggered and crosslinkage >= EMBOLISM_THRESHOLD:
		embolism_triggered = true
		if _organs != null and _organs.get("pulmonary") != null:
			var severity: float = clampf((crosslinkage - EMBOLISM_THRESHOLD) / (100.0 - EMBOLISM_THRESHOLD) * 0.6 + 0.4, 0.4, 1.0)
			_organs.pulmonary.trigger_pe(severity)


# ── Movement API ──────────────────────────────────────────────────────────────

func on_moved() -> void:
	# Movement disperses venous stasis — clears stasis score
	stasis_score = maxf(0.0, stasis_score - 20.0)


func on_waited() -> void:
	# Waiting accelerates stasis — additional bump on top of tick increment
	stasis_score = minf(100.0, stasis_score + 5.0)


# ── Combat API ────────────────────────────────────────────────────────────────

func add_endothelial_injury(amount: float) -> void:
	endothelial_injury = minf(100.0, endothelial_injury + amount)


# ── Disease API ───────────────────────────────────────────────────────────────

func trigger_trauma() -> void:
	# Debug: fast-forward cascade to embolism threshold
	stasis_score = 100.0
	endothelial_injury = 100.0
	tissue_factor = 0.0
	factor_7 = 0.0
	factor_7a = 100.0
	tf_viia = 100.0
	factor_10 = 0.0
	factor_10a = 100.0
	prothrombin = 20.0
	thrombin = 80.0
	fibrinogen = 20.0
	fibrin = 30.0
	crosslinkage = EMBOLISM_THRESHOLD


func apply_heparin() -> void:
	heparin_active = true


func resolve_heparin() -> void:
	heparin_active = false
