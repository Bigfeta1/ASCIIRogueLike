#pragma once
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <thread>
#include <atomic>

namespace godot {

// ── SA Node ──────────────────────────────────────────────────────────────────
struct SaNodeState {
    float membrane_potential = -60.0f;
    float ic_na              = 0.0f;
    float ic_ca              = 0.0f;
    float ic_k               = 70.0f;
    int   state              = 0;       // 0=PHASE_4, 1=PHASE_0, 2=PHASE_3
    bool  cardioplegia       = false;
    float na_slope           = 22.222f;
    float beat_period        = 1.0f;
    float time_since_beat    = 0.0f;
    int   fired_count        = 0;
};

// ── Myocyte region ───────────────────────────────────────────────────────────
struct MyocyteRegion {
    int   phase         = 4;
    float timer         = 0.0f;
    int   mechanical    = 0;
};

// ── Chamber myocytes ─────────────────────────────────────────────────────────
struct MyocytesState {
    static const int MAX_REGIONS = 16;
    MyocyteRegion regions[MAX_REGIONS];
    int   region_count       = 3;
    bool  in_systole         = false;
    bool  prev_in_systole    = false;
    float active_force       = 0.0f;

    bool  sweep_active       = false;
    int   sweep_fascicle     = 0;
    int   sweep_region       = 0;
    float sweep_timer        = 0.0f;

    int   fascicle_count        = 1;
    int   regions_per_fascicle  = 3;
    float sweep_duration        = 0.08f;

    float durations[5] = { 0.002f, 0.005f, 0.1f, 0.08f, 0.0f };
    float forces[5]    = { 0.1f,   0.4f,   1.0f, 0.25f, 0.0f };
};

// ── Cardiac chamber ──────────────────────────────────────────────────────────
struct ChamberState {
    float volume      = 0.0f;
    float elastance   = 0.0f;
    float pressure    = 0.0f;
    float e_min       = 0.20f;
    float e_max       = 0.60f;
    float e_rise_rate = 5.0f;
    float e_decay_rate= 3.0f;
    float v0          = 4.0f;
    float valve_conductance = 0.0f;
    bool  valve_open  = false;
    MyocytesState myocytes;
};

// ── Valve ────────────────────────────────────────────────────────────────────
struct ValveState {
    bool  use_systole_guard   = false;
    bool  use_latch           = false;
    bool  use_waveform_tracking = false;
    float open_threshold      = 0.0f;
    float notch_dip           = 0.0f;
    float contraction_rate    = 0.0f;
    float pressure_clamp_max  = 200.0f;

    bool  latched             = false;
    bool  was_open            = false;
    bool  notch_fired         = false;
    float flow                = 0.0f;

    float cycle_peak          = 0.0f;
    float cycle_min           = 999.0f;

    float bp_systolic_out     = 0.0f;
    float bp_diastolic_out    = 0.0f;

    float edv_out             = 0.0f;
    float esv_out             = 0.0f;
};

// ── Aorta ────────────────────────────────────────────────────────────────────
struct AortaState {
    float volume                      = 620.0f;
    float pressure                    = 80.0f;
    static constexpr float COMPLIANCE        = 1.59f;
    static constexpr float UNSTRESSED_VOLUME = 550.0f;
    static constexpr float BASELINE_SYSTEMIC_RESISTANCE = 1.26f;
    float systemic_resistance         = 1.26f;
    float pressure_min                = 8.0f;
    float pressure_max                = 200.0f;
    bool  blood_flow                  = false;
    bool  blood_flow_end              = false;
};

// ── Vena Cava ────────────────────────────────────────────────────────────────
struct VenaCavaState {
    float volume                       = 3665.0f;
    static constexpr float COMPLIANCE               = 50.0f;
    static constexpr float BASELINE_UNSTRESSED_VOLUME = 3023.0f;
    static constexpr float BASELINE_TO_RA_CONDUCTANCE = 14.3f;
    float unstressed_volume            = 3000.0f;
    float to_ra_conductance            = 14.3f;
};

// ── Pulmonary vein ───────────────────────────────────────────────────────────
struct PulmonaryVeinState {
    float volume             = 433.5f;
    static constexpr float UNSTRESSED_VOLUME  = 305.0f;
    static constexpr float COMPLIANCE         = 10.0f;
    static constexpr float TO_LA_CONDUCTANCE  = 23.0f;
};

// ── Monitor ──────────────────────────────────────────────────────────────────
struct MonitorState {
    float EDV                  = 0.0f;
    float ESV                  = 0.0f;
    float SV                   = 0.0f;
    float EF                   = 0.0f;
    float cardiac_output       = 0.0f;
    float bp_systolic          = 120.0f;
    float bp_diastolic         = 80.0f;
    float mean_arterial_pressure = 93.0f;
    float pulse_pressure       = 40.0f;
    float aorta_pressure       = 80.0f;
    float pcwp                 = 0.0f;
};

// ── Conduction component ─────────────────────────────────────────────────────
struct ConductionState {
    float timer        = 0.0f;
    float delay        = 0.0f;
    bool  active       = false;
    bool  conducted    = false;  // fires once when delay elapsed
};

// ── Main class ───────────────────────────────────────────────────────────────
class CardiacSim : public Node {
    GDCLASS(CardiacSim, Node)

public:
    static const int TURN_STEPS = 750;
    static constexpr float SIM_STEP     = 0.020f;
    static constexpr float BASELINE_CO  = 4.75f;
    static constexpr float MAX_CO       = 20.0f;
    static constexpr float CO_TOLERANCE = 0.03f;

    static constexpr float BASELINE_HR         = 60.0f;
    static constexpr float BASELINE_LV_EMAX    = 2.5f;
    static constexpr float MAX_LV_EMAX         = 4.5f;
    static constexpr float MIN_LV_EMAX         = 1.8f;
    static constexpr float BASELINE_LV_EDECAY  = 60.0f;
    static constexpr float MAX_LV_EDECAY       = 120.0f;
    static constexpr float BASELINE_RV_EMAX    = 1.2f;
    static constexpr float MAX_RV_EMAX         = 2.0f;
    static constexpr float MIN_RV_EMAX         = 0.9f;
    static constexpr float BASELINE_LA_COND    = 25.0f;
    static constexpr float MAX_LA_COND         = 55.0f;
    static constexpr float BASELINE_LV_ERISE   = 20.0f;
    static constexpr float MAX_LV_ERISE        = 130.0f;
    static constexpr float BASELINE_NA_SLOPE   = 23.0f;
    static constexpr float MAX_NA_SLOPE        = 80.6f;
    static constexpr float MIN_NA_SLOPE        = 11.11f;

    // Chambers
    ChamberState lv, rv, la, ra;

    // Valves
    ValveState mitral, aortic, tricuspid, pulmonic;

    // Vessels
    AortaState       aorta;
    VenaCavaState    vena_cava;
    PulmonaryVeinState pulm_vein;

    // Conduction
    SaNodeState      sa;
    ConductionState  atrial_tract;
    ConductionState  av_node;
    ConductionState  his;
    ConductionState  purkinje;

    bool ventricular_depolarization_pending = false;

    // Monitor
    MonitorState monitor;

    // Controller
    float heart_rate            = 60.0f;
    float demanded_co           = 5.0f;
    float demanded_co_pre_decay = 5.0f;
    float spo2                  = 99.0f;
    float venous_return_fraction = 1.0f;
    float _sym_tone_fast        = 0.0f;
    float _sym_tone_slow        = 0.0f;
    float sym_mod               = 1.0f;
    float parasym_recovery      = 1.0f;

    // Threading
    std::thread          _thread;
    std::atomic<bool>    _thread_done { true };

protected:
    static void _bind_methods();

private:
    void _tick(float delta);
    void _tick_sa(float delta);
    void _tick_atrial_conduction(float delta);
    void _tick_ventricular_conduction(float delta);
    void _tick_chamber(ChamberState &ch, float delta);
    void _step_myocytes(MyocytesState &m, float delta);
    void _step_sweep(MyocytesState &m, float delta);
    void _step_elastance(ChamberState &ch, float delta);
    void _step_valves(float delta);
    void _tick_mitral(float delta);
    void _tick_aortic(float delta);
    void _tick_tricuspid(float delta);
    void _tick_pulmonic(float delta);
    float _tick_aorta(float delta);
    float _tick_vena_cava(float delta);
    float _tick_pulm_vein(float delta);
    void _step_heart();
    void _apply_sympathetic_tone();
    void _trigger_atrial_sweep();
    void _trigger_ventricular_sweep();
    inline float _clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
    inline float _maxf(float a, float b) { return a > b ? a : b; }
    inline float _minf(float a, float b) { return a < b ? a : b; }
    inline float _lerpf(float a, float b, float t) { return a + (b - a) * t; }
    inline float _powf_concave(float x) {  // x^0.4
        return (float)pow((double)x, 0.4);
    }

public:
    CardiacSim();
    ~CardiacSim();
    void initialize();
    void tick_turn();
    void tick_turn_async();
    bool is_done() const { return _thread_done.load(); }
    void set_demand(float co);
    void force_fire();

    // Getters for GDScript
    float get_bp_systolic()          const { return monitor.bp_systolic; }
    float get_bp_diastolic()         const { return monitor.bp_diastolic; }
    float get_heart_rate()           const { return heart_rate; }
    float get_cardiac_output()       const { return monitor.cardiac_output; }
    float get_mean_arterial_pressure() const { return monitor.mean_arterial_pressure; }
    float get_sv()                   const { return monitor.SV; }
    float get_edv()                  const { return monitor.EDV; }
    float get_esv()                  const { return monitor.ESV; }
    float get_spo2()                 const { return spo2; }
    float get_demanded_co()          const { return demanded_co; }
    float get_demanded_co_pre_decay() const { return demanded_co_pre_decay; }
    float get_sym_tone_fast()        const { return _sym_tone_fast; }
    float get_sym_tone_slow()        const { return _sym_tone_slow; }
    float get_venous_return_fraction() const { return venous_return_fraction; }

    void  set_spo2(float v)                    { spo2 = v; }
    void  set_venous_return_fraction(float v)  { venous_return_fraction = v; }
    void  set_sym_mod(float v)                 { sym_mod = v; }
    void  set_parasym_recovery(float v)        { parasym_recovery = v; }
};

} // namespace godot
