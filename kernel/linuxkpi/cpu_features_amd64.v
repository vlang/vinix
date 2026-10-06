// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import katomic
import lib

const directstore_mask = (u32(1) << 27) | (u32(1) << 28)
const feature_movdiri = u32(16 * 32 + 27)
const feature_movdir64b = u32(16 * 32 + 28)

__global (
	boot_directstore_bits u32
	boot_directstore_count u32
	boot_directstore_ready u32
)

// Called once by the boot owner after all native CPUs acknowledge their
// initialization. Native Local records and CPU membership have boot lifetime;
// hotplug or feature-policy replacement requires a different protocol.
fn initialise_cpu_features() {
	if katomic.load(&boot_directstore_ready) != 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: CPU feature policy initialized twice')
	}
	count := cpu_locals.len
	if count < 1 || count > 256 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid CPU feature policy membership')
	}
	mut common := directstore_mask
	for i in 0 .. count {
		local := cpu_locals[i]
		if local == unsafe { nil } || local.cpu_number != u64(i)
			|| katomic.load(&local.online) != 1 {
			lib.kpanic(unsafe { nil }, c'linuxkpi: CPU feature member not acknowledged')
		}
		common &= local.directstore_ecx & directstore_mask
	}
	boot_directstore_bits = common
	boot_directstore_count = u32(count)
	// Publish last, including a valid empty intersection. Queries acquire this
	// slot before reading immutable data and never borrow a live current CPU.
	katomic.store(mut &boot_directstore_ready, u32(1))
}

fn directstore_has(feature u32) bool {
	if feature != feature_movdiri && feature != feature_movdir64b {
		lib.kpanic(unsafe { nil }, c'linuxkpi: unsupported CPU feature in word sixteen')
	}
	if katomic.load(&boot_directstore_ready) != 1 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: CPU feature policy not initialized')
	}
	return boot_directstore_bits & (u32(1) << (feature % 32)) != 0
}
