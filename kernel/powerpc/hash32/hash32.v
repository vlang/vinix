// SPDX-License-Identifier: GPL-2.0-or-later
module hash32

pub const bytes = u32(65536)

pub struct Pte {
pub mut:
	tag  u32
	page u32
}

pub fn primary(vsid u32, address u32) u32 {
	return (vsid ^ ((address >> 12) & 0xffff)) & 1023
}

pub fn tag(vsid u32, address u32, secondary bool) u32 {
	return 0x80000000 | ((vsid & 0xffffff) << 7) | (if secondary { u32(64) } else { u32(0) }) | ((address >> 22) & 63)
}

// Caller publishes PTE1, then sync, then PTE0 and invalidates the old TLB
// entry. This policy helper never overwrites another mapping on collision.
pub fn slot(table &Pte, vsid u32, address u32) int {
	group := primary(vsid, address)
	mut empty := -1
	for secondary in 0 .. 2 {
		first := (if secondary == 0 { group } else { group ^ 1023 }) * 8
		wanted := tag(vsid, address, secondary != 0)
		for i := first; i < first + 8; i++ {
			entry := unsafe { table[i].tag }
			if entry == wanted { return -1 } // duplicate mappings need explicit unmap
			if entry & 0x80000000 == 0 && empty == -1 { empty = int(i) }
		}
	}
	return empty
}
