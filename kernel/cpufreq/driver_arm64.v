// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Frequency control on AArch64.
module cpufreq

// Find this machine's frequency control. `cpus` is how many CPUs there are.
//
// An AArch64 CPU has no register that says how fast it runs, and a virtual
// machine's device tree does not either, so without a driver the frequencies
// are 0: not known.
fn driver_start(cpus int) {
	cpufreq_driver.name = 'none'
	for cpu_number in 0 .. cpus {
		add_policy(u64(1) << u32(cpu_number), Limits{}, .performance, .performance, 0)
	}
}
