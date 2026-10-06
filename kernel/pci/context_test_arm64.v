// SPDX-License-Identifier: GPL-2.0-only
module pci

#include "pci_config.h"
#include "pci_config_arm_test.h"

$if pci_config_test ? {
	fn C.vinix_pci_config_read(u32, u32, u32, u32, u64, u32, &u32) i32
	fn C.vinix_pci_config_write(u32, u32, u32, u32, u64, u32, u32) i32

	fn fixture_daif_read() u64 {
		mut flags := u64(0)
		asm volatile aarch64 {
			mrs flags, daif
			; =r (flags)
			; ; memory
		}
		return flags
	}

	fn fixture_daif_write(flags u64) {
		asm volatile aarch64 {
			msr daif, flags
			; ; r (flags)
			; memory
		}
	}

	@[export: 'vinix_pci_config_arm_context_selftest']
	pub fn context_selftest() i32 {
		unsafe {
			mut slots := [2]u32{}
			mut identities := [2]u32{}
			mut found := u32(0)
			for slot := u32(0); slot < 32 && found < 2; slot++ {
				mut identity := u32(0)
				if C.vinix_pci_config_read(0, 0, slot, 0, 0, 4, &identity) != 0 { return 1 }
				if identity & 0xffff != 0xffff {
					slots[found] = slot
					identities[found] = identity
					found++
				}
			}
			if found != 2 { return 2 }
			original := fixture_daif_read()
			mut result := i32(0)
			for mask := u32(0); mask < 8; mask++ {
				state := u64(0x80) | (u64(mask & 1) << 6) | (u64(mask & 2) << 7) | (u64(mask & 4) << 7)
				fixture_daif_write(state)
				for device in 0 .. 2 {
					for width := u32(1); width <= 4; width *= 2 {
						for offset := u32(0); offset < 4; offset += width {
							mut value := u32(0x5aa55aa5)
							mut expected := identities[device] >> (offset * 8)
							if width < 4 { expected &= (u32(1) << (width * 8)) - 1 }
							if C.vinix_pci_config_read(0, 0, slots[device], 0, u64(offset), width, &value) != 0
								|| value != expected {
								result = 3
							}
							if fixture_daif_read() != state { result = 4 }
						}
					}
				}
				mut value := u32(0x5aa55aa5)
				if C.vinix_pci_config_read(0, 0, slots[0], 0, 1, 2, &value) != 1 || value != 0x5aa55aa5
					|| C.vinix_pci_config_read(0, 0, slots[0], 0, u64(0x100000000), 4, &value) != 1 || value != 0x5aa55aa5
					|| C.vinix_pci_config_write(0, 0, slots[0], 0, 4096, 4, u32(-1)) != 1 {
					result = 5
				}
				if fixture_daif_read() != state { result = 4 }
			}
			fixture_daif_write(original)
			return result
		}
	}
}
