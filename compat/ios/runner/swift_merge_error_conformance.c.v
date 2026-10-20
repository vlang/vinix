// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Concrete witnesses for the frozen, payload-free keyCollision case. Indirect
// Self has no bytes, so none of these operations reads x20. The returned
// String is an owned immortal literal; userInfo is an owned empty dictionary.
fn swift_merge_error_domain() SwiftStringWords {
	return swift_string_literal(c'Swift._MergeError', 17, true)
}

fn swift_merge_error_code() u64 { return 0 }

fn swift_merge_error_user_info() u64 {
	return objc_allocate(ios_runtime.names['NSDictionary'])
}

fn swift_merge_error_embedded() u64 { return 0 }

// Reuse the enum's RX/RO allocation. An indirect protocol reference keeps the
// relative descriptor local even when the shared Error arena is far away.
fn swift_merge_error_conformance_emit(code u64, data u64, protocol u64) {
	descriptor := data + 288
	table := data + 320
	slot := data + 368
	swift_protocol_relative(descriptor, slot)
	write32(descriptor, read32(descriptor) | 1)
	swift_protocol_relative(descriptor + 4, data + 192)
	swift_protocol_relative(descriptor + 8, table)
	unsafe {
		*(&u64(slot)) = protocol
		*(&u64(table)) = descriptor
	}
	for i, target in [u64(unsafe { voidptr(swift_merge_error_domain) }),
		u64(unsafe { voidptr(swift_merge_error_code) }),
		u64(unsafe { voidptr(swift_merge_error_user_info) }),
		u64(unsafe { voidptr(swift_merge_error_embedded) })]! {
		entry := code + 32 + u64(i * 24)
		write32(entry, 0x58000050) // ldr x16,literal at +8
		write32(entry + 4, 0xd61f0200) // br x16; ordinary C preserves x20/x21.
		unsafe {
			*(&u64(entry + 8)) = target
			*(&u64(table + 8 + u64(i * 8))) = entry
		}
	}
}

fn swift_merge_error_table_checked(metadata u64) !u64 {
	if ios_runtime == unsafe { nil } { return swift_merge_error_metadata_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	base := ios_runtime.swift_merge_error_metadata_arena
	if base == 0 || ios_runtime.swift_merge_error_metadata_retired || ios_runtime.swift_concurrency_retired
		|| metadata != base + u64(C.getpagesize()) + 16 {
		return swift_merge_error_metadata_failure()
	}
	return base + u64(C.getpagesize()) + 320
}
