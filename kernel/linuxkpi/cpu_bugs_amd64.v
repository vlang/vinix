// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import katomic
import lib

const bug_l1tf = u32(22 * 32 + 18)

__global (
	boot_l1tf_sample u32
	boot_bug_count   u32
	boot_bug_ready   u32
)

// Called once by the boot owner after every native CPU has acknowledged its
// initialization. x86.smp installs the BSP as logical CPU zero. Linux derives
// L1TF from the BSP and copies forced bug bits to APs; this query preserves
// that boot-CPU meaning rather than inventing an all-CPU vulnerability union.
// Other samples validate completed boot observation, not migration immunity.
fn initialise_cpu_bugs() {
	if katomic.load(&boot_bug_ready) != 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: CPU bug policy initialized twice')
	}
	count := cpu_locals.len
	if count < 1 || count > 256 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid CPU bug policy membership')
	}
	for i in 0 .. count {
		local := cpu_locals[i]
		if local == unsafe { nil } || local.cpu_number != u64(i)
			|| katomic.load(&local.online) != 1 {
			lib.kpanic(unsafe { nil }, c'linuxkpi: CPU bug member not acknowledged')
		}
		if local.linuxkpi_l1tf_sample != 1 && local.linuxkpi_l1tf_sample != 2 {
			lib.kpanic(unsafe { nil }, c'linuxkpi: unresolved CPU L1TF observation')
		}
	}
	boot_l1tf_sample = cpu_locals[0].linuxkpi_l1tf_sample
	boot_bug_count = u32(count)
	// The fixed boot membership and samples have permanent lifetime. Readers
	// acquire readiness before immutable scalars, without borrowing a CPU/task.
	katomic.store(mut &boot_bug_ready, u32(1))
}

@[export: 'vinix_linuxkpi_boot_cpu_has_bug']
fn boot_cpu_has_bug(bug u32) bool {
	if bug != bug_l1tf {
		lib.kpanic(unsafe { nil }, c'linuxkpi: unsupported CPU bug query')
	}
	if katomic.load(&boot_bug_ready) != 1 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: CPU bug policy not initialized')
	}
	return boot_l1tf_sample == 2
}
