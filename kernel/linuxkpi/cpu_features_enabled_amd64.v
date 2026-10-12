// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import katomic
import lib
import memory

const feature_hw_shstk = u32(16 * 32 + 7)
const feature_active_la57 = u32(16 * 32 + 16)

__global (
	boot_infrastructure_bits  u32
	boot_infrastructure_count u32
	boot_infrastructure_ready u32
)

// The boot owner calls this after every CPU publishes its own capabilities
// and active CR4 mode. SHSTK is the original hardware capability, including
// its XSAVES/XSAVE prerequisites; USER_SHSTK/CET services are separate.
// LA57 describes the page tables actually installed, rather than raw CPUID.
fn initialise_cpu_infrastructure_features() {
	if katomic.load(&boot_infrastructure_ready) != 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: CPU infrastructure policy initialized twice')
	}
	count := cpu_locals.len
	if count < 1 || count > 256 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid CPU infrastructure membership')
	}
	// This native accessor reads memory.la57, selected from the actual Limine
	// paging response before CPU initialization. Its geometry has boot lifetime.
	active_la57 := memory.user_address_limit() == u64(1) << 56
	mut common_shstk := true
	for i in 0 .. count {
		local := cpu_locals[i]
		if local == unsafe { nil } || local.cpu_number != u64(i)
			|| katomic.load(&local.online) != 1 {
			lib.kpanic(unsafe { nil }, c'linuxkpi: CPU infrastructure member not acknowledged')
		}
		if local.linuxkpi_la57_active != active_la57 {
			lib.kpanic(unsafe { nil }, c'linuxkpi: CPU paging mode disagrees with native geometry')
		}
		common_shstk = common_shstk && local.linuxkpi_shstk_supported
	}
	mut bits := u32(0)
	if common_shstk { bits |= u32(1) << 7 }
	if active_la57 { bits |= u32(1) << 16 }
	boot_infrastructure_bits = bits
	boot_infrastructure_count = u32(count)
	// Publish last, including a legitimate empty hardware intersection. Native
	// CPU records and geometry remain permanent; topology changes need a new
	// coordinated policy and are outside this fixed boot-domain profile.
	katomic.store(mut &boot_infrastructure_ready, u32(1))
}

fn cpu_infrastructure_has(feature u32) bool {
	if feature != feature_hw_shstk && feature != feature_active_la57 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: unsupported CPU infrastructure feature')
	}
	if katomic.load(&boot_infrastructure_ready) != 1 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: CPU infrastructure policy not initialized')
	}
	return boot_infrastructure_bits & (u32(1) << (feature % 32)) != 0
}
