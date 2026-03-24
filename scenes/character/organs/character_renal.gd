extends Node

# Fluid compartments and GFR — ported from Renal_Dynamics GML (VitalSignsRevised2)

# Body
var body_mass: float = 75.0  # kg
var dry_mass: float = 0.0   # 40% of starting body_mass — floor when fully dehydrated

# Fluid compartments (mL)
var total_body_water: float = 0.0
var intracellular_fluid: float = 0.0
var extracellular_fluid: float = 0.0
var interstitial_fluid: float = 0.0
var plasma_fluid: float = 0.0

# Renal blood/plasma flow
var renal_blood_flow: float = 1200.0  # mL/min
var renal_plasma_flow: float = 0.0

# Filtration pressures (mmHg)
var hp_capillary: float = 60.0
var hp_bowman: float = 25.0
var op_capillary: float = 25.0
var op_bowman: float = 5.0
var efferent_arteriole_diameter: float = 20.0  # micrometers

var net_filtration: float = 0.0

# GFR
var filtration_fraction: float = 0.2
var gfr: float = 0.0
var ff: float = 0.0

# Creatinine
var plasma_creatinine: float = 0.01   # mg/mL
var urine_creatinine: float = 110.0   # mg/dL
var creatinine_clearance: float = 120.0  # mL/min
var urine_flow_rate: float = 1.0      # mL/min

# Hematocrit assumed normal — will wire to vitals/blood later
var hematocrit: float = 0.45

# Plasma solutes — fixed total amounts, concentration rises as plasma shrinks
var total_plasma_sodium: float = 0.0   # mmol
var total_plasma_glucose: float = 0.0  # mg
var total_plasma_bun: float = 0.0      # mg

# Derived plasma concentrations
var plasma_sodium: float = 138.0       # mEq/L
var plasma_glucose: float = 90.0       # mg/dL
var plasma_bun: float = 14.0           # mg/dL
var plasma_osmolality: float = 285.0   # mOsm/kg

# ICF solutes — fixed total, used to track ICF osmolality as volume changes
var total_icf_solutes: float = 0.0  # mOsm

const DEFAULT_ACTION_COST_ML: float = 0.434  # 2.5L/day ÷ 5760 turns/day
var pending_plasma_cost: float = DEFAULT_ACTION_COST_ML

var _organs: Node = null

func setup(organ_registry: Node) -> void:
	_organs = organ_registry


func _ready() -> void:
	# Compute baseline compartments and seed plasma_fluid once.
	dry_mass = body_mass * 0.4
	total_body_water = body_mass * 0.6 * 1000.0
	intracellular_fluid = (2.0 / 3.0) * total_body_water
	extracellular_fluid = (1.0 / 3.0) * total_body_water
	interstitial_fluid = (3.0 / 4.0) * extracellular_fluid
	plasma_fluid = (1.0 / 4.0) * extracellular_fluid

	# Seed plasma solute totals.
	var plasma_liters := plasma_fluid * 0.001
	var plasma_dl := plasma_fluid * 0.01
	total_plasma_sodium = plasma_sodium * plasma_liters
	total_plasma_glucose = plasma_glucose * plasma_dl
	total_plasma_bun = plasma_bun * plasma_dl
	# ICF solutes seeded at isotonic baseline — fixed, only volume changes.
	total_icf_solutes = intracellular_fluid * 0.001 * 285.0


func drink(amount_liters: float) -> void:
	# Oral water distributes into ECF. Split 1:3 plasma:interstitial (ECF ratio).
	var amount_ml := amount_liters * 1000.0
	plasma_fluid += amount_ml * 0.25
	interstitial_fluid += amount_ml * 0.75
	extracellular_fluid = plasma_fluid + interstitial_fluid
	total_body_water = intracellular_fluid + extracellular_fluid
	body_mass = maxf(dry_mass + (total_body_water / 1000.0), dry_mass)


func consume_action_cost() -> void:
	# Step 1: plasma loses free water.
	plasma_fluid -= pending_plasma_cost

	# Step 2: recalculate plasma osmolality immediately after loss
	# so the gradient is current before we compute the ICF shift.
	var plasma_liters := plasma_fluid * 0.001
	var current_plasma_osm := 285.0
	if plasma_liters > 0.0:
		var na := total_plasma_sodium / plasma_liters
		var gluc := total_plasma_glucose / (plasma_fluid * 0.01)
		var bun := total_plasma_bun / (plasma_fluid * 0.01)
		current_plasma_osm = (2.0 * na) + (gluc / 18.0) + (bun / 2.8)

	# Step 3: elevated ECF osmolality pulls water out of ICF into ECF.
	# Shift is proportional to the gradient. ICF osmolality is approximated
	# as 285 mOsm/kg at baseline — it rises as it loses volume too.
	var icf_osm := total_icf_solutes / (intracellular_fluid * 0.001) if intracellular_fluid > 0.0 else 285.0
	var gradient := current_plasma_osm - icf_osm
	var icf_shift := 0.0
	if gradient > 0.0:
		# Shift scaled by gradient magnitude. At 1-2% rise (~3-6 mOsm) a meaningful
		# but partial shift occurs. Capped at what ICF can provide.
		icf_shift = minf(pending_plasma_cost * (gradient / 285.0), intracellular_fluid)
		intracellular_fluid -= icf_shift
		plasma_fluid += icf_shift

	if plasma_fluid < 0.0:
		plasma_fluid = 0.0
	if intracellular_fluid < 0.0:
		intracellular_fluid = 0.0

	# Interstitial follows ECF proportionally (3:1 ratio within ECF is maintained).
	extracellular_fluid = plasma_fluid + interstitial_fluid
	interstitial_fluid = (3.0 / 4.0) * extracellular_fluid
	plasma_fluid = (1.0 / 4.0) * extracellular_fluid
	total_body_water = intracellular_fluid + extracellular_fluid
	body_mass = maxf(dry_mass + (total_body_water / 1000.0), dry_mass)
	pending_plasma_cost = DEFAULT_ACTION_COST_ML


func tick() -> void:
	# Compartment volumes are tracked live via consume_action_cost().
	# tick() recalculates concentrations, osmolality, GFR, and filtration pressures.

	# Recalculate concentrations from fixed solute totals and current plasma volume.
	var plasma_liters := plasma_fluid * 0.001
	var plasma_dl := plasma_fluid * 0.01
	if plasma_liters > 0.0:
		plasma_sodium = total_plasma_sodium / plasma_liters
		plasma_glucose = total_plasma_glucose / plasma_dl
		plasma_bun = total_plasma_bun / plasma_dl

	# Plasma osmolality: Posm = 2×Na + glucose/18 + BUN/2.8
	plasma_osmolality = (2.0 * plasma_sodium) + (plasma_glucose / 18.0) + (plasma_bun / 2.8)

	# RPF scales with plasma volume and MAP.
	# Baseline: 660 mL/min at 3750 mL plasma and MAP=93.
	# RPF is modulated by MAP and sympathetic tone.
	# Autoregulation keeps RPF near baseline across MAP 70–180 mmHg.
	# Below 70: perfusion falls with MAP (shock).
	# During exertion: sympathetic renal vasoconstriction reduces RPF ceiling.
	# At peak combat demand, RPF falls to ~70% of baseline (blood redistributed to muscle).
	var map_ratio := 1.0
	if _organs != null and _organs.cardiovascular != null:
		var map: float = _organs.cardiovascular.monitor.mean_arterial_pressure
		var sympathetic_suppression: float = _organs.autonomic._metabolic_svr_factor if _organs.autonomic != null else 0.0
		var rpf_ceiling: float = lerpf(1.0, 0.7, sympathetic_suppression)
		if map < 70.0:
			map_ratio = maxf(map / 70.0, 0.0)
		else:
			map_ratio = minf(1.0, rpf_ceiling)
	
	
	renal_plasma_flow = plasma_fluid * 0.176 * map_ratio
	renal_blood_flow = renal_plasma_flow / (1.0 - hematocrit)

	var efferent_effect := -(efferent_arteriole_diameter - 20.0)
	var h_gradient := hp_capillary - hp_bowman
	var o_gradient := op_capillary - op_bowman
	net_filtration = h_gradient - o_gradient - (efferent_effect / 30.0)

	# GFR calculated first so creatinine clearance uses current value.
	gfr = renal_plasma_flow * filtration_fraction + ((net_filtration - 15.0) / 2.0)
	ff = gfr / renal_plasma_flow if renal_plasma_flow > 0.0 else 0.0

	# Creatinine balance per turn (1 turn = 15 seconds = 0.25 min).
	# Production seeded at steady state: GFR_baseline × creatinine_baseline × 0.25 min.
	# GFR_baseline = 660 × 0.2 + (10-15)/2 = 132 - 2.5 = 129.5 mL/min
	# production = 129.5 × 0.01 × 0.25 = 0.324 mg/turn
	var production_per_turn := 0.324
	var clearance_per_turn := gfr * plasma_creatinine * 0.25
	var delta_mg := production_per_turn - clearance_per_turn
	if plasma_fluid > 0.0:
		plasma_creatinine += delta_mg / plasma_fluid
	if plasma_creatinine < 0.0:
		plasma_creatinine = 0.0
	urine_creatinine = gfr * plasma_creatinine * 1440.0  # mg/day cleared
