// SPDX-License-Identifier: GPL-2.0-or-later
module main

// This is imported data: the GOT contains the address of one uintptr_t cell.
// Vinix uses aligned, plain-pointer isa headers, without Darwin's packed isa
// or pointer authentication. Keep every address bit, including guest mappings
// above the device's packed-isa range; only the class alignment bits are clear.
__global swift_isa_mask_value = u64(0xfffffffffffffff8)

fn swift_isa_mask_address() u64 {
	return u64(unsafe { &swift_isa_mask_value })
}
