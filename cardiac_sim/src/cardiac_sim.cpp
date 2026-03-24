#include "cardiac_sim.h"
#include <cmath>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

CardiacSim::CardiacSim() {}

CardiacSim::~CardiacSim() {
    if (_thread.joinable()) _thread.join();
}

void CardiacSim::_bind_methods() {
    ClassDB::bind_method(D_METHOD("tick_turn"),       &CardiacSim::tick_turn);
    ClassDB::bind_method(D_METHOD("tick_turn_async"), &CardiacSim::tick_turn_async);
    ClassDB::bind_method(D_METHOD("is_done"),         &CardiacSim::is_done);
    ClassDB::bind_method(D_METHOD("initialize"),      &CardiacSim::initialize);
    ClassDB::bind_method(D_METHOD("force_fire"),      &CardiacSim::force_fire);
    ClassDB::bind_method(D_METHOD("apply_tone", "effective_sym", "effective_vagal", "metabolic_svr_factor"), &CardiacSim::apply_tone);

    ClassDB::bind_method(D_METHOD("get_bp_systolic"),            &CardiacSim::get_bp_systolic);
    ClassDB::bind_method(D_METHOD("get_bp_diastolic"),           &CardiacSim::get_bp_diastolic);
    ClassDB::bind_method(D_METHOD("get_heart_rate"),             &CardiacSim::get_heart_rate);
    ClassDB::bind_method(D_METHOD("get_cardiac_output"),         &CardiacSim::get_cardiac_output);
    ClassDB::bind_method(D_METHOD("get_mean_arterial_pressure"), &CardiacSim::get_mean_arterial_pressure);
    ClassDB::bind_method(D_METHOD("get_sv"),                     &CardiacSim::get_sv);
    ClassDB::bind_method(D_METHOD("get_edv"),                    &CardiacSim::get_edv);
    ClassDB::bind_method(D_METHOD("get_esv"),                    &CardiacSim::get_esv);
    ClassDB::bind_method(D_METHOD("get_spo2"),                   &CardiacSim::get_spo2);
    ClassDB::bind_method(D_METHOD("get_venous_return_fraction"), &CardiacSim::get_venous_return_fraction);

    ClassDB::bind_method(D_METHOD("set_spo2", "v"),                   &CardiacSim::set_spo2);
    ClassDB::bind_method(D_METHOD("set_venous_return_fraction", "v"), &CardiacSim::set_venous_return_fraction);
}

// ─────────────────────────────────────────────────────────────────────────────
// INITIALIZE — mirrors character_cardiovascular.tscn exported values
// ─────────────────────────────────────────────────────────────────────────────
void CardiacSim::initialize() {
    // Left ventricle — matches LeftHeart/Ventricle + Myocytes in .tscn
    lv.e_min = 0.06f; lv.e_max = 2.5f; lv.e_rise_rate = 20.0f; lv.e_decay_rate = 48.0f;
    lv.v0 = 10.0f; lv.volume = 126.0f; lv.valve_conductance = 40.0f;
    lv.myocytes.fascicle_count = 3; lv.myocytes.regions_per_fascicle = 3;
    lv.myocytes.region_count = 9;
    lv.myocytes.sweep_duration = 0.0375f;
    lv.myocytes.durations[0]=0.0025f; lv.myocytes.durations[1]=0.00625f;
    lv.myocytes.durations[2]=0.125f;  lv.myocytes.durations[3]=0.1f; lv.myocytes.durations[4]=0.0f;
    lv.myocytes.forces[0]=0.1f; lv.myocytes.forces[1]=0.4f;
    lv.myocytes.forces[2]=1.0f; lv.myocytes.forces[3]=0.25f; lv.myocytes.forces[4]=0.0f;
    lv.elastance = lv.e_min;
    lv.pressure = lv.elastance * _maxf(0.0f, lv.volume - lv.v0);

    // Right ventricle — matches RightHeart/Ventricle + Myocytes in .tscn
    rv.e_min = 0.05f; rv.e_max = 1.2f; rv.e_rise_rate = 4.8f; rv.e_decay_rate = 4.8f;
    rv.v0 = 10.0f; rv.volume = 86.7f; rv.valve_conductance = 40.0f;
    rv.myocytes.fascicle_count = 3; rv.myocytes.regions_per_fascicle = 3;
    rv.myocytes.region_count = 9;
    rv.myocytes.sweep_duration = 0.0375f;
    rv.myocytes.durations[0]=0.0025f; rv.myocytes.durations[1]=0.00625f;
    rv.myocytes.durations[2]=0.125f;  rv.myocytes.durations[3]=0.1f; rv.myocytes.durations[4]=0.0f;
    rv.myocytes.forces[0]=0.1f; rv.myocytes.forces[1]=0.4f;
    rv.myocytes.forces[2]=1.0f; rv.myocytes.forces[3]=0.25f; rv.myocytes.forces[4]=0.0f;
    rv.elastance = rv.e_min;
    rv.pressure = rv.elastance * _maxf(0.0f, rv.volume - rv.v0);

    // Left atrium — matches LeftHeart/Atria in .tscn; myocytes use GDScript defaults
    la.e_min = 0.10f; la.e_max = 0.60f; la.e_rise_rate = 4.0f; la.e_decay_rate = 2.4f;
    la.v0 = 10.0f; la.volume = 59.9f; la.valve_conductance = 20.0f;
    la.myocytes.fascicle_count = 1; la.myocytes.regions_per_fascicle = 3;
    la.myocytes.region_count = 3;
    la.myocytes.sweep_duration = 0.08f;
    la.myocytes.durations[0]=0.002f; la.myocytes.durations[1]=0.005f;
    la.myocytes.durations[2]=0.073f; la.myocytes.durations[3]=0.060f; la.myocytes.durations[4]=0.0f;
    la.myocytes.forces[0]=0.1f; la.myocytes.forces[1]=0.4f;
    la.myocytes.forces[2]=1.0f; la.myocytes.forces[3]=0.25f; la.myocytes.forces[4]=0.0f;
    la.elastance = la.e_min;
    la.pressure = la.elastance * _maxf(0.0f, la.volume - la.v0);
    la.valve_open = true;

    // Right atrium — matches RightHeart/Atria in .tscn; myocytes use GDScript defaults
    ra.e_min = 0.25f; ra.e_max = 0.67f; ra.e_rise_rate = 4.0f; ra.e_decay_rate = 2.4f;
    ra.v0 = 8.0f; ra.volume = 30.4f; ra.valve_conductance = 48.0f;
    ra.myocytes.fascicle_count = 1; ra.myocytes.regions_per_fascicle = 3;
    ra.myocytes.region_count = 3;
    ra.myocytes.sweep_duration = 0.08f;
    ra.myocytes.durations[0]=0.002f; ra.myocytes.durations[1]=0.005f;
    ra.myocytes.durations[2]=0.073f; ra.myocytes.durations[3]=0.060f; ra.myocytes.durations[4]=0.0f;
    ra.myocytes.forces[0]=0.1f; ra.myocytes.forces[1]=0.4f;
    ra.myocytes.forces[2]=1.0f; ra.myocytes.forces[3]=0.25f; ra.myocytes.forces[4]=0.0f;
    ra.elastance = ra.e_min;
    ra.pressure = ra.elastance * _maxf(0.0f, ra.volume - ra.v0);
    ra.valve_open = true;

    // Mitral — contraction_rate from .tscn
    mitral.use_systole_guard = true;
    mitral.contraction_rate  = 96.0f;

    // Aortic
    aortic.use_latch             = true;
    aortic.use_waveform_tracking = true;
    aortic.notch_dip             = 2.0f;
    aortic.open_threshold        = 0.0f;

    // Tricuspid — contraction_rate from .tscn
    tricuspid.use_systole_guard = true;
    tricuspid.contraction_rate  = 144.0f;

    // Conduction delays from .tscn (conduction_duration exports)
    atrial_tract.delay = 0.08f;
    av_node.delay      = 0.06f;
    his.delay          = 0.01f;
    purkinje.delay     = 0.02f;

    // Vessels — from GDScript defaults
    vena_cava.volume            = 3633.4f;
    vena_cava.unstressed_volume = 3023.0f;
    pulm_vein.volume            = 433.5f;
}

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────
void CardiacSim::force_fire() {
    // Immediately fire SA node — used for KP_4 single-beat debug
    _trigger_atrial_sweep();
    sa.beat_period         = 1.0f;
    sa.time_since_beat     = 0.0f;
    sa.fired_count        += 1;
}

void CardiacSim::tick_turn() {
    for (int i = 0; i < TURN_STEPS; ++i) {
        _tick(SIM_STEP);
    }

    if (sa.beat_period > 0.0f) {
        heart_rate             = 60.0f / sa.beat_period;
        monitor.cardiac_output = (monitor.SV * heart_rate) / 1000.0f;
    } else {
        monitor.cardiac_output = 0.0f;
    }
}

void CardiacSim::tick_turn_async() {
    if (_thread.joinable()) _thread.join();
    _thread_done.store(false);
    _thread = std::thread([this]() {
        tick_turn();
        _thread_done.store(true);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// INNER TICK
// ─────────────────────────────────────────────────────────────────────────────
void CardiacSim::_tick(float delta) {
    _tick_sa(delta);
    _tick_atrial_conduction(delta);
    _tick_ventricular_conduction(delta);

    _tick_chamber(lv, delta);
    _tick_chamber(rv, delta);
    _tick_chamber(la, delta);
    _tick_chamber(ra, delta);

    _step_valves(delta);

    lv.pressure = lv.elastance * _maxf(0.0f, lv.volume - lv.v0);
    rv.pressure = rv.elastance * _maxf(0.0f, rv.volume - rv.v0);
    la.pressure = la.elastance * _maxf(0.0f, la.volume - la.v0);
    ra.pressure = ra.elastance * _maxf(0.0f, ra.volume - ra.v0);

    vena_cava.volume += _tick_aorta(delta);
    monitor.aorta_pressure = aorta.pressure;

    // Pulmonary artery — simplified: drains into pulm_vein proportionally
    if (rv.valve_open) {
        float pa_flow = _maxf(0.0f, (rv.pressure - 15.0f) * 8.0f * delta);
        pa_flow = _minf(pa_flow, _maxf(0.0f, rv.volume - rv.v0));
        rv.volume -= pa_flow;
        pulm_vein.volume += pa_flow;
    }

    _step_heart();
}

// ─────────────────────────────────────────────────────────────────────────────
// SA NODE
// ─────────────────────────────────────────────────────────────────────────────
void CardiacSim::_tick_sa(float delta) {
    sa.time_since_beat += delta;

    if (sa.cardioplegia) { sa.ic_k = 500.0f; return; }

    switch (sa.state) {
        case 0: // PHASE_4
            if (sa.membrane_potential < -40.0f && sa.ic_na < 20.0f) {
                sa.ic_na += sa.na_slope * delta;
            } else if (sa.membrane_potential >= -40.0f && sa.membrane_potential < 10.0f && sa.ic_ca < 50.0f) {
                sa.ic_ca += (50.0f / 0.05f) * delta;
            }
            sa.membrane_potential = -130.0f + sa.ic_na + sa.ic_ca + sa.ic_k;
            if (sa.membrane_potential >= 10.0f) {
                sa.state = 1;
            }
            break;

        case 1: // PHASE_0 — fire
            sa.beat_period     = sa.time_since_beat;
            sa.time_since_beat = 0.0f;
            sa.fired_count    += 1;
            sa.state           = 2;
            // Trigger atrial conduction
            atrial_tract.active   = true;
            atrial_tract.timer    = 0.0f;
            atrial_tract.conducted = false;
            break;

        case 2: // PHASE_3
            if (sa.ic_k > 0.0f) {
                sa.ic_k -= (80.0f / 0.04f) * delta;
            }
            if (sa.ic_k <= 0.0f) {
                sa.ic_na = 0.0f; sa.ic_ca = 0.0f; sa.ic_k = 70.0f;
                sa.membrane_potential = -60.0f;
                sa.state = 0;
            }
            break;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONDUCTION
// ─────────────────────────────────────────────────────────────────────────────
void CardiacSim::_tick_atrial_conduction(float delta) {
    if (!atrial_tract.active) return;
    atrial_tract.timer += delta;
    if (!atrial_tract.conducted && atrial_tract.timer >= atrial_tract.delay) {
        atrial_tract.conducted = true;
        // Fire atrial sweep
        _trigger_atrial_sweep();
        // Start AV node
        av_node.active    = true;
        av_node.timer     = 0.0f;
        av_node.conducted = false;
    }
}

void CardiacSim::_tick_ventricular_conduction(float delta) {
    if (av_node.active) {
        av_node.timer += delta;
        if (!av_node.conducted && av_node.timer >= av_node.delay) {
            av_node.conducted = true;
            his.active = true; his.timer = 0.0f; his.conducted = false;
        }
    }
    if (his.active) {
        his.timer += delta;
        if (!his.conducted && his.timer >= his.delay) {
            his.conducted = true;
            purkinje.active = true; purkinje.timer = 0.0f; purkinje.conducted = false;
        }
    }
    if (purkinje.active) {
        purkinje.timer += delta;
        if (!purkinje.conducted && purkinje.timer >= purkinje.delay) {
            purkinje.conducted = true;
            ventricular_depolarization_pending = true;
            // Unlock aortic valve latch
            aortic.latched   = false;
            pulmonic.latched = false;
            // Trigger ventricular sweep
            _trigger_ventricular_sweep();
        }
    }
}

void CardiacSim::_trigger_atrial_sweep() {
    auto trigger = [](MyocytesState &m) {
        m.sweep_active   = true;
        m.sweep_fascicle = 0;
        m.sweep_region   = 0;
        m.sweep_timer    = 0.0f;
        for (int i = 0; i < m.region_count; ++i) {
            m.regions[i].phase = 4;
            m.regions[i].timer = 0.0f;
            m.regions[i].mechanical = 0;
        }
    };
    trigger(la.myocytes);
    trigger(ra.myocytes);
}

void CardiacSim::_trigger_ventricular_sweep() {
    auto trigger = [](MyocytesState &m) {
        m.sweep_active   = true;
        m.sweep_fascicle = 0;
        m.sweep_region   = 0;
        m.sweep_timer    = 0.0f;
        for (int i = 0; i < m.region_count; ++i) {
            m.regions[i].phase = 4;
            m.regions[i].timer = 0.0f;
            m.regions[i].mechanical = 0;
        }
    };
    trigger(lv.myocytes);
    trigger(rv.myocytes);
}

// ─────────────────────────────────────────────────────────────────────────────
// CHAMBER
// ─────────────────────────────────────────────────────────────────────────────
void CardiacSim::_tick_chamber(ChamberState &ch, float delta) {
    _step_myocytes(ch.myocytes, delta);
    _step_elastance(ch, delta);
}

void CardiacSim::_step_myocytes(MyocytesState &m, float delta) {
    m.active_force = 0.0f;
    for (int i = 0; i < m.region_count; ++i) {
        MyocyteRegion &r = m.regions[i];
        if (r.phase == 4) continue;
        r.timer      += delta;
        m.active_force += m.forces[r.phase];
        float dur = m.durations[r.phase];
        if (dur > 0.0f && r.timer >= dur) {
            float overflow = r.timer - dur;
            if (r.phase < 3) {
                r.phase += 1;
                r.timer  = overflow;
            } else {
                r.phase      = 4;
                r.timer      = 0.0f;
                r.mechanical = 0;
            }
        }
    }
    // Update in_systole
    bool any = false;
    for (int i = 0; i < m.region_count; ++i) {
        if (m.regions[i].mechanical == 1) { any = true; break; }
    }
    m.prev_in_systole = m.in_systole;
    m.in_systole = any;
    if (m.sweep_active) _step_sweep(m, delta);
}

void CardiacSim::_step_sweep(MyocytesState &m, float delta) {
    float time_per_fascicle = m.sweep_duration / (float)m.fascicle_count;
    float time_per_region   = time_per_fascicle / (float)m.regions_per_fascicle;
    m.sweep_timer += delta;

    while (m.sweep_active) {
        if (m.sweep_timer < time_per_region) break;
        m.sweep_timer -= time_per_region;
        int idx = m.sweep_fascicle * m.regions_per_fascicle + m.sweep_region;
        m.regions[idx].phase      = 0;
        m.regions[idx].timer      = 0.0f;
        m.regions[idx].mechanical = 1;
        m.sweep_region++;
        if (m.sweep_region >= m.regions_per_fascicle) {
            m.sweep_region = 0;
            m.sweep_fascicle++;
            if (m.sweep_fascicle >= m.fascicle_count) {
                m.sweep_active = false;
            }
        }
    }
}

void CardiacSim::_step_elastance(ChamberState &ch, float delta) {
    float nf = ch.myocytes.active_force / (float)ch.myocytes.region_count;
    if (nf > 0.0f) {
        ch.elastance = _minf(ch.e_max, ch.elastance + nf * ch.e_rise_rate * delta);
    } else {
        ch.elastance = _maxf(ch.e_min, ch.elastance - ch.e_decay_rate * delta);
    }
    ch.pressure = ch.elastance * _maxf(0.0f, ch.volume - ch.v0);
}

// ─────────────────────────────────────────────────────────────────────────────
// VALVES
// ─────────────────────────────────────────────────────────────────────────────
void CardiacSim::_step_valves(float delta) {
    monitor.pcwp = la.pressure;

    // Pulmonary vein → LA
    la.volume += _tick_pulm_vein(delta);
    // Vena cava → RA
    ra.volume += _tick_vena_cava(delta);

    _tick_mitral(delta);
    la.volume = _maxf(la.v0, la.volume);

    _tick_aortic(delta);
    aorta.volume += aortic.flow;

    _tick_tricuspid(delta);
    ra.volume = _maxf(ra.v0, ra.volume);

    // Pulmonic handled in main tick via simplified PA
}

void CardiacSim::_tick_mitral(float delta) {
    bool lv_systole = lv.pressure > la.pressure;

    if (mitral.use_systole_guard) {
        if (lv_systole && (lv.pressure > la.pressure + 1.0f)) {
            if (la.valve_open) {
                la.valve_open = false;
                monitor.EDV   = lv.volume;
            }
        } else if (!lv_systole) {
            if (!la.valve_open && lv.pressure <= la.pressure + 1.0f) {
                la.valve_open = true;
            }
        }
    }

    if (la.valve_open) {
        // Active contraction flow
        if (mitral.contraction_rate > 0.0f && la.myocytes.active_force > 0.0f) {
            float active = (mitral.contraction_rate / (float)la.myocytes.region_count)
                           * la.myocytes.active_force * delta;
            active       = _minf(active, _maxf(0.0f, la.volume - la.v0));
            la.volume   -= active;
            lv.volume   += active;
        }
        // Passive flow
        float passive = _maxf(0.0f, (la.pressure - lv.pressure) * la.valve_conductance * delta);
        passive        = _minf(passive, _maxf(0.0f, la.volume - la.v0));
        la.volume     -= passive;
        lv.volume     += passive;
    }
}

void CardiacSim::_tick_aortic(float delta) {
    aortic.notch_fired = false;
    aortic.flow        = 0.0f;
    bool prev_open = aortic.was_open;

    if (!lv.valve_open && !aortic.latched) {
        if (lv.pressure >= aorta.pressure + aortic.open_threshold) {
            lv.valve_open = true;
        }
    }
    if (lv.valve_open) {
        if (lv.pressure < aorta.pressure) {
            lv.valve_open = false;
            if (aortic.use_latch) aortic.latched = true;
            monitor.ESV = lv.volume;
        }
    }

    if (lv.valve_open) {
        aortic.flow = _maxf(0.0f, (lv.pressure - aorta.pressure) * lv.valve_conductance * delta);
        aortic.flow = _minf(aortic.flow, _maxf(0.0f, lv.volume - lv.v0));
        lv.volume  -= aortic.flow;
    }

    aortic.was_open    = lv.valve_open;
    aortic.notch_fired = prev_open && !lv.valve_open;

    // Waveform tracking
    if (aortic.use_waveform_tracking) {
        if (lv.valve_open) {
            aortic.cycle_peak = _maxf(aortic.cycle_peak, aorta.pressure);
            if (!prev_open && aortic.cycle_min < 999.0f) {
                monitor.bp_diastolic = aortic.cycle_min;
                aortic.cycle_min = 999.0f;
            }
        } else {
            aortic.cycle_min = _minf(aortic.cycle_min, aorta.pressure);
            if (aortic.notch_fired) {
                monitor.bp_systolic  = aortic.cycle_peak;
                aortic.cycle_peak    = 0.0f;
            }
        }
    }
}

void CardiacSim::_tick_tricuspid(float delta) {
    bool rv_systole = rv.pressure > ra.pressure;

    if (rv_systole && (rv.pressure > ra.pressure + 1.0f)) {
        if (ra.valve_open) {
            ra.valve_open = false;
        }
    } else if (!rv_systole) {
        if (!ra.valve_open && rv.pressure <= ra.pressure + 1.0f) {
            ra.valve_open = true;
        }
    }

    if (ra.valve_open) {
        if (tricuspid.contraction_rate > 0.0f && ra.myocytes.active_force > 0.0f) {
            float active = (tricuspid.contraction_rate / (float)ra.myocytes.region_count)
                           * ra.myocytes.active_force * delta;
            active       = _minf(active, _maxf(0.0f, ra.volume - ra.v0));
            ra.volume   -= active;
            rv.volume   += active;
        }
        float passive = _maxf(0.0f, (ra.pressure - rv.pressure) * ra.valve_conductance * delta);
        passive        = _minf(passive, _maxf(0.0f, ra.volume - ra.v0));
        ra.volume     -= passive;
        rv.volume     += passive;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// VESSELS
// ─────────────────────────────────────────────────────────────────────────────
float CardiacSim::_tick_aorta(float delta) {
    aorta.blood_flow     = lv.valve_open;
    aorta.blood_flow_end = aortic.notch_fired;

    aorta.pressure = _maxf(0.0f, (aorta.volume - AortaState::UNSTRESSED_VOLUME) / AortaState::COMPLIANCE);

    float outflow = _maxf(0.0f, aorta.pressure / aorta.systemic_resistance * delta);
    outflow        = _minf(outflow, _maxf(0.0f, aorta.volume - AortaState::UNSTRESSED_VOLUME));
    aorta.volume  -= outflow;

    aorta.pressure = _maxf(0.0f, (aorta.volume - AortaState::UNSTRESSED_VOLUME) / AortaState::COMPLIANCE);

    if (aortic.notch_fired) {
        aorta.pressure = _maxf(0.0f, aorta.pressure - aortic.notch_dip);
    }

    aorta.pressure = _clampf(aorta.pressure, aorta.pressure_min, aorta.pressure_max);
    return outflow;
}

float CardiacSim::_tick_vena_cava(float delta) {
    float vc_pressure = _maxf(0.0f, (vena_cava.volume - vena_cava.unstressed_volume) / VenaCavaState::COMPLIANCE);
    float flow = _maxf(0.0f, (vc_pressure - ra.pressure) * vena_cava.to_ra_conductance * delta);
    flow = _minf(flow, _maxf(0.0f, vena_cava.volume - vena_cava.unstressed_volume));
    vena_cava.volume -= flow;
    return flow * venous_return_fraction;
}

float CardiacSim::_tick_pulm_vein(float delta) {
    float pv_pressure = _maxf(0.0f, (pulm_vein.volume - PulmonaryVeinState::UNSTRESSED_VOLUME) / PulmonaryVeinState::COMPLIANCE);
    float flow = _maxf(0.0f, (pv_pressure - la.pressure) * PulmonaryVeinState::TO_LA_CONDUCTANCE * delta);
    flow = _minf(flow, _maxf(0.0f, pulm_vein.volume - PulmonaryVeinState::UNSTRESSED_VOLUME));
    pulm_vein.volume -= flow;
    return flow;
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP HEART
// ─────────────────────────────────────────────────────────────────────────────
void CardiacSim::_step_heart() {
    monitor.SV             = _maxf(0.0f, monitor.EDV - monitor.ESV);
    monitor.EF             = (monitor.EDV > 0.0f) ? (monitor.SV / monitor.EDV) * 100.0f : 0.0f;
    monitor.cardiac_output = sa.cardioplegia ? 0.0f : (monitor.SV * heart_rate) / 1000.0f;
    monitor.mean_arterial_pressure = monitor.bp_diastolic + (monitor.bp_systolic - monitor.bp_diastolic) / 3.0f;
    monitor.pulse_pressure         = monitor.bp_systolic - monitor.bp_diastolic;
}

// ─────────────────────────────────────────────────────────────────────────────
// APPLY TONE — called by GDScript CharacterANS each turn.
// effective_sym   [0, 1] — net sympathetic drive (baroreflex + central command)
// effective_vagal [0, 1] — net vagal drive (1.0 = resting, 0.0 = fully withdrawn)
// metabolic_svr_factor [0, 1] — local exercise vasodilation
// ─────────────────────────────────────────────────────────────────────────────
void CardiacSim::apply_tone(float effective_sym, float effective_vagal, float metabolic_svr_factor) {
    // SA node: sym raises na_slope, vagal lowers it.
    // At rest (sym=0, vagal=1): baseline. At max sym: MAX. At max vagal withdrawal: MIN.
    sa.na_slope = _lerpf(BASELINE_NA_SLOPE, MAX_NA_SLOPE, effective_sym);
    sa.na_slope = _lerpf(sa.na_slope, MIN_NA_SLOPE, 1.0f - effective_vagal);

    // Ventricular inotropy/lusitropy — sym only (vagal has negligible ventricular effect)
    lv.e_max        = _lerpf(BASELINE_LV_EMAX,  MAX_LV_EMAX,  effective_sym);
    rv.e_max        = _lerpf(BASELINE_RV_EMAX,  MAX_RV_EMAX,  effective_sym);
    lv.e_rise_rate  = _lerpf(BASELINE_LV_ERISE,  MAX_LV_ERISE,  effective_sym);
    lv.e_decay_rate = _lerpf(BASELINE_LV_EDECAY, MAX_LV_EDECAY, effective_sym);

    // LA valve conductance — sym only
    la.valve_conductance = _lerpf(BASELINE_LA_COND, MAX_LA_COND, effective_sym);

    // SVR: sym raises resistance (vasoconstriction); metabolic vasodilation opposes.
    // At rest (sym=0, metabolic=0): baseline. At sym=1: 2x baseline.
    float baseline_svr = AortaState::BASELINE_SYSTEMIC_RESISTANCE;
    float max_svr      = baseline_svr * 2.0f;
    float min_svr      = baseline_svr * 0.50f;
    float raw_svr      = _lerpf(baseline_svr, max_svr, effective_sym)
                         - (baseline_svr * metabolic_svr_factor * 0.5f);
    aorta.systemic_resistance = _clampf(raw_svr, min_svr, max_svr);

    // Venous tone: sym causes venoconstriction (lower unstressed volume → more preload)
    vena_cava.unstressed_volume = _lerpf(VenaCavaState::BASELINE_UNSTRESSED_VOLUME,
                                          VenaCavaState::BASELINE_UNSTRESSED_VOLUME * 0.85f,
                                          effective_sym);
    vena_cava.to_ra_conductance = _lerpf(VenaCavaState::BASELINE_TO_RA_CONDUCTANCE,
                                          VenaCavaState::BASELINE_TO_RA_CONDUCTANCE * 2.0f,
                                          effective_sym);
}

} // namespace godot
