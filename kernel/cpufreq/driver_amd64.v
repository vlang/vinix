// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Frequency control on x86-64.
module cpufreq

import cpuidle
import x86.cpu

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

// Find this machine's frequency control. `cpus` is how many CPUs there are.
fn driver_start(cpus int) {
	cpufreq_driver.name = 'none'
	khz := base_khz()
	for cpu_number in 0 .. cpus {
		add_policy(u64(1) << u32(cpu_number), Limits{
			hw_min_khz:  khz
			hw_max_khz:  khz
			nominal_khz: khz
		}, .performance, .performance, 0)
	}
}
