// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the x86 frequency drivers write to their registers, as arithmetic.
//
// Three interfaces, each a model-specific register or three per logical CPU:
//
//   - Intel HWP, hardware-controlled performance states. The processor picks
//     its own operating point between a minimum and a maximum "performance
//     level" the system gives it, guided by an energy/performance preference.
//     Translated from drivers/cpufreq/intel_pstate.c.
//   - Intel Enhanced SpeedStep, where the system picks the ratio itself and
//     writes it to IA32_PERF_CTL. Also intel_pstate.c, its core_* functions.
//   - AMD CPPC through MSRs, which is HWP in AMD's layout. Translated from
//     drivers/cpufreq/amd-pstate.c in its MSR mode.
//
// The register layouts are those of arch/x86/include/asm/msr-index.h. Nothing
// here touches a register: these are functions of plain values, and
// tests/cpu-power runs them on the host. driver_amd64.v reads and writes.
module cpufreq

pub const msr_platform_info = u32(0xce)
pub const msr_mperf = u32(0xe7)
pub const msr_aperf = u32(0xe8)
pub const msr_perf_status = u32(0x198)
pub const msr_perf_ctl = u32(0x199)
pub const msr_misc_enable = u32(0x1a0)
pub const msr_turbo_ratio_limit = u32(0x1ad)
pub const msr_pm_enable = u32(0x770)
pub const msr_hwp_capabilities = u32(0x771)
pub const msr_hwp_interrupt = u32(0x773)
pub const msr_hwp_request = u32(0x774)
pub const msr_amd_cppc_cap1 = u32(0xc00102b0)
pub const msr_amd_cppc_enable = u32(0xc00102b1)
pub const msr_amd_cppc_req = u32(0xc00102b3)

// IA32_MISC_ENABLE: Enhanced SpeedStep is switched on; turbo is switched off.
pub const misc_enable_speedstep = u64(1) << 16
pub const misc_enable_turbo_disable = u64(1) << 38

// One HWP performance level in kHz. A level is a bus ratio, 100 MHz, except
// on the performance cores of a hybrid processor, where intel_pstate.c's
// HYBRID_SCALING_FACTOR applies.
pub const khz_per_level = u64(100000)
pub const khz_per_level_hybrid_p = u64(78741)

// What is asked of a processor that manages its own performance: a floor, a
// ceiling, a level to hold (0 lets it choose) and a preference, 0 for
// performance to 255 for energy.
pub struct PerfRequest {
pub mut:
	lowest     u32
	highest    u32
	desired    u32
	preference u32
}

// The preference as Intel's HWP takes it: HWP_EPP_* in msr-index.h.
pub fn intel_epp(preference Preference) u32 {
	return match preference {
		.performance { u32(0x00) }
		.balance_performance { u32(0x80) }
		.balance_power { u32(0xc0) }
		.power { u32(0xff) }
	}
}

// And as AMD's CPPC takes it: AMD_CPPC_EPP_* in include/linux/amd-pstate.h.
pub fn amd_epp(preference Preference) u32 {
	return match preference {
		.performance { u32(0x00) }
		.balance_performance { u32(0x80) }
		.balance_power { u32(0xbf) }
		.power { u32(0xff) }
	}
}

fn within(value u32, lowest u32, highest u32) u32 {
	if value < lowest {
		return lowest
	}
	if value > highest {
		return highest
	}
	return value
}

// ── Intel HWP ───────────────────────────────────────────────────────────────

// IA32_HWP_CAPABILITIES.
pub struct HwpCaps {
pub:
	highest        u32
	guaranteed     u32
	most_efficient u32
	lowest         u32
}

pub fn hwp_caps(value u64) HwpCaps {
	return HwpCaps{
		highest:        u32(value & 0xff)
		guaranteed:     u32((value >> 8) & 0xff)
		most_efficient: u32((value >> 16) & 0xff)
		lowest:         u32((value >> 24) & 0xff)
	}
}

// The level for a ceiling of `khz`: rounded down, so that a limit is never
// exceeded by the rounding.
pub fn level_at_most(khz u64, per_level u64) u32 {
	if per_level == 0 {
		return 0
	}
	level := khz / per_level
	return if level > 255 { u32(255) } else { u32(level) }
}

// The level for a floor of `khz`: rounded up, as intel_pstate_freq_to_hwp()
// rounds.
pub fn level_at_least(khz u64, per_level u64) u32 {
	if per_level == 0 {
		return 0
	}
	level := (khz + per_level - 1) / per_level
	return if level > 255 { u32(255) } else { u32(level) }
}

// What to ask of HWP for a policy whose allowed range is `lowest_khz` to
// `highest_khz`.
//
//	performance   floor raised to the ceiling, preference 0: as
//	              intel_pstate_hwp_set() does for CPUFREQ_POLICY_PERFORMANCE
//	powersave     ceiling lowered to the floor
//	ondemand      the range as it is and the policy's preference; the
//	              processor follows the load itself, better than a sample
//	              every 100 ms could
//
// The desired level is always 0: the processor chooses within the range.
pub fn hwp_plan(governor Governor, preference Preference, caps HwpCaps, per_level u64, lowest_khz u64, highest_khz u64) PerfRequest {
	hardware_lowest := if caps.lowest > caps.highest { caps.highest } else { caps.lowest }
	mut top := within(level_at_most(highest_khz, per_level), hardware_lowest, caps.highest)
	mut bottom := within(level_at_least(lowest_khz, per_level), hardware_lowest, top)
	mut epp := intel_epp(preference)
	match governor {
		.performance {
			bottom = top
			epp = intel_epp(.performance)
		}
		.powersave {
			top = bottom
			epp = intel_epp(.power)
		}
		.ondemand {}
	}
	return PerfRequest{
		lowest:     bottom
		highest:    top
		desired:    0
		preference: epp
	}
}

// IA32_HWP_REQUEST for `request`, starting from the register's `previous`
// value so that the activity window is kept. The preference field is written
// only where CPUID says there is one (CPUID.6:EAX[10]); the package-control
// bit is cleared, since this request is this logical CPU's own.
pub fn hwp_request(previous u64, request PerfRequest, has_preference bool) u64 {
	mut value := previous & ~u64(0xffffff)
	value |= u64(request.lowest & 0xff)
	value |= u64(request.highest & 0xff) << 8
	value |= u64(request.desired & 0xff) << 16
	if has_preference {
		value &= ~(u64(0xff) << 24)
		value |= u64(request.preference & 0xff) << 24
	}
	value &= ~(u64(1) << 42)
	return value
}

// The fields of an IA32_HWP_REQUEST, for reading one back.
pub fn hwp_request_fields(value u64) PerfRequest {
	return PerfRequest{
		lowest:     u32(value & 0xff)
		highest:    u32((value >> 8) & 0xff)
		desired:    u32((value >> 16) & 0xff)
		preference: u32((value >> 24) & 0xff)
	}
}

// ── Intel Enhanced SpeedStep ────────────────────────────────────────────────

// The family 6 models intel_pstate.c drives through MSR_PLATFORM_INFO and
// IA32_PERF_CTL: the entries of intel_pstate_cpu_ids[] that use core_funcs.
// Those two registers and MSR_TURBO_RATIO_LIMIT have no CPUID bit of their
// own, and a register that is not there is a fault, so the list is the gate.
pub fn speedstep_model(model u32) bool {
	return match model {
		0x2a, 0x2d { true } // SANDYBRIDGE, SANDYBRIDGE_X
		0x3a, 0x3e { true } // IVYBRIDGE, IVYBRIDGE_X
		0x3c, 0x3f, 0x45, 0x46 { true } // HASWELL, _X, _L, _G
		0x3d, 0x47, 0x4f, 0x56 { true } // BROADWELL, _G, _X, _D
		0x4e, 0x5e, 0x55 { true } // SKYLAKE_L, SKYLAKE, SKYLAKE_X
		0x5c, 0x7a { true } // ATOM_GOLDMONT, ATOM_GOLDMONT_PLUS
		0xa5, 0x6a, 0x8d, 0x8f { true } // COMETLAKE, ICELAKE_X, TIGERLAKE, SAPPHIRERAPIDS_X
		else { false }
	}
}

// The ratios a processor offers, each 100 MHz.
pub struct SpeedStep {
pub:
	// The lowest ratio, and the highest without turbo.
	lowest  u32
	nominal u32
	// The highest with turbo; `nominal` when there is none.
	turbo u32
	// Turbo is not available: the processor has none, or firmware has
	// switched it off. intel_pstate.c's turbo_is_disabled().
	turbo_disabled bool
}

// core_get_min_pstate(), core_get_max_pstate_physical() and
// core_get_turbo_pstate(). `has_turbo` is CPUID.6:EAX[1]. The configurable
// TDP levels core_get_max_pstate() also consults are not: the registers they
// are in cannot be read safely here.
pub fn speedstep(platform_info u64, turbo_ratio_limit u64, misc_enable u64, has_turbo bool) SpeedStep {
	nominal := u32((platform_info >> 8) & 0xff)
	mut turbo := u32(turbo_ratio_limit & 0xff)
	if turbo <= nominal {
		turbo = nominal
	}
	return SpeedStep{
		lowest:         u32((platform_info >> 40) & 0xff)
		nominal:        nominal
		turbo:          turbo
		turbo_disabled: !has_turbo || misc_enable & misc_enable_turbo_disable != 0
	}
}

// The highest ratio that can be asked for.
pub fn speedstep_highest(s SpeedStep) u32 {
	return if s.turbo_disabled { s.nominal } else { s.turbo }
}

// The ratio for a governor's target of `wanted_khz`, which may not exceed
// `highest_khz`: intel_pstate_prepare_request()'s clamp.
pub fn speedstep_ratio(s SpeedStep, wanted_khz u64, highest_khz u64) u32 {
	ceiling := within(level_at_most(highest_khz, khz_per_level), s.lowest, speedstep_highest(s))
	return within(level_at_least(wanted_khz, khz_per_level), s.lowest, ceiling)
}

// IA32_PERF_CTL for `ratio`: core_get_val(). Bit 32 tells the processor not
// to engage turbo. intel_pstate sets it when the system does not want turbo
// and the processor would otherwise use it; here the system does not want it
// when the allowed ceiling is no higher than the nominal ratio.
pub fn perf_ctl(s SpeedStep, ratio u32, highest_khz u64) u64 {
	mut value := u64(ratio & 0xff) << 8
	no_turbo := level_at_most(highest_khz, khz_per_level) <= s.nominal
	if no_turbo && !s.turbo_disabled {
		value |= u64(1) << 32
	}
	return value
}

// The ratio in force, from IA32_PERF_STATUS.
pub fn perf_status_ratio(value u64) u32 {
	return u32((value >> 8) & 0xff)
}

// ── AMD CPPC ────────────────────────────────────────────────────────────────

// MSR_AMD_CPPC_CAP1.
pub struct CppcCaps {
pub:
	lowest           u32
	lowest_nonlinear u32
	nominal          u32
	highest          u32
}

pub fn cppc_caps(value u64) CppcCaps {
	return CppcCaps{
		lowest:           u32(value & 0xff)
		lowest_nonlinear: u32((value >> 8) & 0xff)
		nominal:          u32((value >> 16) & 0xff)
		highest:          u32((value >> 24) & 0xff)
	}
}

// The frequency of a CPPC level. CPPC's levels are abstract; what ties them
// to a frequency is that the nominal level runs at the nominal frequency,
// which is how amd_get_max_freq() scales them.
pub fn cppc_khz(caps CppcCaps, nominal_khz u64, level u32) u64 {
	if caps.nominal == 0 {
		return 0
	}
	return nominal_khz * u64(level) / u64(caps.nominal)
}

// What to ask of CPPC for a policy whose allowed range is `lowest_khz` to
// `highest_khz`, as amd_pstate_epp_update_limit() works it out: under the
// performance governor the floor is the nominal level (or the ceiling when
// that is lower), not the ceiling itself, and the preference is 0.
pub fn cppc_plan(governor Governor, preference Preference, caps CppcCaps, nominal_khz u64, lowest_khz u64, highest_khz u64) PerfRequest {
	if caps.nominal == 0 || nominal_khz == 0 {
		return PerfRequest{
			lowest:  caps.lowest
			highest: caps.highest
		}
	}
	hardware_lowest := if caps.lowest > caps.highest { caps.highest } else { caps.lowest }
	// Scaled by the highest level over its frequency, as Linux scales
	// (policy->max * highest_perf / max_freq), so that the top of the range
	// comes back as exactly the highest level; by the nominal pair it would
	// come back one short.
	top_khz := cppc_khz(caps, nominal_khz, caps.highest)
	if top_khz == 0 {
		return PerfRequest{
			lowest:  caps.lowest
			highest: caps.highest
		}
	}
	ceiling := highest_khz * u64(caps.highest) / top_khz
	floor := (lowest_khz * u64(caps.highest) + top_khz - 1) / top_khz
	mut top := within(if ceiling > 255 { u32(255) } else { u32(ceiling) }, hardware_lowest,
		caps.highest)
	mut bottom := within(if floor > 255 { u32(255) } else { u32(floor) }, hardware_lowest,
		top)
	mut epp := amd_epp(preference)
	match governor {
		.performance {
			bottom = if caps.nominal < top { caps.nominal } else { top }
			epp = amd_epp(.performance)
		}
		.powersave {
			top = bottom
			epp = amd_epp(.power)
		}
		.ondemand {}
	}
	return PerfRequest{
		lowest:     bottom
		highest:    top
		desired:    0
		preference: epp
	}
}

// MSR_AMD_CPPC_REQ for `request`: maximum in the low byte, then minimum,
// desired and preference -- the minimum and maximum the other way round from
// Intel's register. The rest of `previous` is kept.
pub fn cppc_request(previous u64, request PerfRequest) u64 {
	mut value := previous & ~u64(0xffffffff)
	value |= u64(request.highest & 0xff)
	value |= u64(request.lowest & 0xff) << 8
	value |= u64(request.desired & 0xff) << 16
	value |= u64(request.preference & 0xff) << 24
	return value
}

// ── APERF and MPERF ─────────────────────────────────────────────────────────

// The average frequency over an interval in which APERF advanced by `aperf`
// and MPERF by `mperf`. MPERF counts at the base frequency while the CPU
// runs and APERF at the frequency it really ran at, so their ratio scales the
// base. 0 when the CPU did not run at all, when there is nothing to say.
pub fn effective_khz(aperf u64, mperf u64, base_khz u64) u64 {
	if mperf == 0 {
		return 0
	}
	// Both counts are divided down first if the product would not fit.
	mut a := aperf
	mut m := mperf
	for a > u64(0xffffffff) || m > u64(0xffffffff) {
		a >>= 1
		m >>= 1
	}
	if m == 0 {
		return 0
	}
	return base_khz * a / m
}
