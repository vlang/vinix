// SPDX-License-Identifier: GPL-2.0-or-later
module main

// CodingKey.debugDescription forwards to the inherited CustomStringConvertible
// table at byte 16 of x1, then its description getter at byte 8. Preserve
// Self metadata x0, borrowed Self x20, nonthrowing x21 and the owned String
// result in x0/x1. The supplied witness owns formatting and result ownership;
// no CodingKey property, metadata, value bytes or reference count is read.
fn swift_coding_key_debug_description_emit(code u64) {
	write32(code, 0xf9400821) // ldr x1,[x1,#16]
	write32(code + 4, 0xf9400430) // ldr x16,[x1,#8]
	write32(code + 8, 0xd61f0200) // br x16
}

fn swift_coding_key_debug_description_symbol(symbol string) ?u64 {
	if symbol != '_$ss9CodingKeyPsE16debugDescriptionSSvg' || ios_runtime == unsafe { nil }
		|| ios_runtime.swift_concurrency_retired { return none }
	return swift_hash_entry(1888)
}
