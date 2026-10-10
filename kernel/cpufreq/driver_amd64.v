// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Frequency control on x86-64: Intel HWP, Intel Enhanced SpeedStep and AMD
// CPPC, each a few model-specific registers per logical CPU. What goes into
// the registers is worked out in registers_amd64.v; this file is where they
// are read and written, and that is the awkward part.
//
// A register that is not there is a fault
//
// RDMSR or WRMSR of a register the processor does not have raises #GP, and
// this kernel has no way to catch one: it panics. So every register below is
// touched only behind what enumerates it:
//
//	IA32_PM_ENABLE, IA32_HWP_*        CPUID.6:EAX[7]
//	IA32_HWP_INTERRUPT                CPUID.6:EAX[8]
//	the preference in IA32_HWP_REQUEST CPUID.6:EAX[10]
//	IA32_APERF, IA32_MPERF            CPUID.6:ECX[0]
//	MSR_AMD_CPPC_*                    CPUID.80000008:EBX[27]
//	MSR_PLATFORM_INFO, MSR_TURBO_RATIO_LIMIT, IA32_PERF_CTL, IA32_PERF_STATUS
//	    no CPUID bit. An Intel family 6 model on intel_pstate.c's list
//	    (speedstep_model()), with CPUID.1:ECX[7], and not in a virtual
//	    machine, which shows a host's model number without its registers.
//	IA32_MISC_ENABLE                  the same condition
//
// A register is written on its own CPU
//
// These registers are per logical CPU, and there is one way to write CPU 3's:
// execute WRMSR on CPU 3. Linux sends it there with a cross-call. This kernel
// has no cross-call that carries work, only the scheduler's interrupt, so the
// write is done from there: the worker, on whichever CPU it runs, leaves the
// value and counts a generation up; each CPU compares generations when it
// passes through the scheduler's interrupt (cpu_tick()) and writes its own
// register if it is behind. A busy CPU passes at the end of every time slice
// and an idle one at least every 20 ms, so a new request is in force within a
// tick, well inside the worker's 100 ms.
//
// The same pass does what else must run there: the one-time enabling of HWP
// or CPPC and reading of the capabilities, which differ between the cores of
// a hybrid processor, and the APERF/MPERF readings scaling_cur_freq is worked
// out from.
//
// None of this has run on hardware. Every virtual machine this kernel is
// tested in shows none of the CPUID bits above, and gets the driver "none";
// the arithmetic is tested on the host (tests/cpu-power).
//
// What can be run in a virtual machine is everything but the registers.
// vinix.cpufreq=simulate starts a driver, "simulated", that goes the whole
// way SpeedStep goes -- policies, worker, a value left for each CPU, each CPU
// writing its own on its pass through the scheduler -- with a word of memory
// per CPU in place of IA32_PERF_CTL and made-up ratios of 8 to 30. The
// frequencies it reports are not the machine's. It is there so that
// tests/cpu-power can watch a request reach every CPU.
@[has_globals]
module cpufreq

import cpuidle
import devcore
import katomic
import x86.cpu
import x86.msr

enum X86Control {
	absent
	hwp
	speedstep
	cppc
	// SpeedStep's path with memory for registers; see the top of the file.
	simulated
}

// What one logical CPU knows about its own registers. `ready` and everything
// read from the hardware is written by that CPU alone, in cpu_tick() with
// interrupts off; `wanted` and `generation` by the worker.
struct CpuControl {
mut:
	// Set last, once the capabilities below have been read.
	ready u32
	// IA32_HWP_CAPABILITIES or MSR_AMD_CPPC_CAP1.
	capabilities u64
	// The request register as it was found: what a new value starts from.
	found_request u64
	// MSR_PLATFORM_INFO, MSR_TURBO_RATIO_LIMIT and IA32_MISC_ENABLE.
	platform_info u64
	turbo_limit   u64
	misc_enable   u64
	// kHz per HWP level on this core.
	per_level u64
	// The value its request register should hold, and how many times that
	// has changed; the generation the register was last written at.
	wanted     u64
	generation u32
	applied    u32
	// Whether the policy has taken this CPU's range yet. The worker's.
	adopted bool
	// APERF, MPERF and IA32_PERF_STATUS as last read here. `sequence` is odd
	// while they are being replaced.
	sequence u32
	aperf    u64
	mperf    u64
	status   u64
	// The simulated driver's stand-in for IA32_PERF_CTL.
	pretend u64
	// What the reader of scaling_cur_freq last saw, and made of it.
	seen_aperf u64
	seen_mperf u64
	seen_khz   u64
}

__global (
	cpufreq_x86_control X86Control
	cpufreq_x86_cpus    [max_cpus]CpuControl
	// CPUID.6:ECX[0], CPUID.6:EAX[8], CPUID.6:EAX[10], CPUID.6:EAX[1], and
	// CPUID.7:EDX[15] for a hybrid processor.
	cpufreq_x86_aperf      bool
	cpufreq_x86_hwp_notify bool
	cpufreq_x86_hwp_epp    bool
	cpufreq_x86_turbo      bool
	cpufreq_x86_hybrid     bool
	cpufreq_x86_base_khz   u64
)

// The frequency the processor runs at when nothing scales it, in kHz: the
// base frequency CPUID leaf 0x16 names, or the TSC's rate, which is that
// frequency on every processor whose TSC is invariant and is all a virtual
// machine can measure. /proc/cpuinfo's "cpu MHz" is found the same way.
fn base_khz() u64 {
	named, base_mhz, _, _, _ := cpu.cpuid(0x16, 0)
	if named && base_mhz & 0xffff != 0 {
		return u64(base_mhz & 0xffff) * 1000
	}
	return cpuidle.tsc_hz() / 1000
}

// This CPU's pass through the scheduler's interrupt: see the top of the file.
// With interrupts off, on the CPU itself. One load and a branch on a machine
// with no driver.
@[inline]
pub fn cpu_tick(cpu_number u64) {
	if cpufreq_x86_control != .absent && cpu_number < max_cpus {
		cpu_service(cpu_number)
	}
}

fn cpu_service(cpu_number u64) {
	mut me := unsafe { &cpufreq_x86_cpus[cpu_number] }
	if me.ready == 0 {
		cpu_setup(mut me)
	}
	if cpufreq_x86_aperf || cpufreq_x86_control == .speedstep || cpufreq_x86_control == .simulated {
		// Odd while the three are replaced, so a reader on another CPU can
		// tell a mixed set from a whole one.
		me.sequence++
		if cpufreq_x86_aperf {
			me.aperf = msr.rdmsr(msr_aperf)
			me.mperf = msr.rdmsr(msr_mperf)
		}
		if cpufreq_x86_control == .speedstep {
			me.status = msr.rdmsr(msr_perf_status)
		} else if cpufreq_x86_control == .simulated {
			me.status = me.pretend
		}
		me.sequence++
	}
	generation := katomic.load(&me.generation)
	if generation == me.applied {
		return
	}
	value := katomic.load(&me.wanted)
	match cpufreq_x86_control {
		.hwp { msr.wrmsr(msr_hwp_request, value) }
		.speedstep { msr.wrmsr(msr_perf_ctl, value) }
		.cppc { msr.wrmsr(msr_amd_cppc_req, value) }
		.simulated { me.pretend = value }
		.absent {}
	}
	me.applied = generation
}

// The first pass: switch the interface on and read what this core can do.
fn cpu_setup(mut me CpuControl) {
	match cpufreq_x86_control {
		.hwp {
			// intel_pstate_hwp_enable(): no notification interrupts, since
			// nothing handles them, then HWP on. It stays on until reset.
			if cpufreq_x86_hwp_notify {
				msr.wrmsr(msr_hwp_interrupt, 0)
			}
			msr.wrmsr(msr_pm_enable, 1)
			me.capabilities = msr.rdmsr(msr_hwp_capabilities)
			me.found_request = msr.rdmsr(msr_hwp_request)
			me.per_level = khz_per_level
			if cpufreq_x86_hybrid {
				// hwp_get_cpu_scaling(): CPUID.1A:EAX[31:24] is 0x40 on a
				// performance core.
				typed, kind, _, _, _ := cpu.cpuid(0x1a, 0)
				if typed && kind >> 24 == 0x40 {
					me.per_level = khz_per_level_hybrid_p
				}
			}
		}
		.speedstep {
			me.platform_info = msr.rdmsr(msr_platform_info)
			me.turbo_limit = msr.rdmsr(msr_turbo_ratio_limit)
			me.misc_enable = msr.rdmsr(msr_misc_enable)
		}
		.cppc {
			// pstate_enable() and pstate_init_perf().
			msr.wrmsr(msr_amd_cppc_enable, 1)
			me.capabilities = msr.rdmsr(msr_amd_cppc_cap1)
			me.found_request = msr.rdmsr(msr_amd_cppc_req)
		}
		.simulated {
			// Ratios 8 to 24, 30 with turbo, in the registers' own layouts.
			me.platform_info = (u64(8) << 40) | (u64(24) << 8)
			me.turbo_limit = 30
			me.misc_enable = 0
		}
		.absent {}
	}
	katomic.store(mut &me.ready, u32(1))
}

fn speedstep_of(me &CpuControl) SpeedStep {
	return speedstep(me.platform_info, me.turbo_limit, me.misc_enable, cpufreq_x86_turbo)
}

// Take the range the CPU read for itself into its policy. With the lock.
fn adopt(mut policy Policy, me &CpuControl) {
	mut limits := Limits{}
	match cpufreq_x86_control {
		.hwp {
			caps := hwp_caps(me.capabilities)
			limits.hw_min_khz = u64(caps.lowest) * me.per_level
			limits.hw_max_khz = u64(caps.highest) * me.per_level
			limits.nominal_khz = u64(caps.guaranteed) * me.per_level
		}
		.speedstep, .simulated {
			s := speedstep_of(me)
			limits.hw_min_khz = u64(s.lowest) * khz_per_level
			limits.hw_max_khz = u64(speedstep_highest(s)) * khz_per_level
			limits.nominal_khz = u64(s.nominal) * khz_per_level
		}
		.cppc {
			caps := cppc_caps(me.capabilities)
			limits.hw_min_khz = cppc_khz(caps, cpufreq_x86_base_khz, caps.lowest)
			limits.hw_max_khz = cppc_khz(caps, cpufreq_x86_base_khz, caps.highest)
			limits.nominal_khz = cpufreq_x86_base_khz
		}
		.absent {}
	}
	if limits.hw_max_khz == 0 || limits.hw_min_khz > limits.hw_max_khz {
		// Capabilities that make no sense: leave the policy at the base
		// frequency it started with rather than act on them.
		return
	}
	limits.user_min_khz = limits.hw_min_khz
	limits.user_max_khz = limits.hw_max_khz
	policy.limits = limits
}

// The driver's apply(): work out the policy's register value and leave it
// for the CPU to write. With the lock.
fn x86_apply(_ int, mut policy Policy) {
	mut me := unsafe { &cpufreq_x86_cpus[policy.first_cpu] }
	if katomic.load(&me.ready) == 0 {
		// The CPU has not been through the scheduler since the driver
		// started. The worker comes back.
		return
	}
	first := !me.adopted
	if first {
		adopt(mut policy, me)
		me.adopted = true
		policy.wanted_khz = policy.limits.hw_max_khz
	}
	lowest, highest := allowed_range(policy.limits, thermal_limit())
	if first {
		policy.wanted_khz = target_khz(policy.governor, policy.preference, policy.utilisation,
			lowest, highest)
	}
	value := match cpufreq_x86_control {
		.hwp {
			hwp_request(me.found_request, hwp_plan(policy.governor, policy.preference,
				hwp_caps(me.capabilities), me.per_level, lowest, highest), cpufreq_x86_hwp_epp)
		}
		.speedstep, .simulated {
			s := speedstep_of(me)
			perf_ctl(s, speedstep_ratio(s, policy.wanted_khz, highest), highest)
		}
		.cppc {
			cppc_request(me.found_request, cppc_plan(policy.governor, policy.preference,
				cppc_caps(me.capabilities), cpufreq_x86_base_khz, lowest, highest))
		}
		.absent {
			u64(0)
		}
	}
	if first || value != me.wanted {
		katomic.store(mut &me.wanted, value)
		katomic.inc(mut &me.generation)
	}
}

// The driver's current(): the frequency the CPU has averaged since this was
// last asked, from APERF and MPERF where there are any.
fn x86_current(_ int, policy &Policy) u64 {
	mut me := unsafe { &cpufreq_x86_cpus[policy.first_cpu] }
	if katomic.load(&me.ready) == 0 {
		return 0
	}
	mut aperf := u64(0)
	mut mperf := u64(0)
	mut status := u64(0)
	for {
		before := katomic.load(&me.sequence)
		aperf = me.aperf
		mperf = me.mperf
		status = me.status
		if before & 1 == 0 && katomic.load(&me.sequence) == before {
			break
		}
	}
	if cpufreq_x86_aperf {
		// Two readers at once only lose each other's interval.
		khz := effective_khz(aperf - me.seen_aperf, mperf - me.seen_mperf, cpufreq_x86_base_khz)
		if khz != 0 {
			me.seen_aperf = aperf
			me.seen_mperf = mperf
			me.seen_khz = khz
		}
		if me.seen_khz != 0 {
			return me.seen_khz
		}
	}
	if cpufreq_x86_control == .speedstep || cpufreq_x86_control == .simulated {
		return u64(perf_status_ratio(status)) * khz_per_level
	}
	return 0
}

// Find this machine's frequency control. `cpus` is how many CPUs there are.
fn driver_start(cpus int) {
	cpufreq_driver.name = 'none'
	cpufreq_x86_base_khz = base_khz()
	for cpu_number in 0 .. cpus {
		add_policy(u64(1) << u32(cpu_number), Limits{
			hw_min_khz:  cpufreq_x86_base_khz
			hw_max_khz:  cpufreq_x86_base_khz
			nominal_khz: cpufreq_x86_base_khz
		}, .ondemand, .balance_performance, 0)
	}
	control := detect()
	if control == .absent {
		// The CPUs run at their one frequency, which is what "performance"
		// means.
		for i in 0 .. cpufreq_policy_count {
			cpufreq_policies[i].governor = .performance
			cpufreq_policies[i].preference = .performance
		}
		return
	}
	cpufreq_driver.name = match control {
		.hwp { 'intel_hwp' }
		.speedstep { 'intel_speedstep' }
		.cppc { 'amd_cppc' }
		.simulated { 'simulated' }
		.absent { 'none' }
	}
	cpufreq_driver.settable = true
	cpufreq_driver.has_preference = (control == .hwp && cpufreq_x86_hwp_epp) || control == .cppc
	cpufreq_driver.apply = x86_apply
	cpufreq_driver.current = x86_current
	C.kprintf(c'cpufreq: driver %s, base %llu kHz\n', cpufreq_driver.name.str, cpufreq_x86_base_khz)
	// Last: from here every CPU's next scheduler interrupt sets it up.
	cpufreq_x86_control = control
}

// Which interface this processor has, by the conditions at the top of the
// file. Read on the CPU that publishes /sys and taken to hold for all.
fn detect() X86Control {
	if choice := devcore.boot_option('vinix.cpufreq=') {
		if choice == 'off' {
			print('cpufreq: switched off by vinix.cpufreq=off\n')
			return .absent
		}
		if choice == 'simulate' {
			print('cpufreq: simulated driver by vinix.cpufreq=simulate; its frequencies are not real\n')
			cpufreq_x86_aperf = false
			cpufreq_x86_turbo = true
			return .simulated
		}
	}
	_, _, vendor_b, vendor_c, vendor_d := cpu.cpuid(0, 0)
	intel := vendor_b == 0x756e6547 && vendor_d == 0x49656e69 && vendor_c == 0x6c65746e
	amd := vendor_b == 0x68747541 && vendor_d == 0x69746e65 && vendor_c == 0x444d4163
	_, signature, _, features, _ := cpu.cpuid(1, 0)
	mut family := (signature >> 8) & 0xf
	mut model := (signature >> 4) & 0xf
	if family == 0xf {
		family += (signature >> 20) & 0xff
	}
	if family == 6 || family >= 0xf {
		model += ((signature >> 16) & 0xf) << 4
	}
	virtual := features & (u32(1) << 31) != 0
	leaf6, thermal_a, _, thermal_c, _ := cpu.cpuid(6, 0)
	if leaf6 {
		cpufreq_x86_aperf = thermal_c & 1 != 0
		cpufreq_x86_turbo = thermal_a & (u32(1) << 1) != 0
		cpufreq_x86_hwp_notify = thermal_a & (u32(1) << 8) != 0
		cpufreq_x86_hwp_epp = thermal_a & (u32(1) << 10) != 0
	}
	leaf7, _, _, _, structured_d := cpu.cpuid(7, 0)
	cpufreq_x86_hybrid = leaf7 && structured_d & (u32(1) << 15) != 0

	if intel && leaf6 && thermal_a & (u32(1) << 7) != 0 {
		return .hwp
	}
	if intel && family == 6 && speedstep_model(model) && features & (u32(1) << 7) != 0
		&& !virtual {
		// Firmware can leave SpeedStep switched off, and then IA32_PERF_CTL
		// is not to be written.
		if msr.rdmsr(msr_misc_enable) & misc_enable_speedstep != 0 {
			return .speedstep
		}
		print('cpufreq: Enhanced SpeedStep is switched off in IA32_MISC_ENABLE\n')
		return .absent
	}
	extended, _, extended_b, _, _ := cpu.cpuid(0x80000008, 0)
	if amd && extended && extended_b & (u32(1) << 27) != 0 {
		return .cppc
	}
	return .absent
}
