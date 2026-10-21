// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftErrorSelfFailure {}
fn (_ &SwiftErrorSelfFailure) msg() string { return 'iOS: inactive Swift Error self-conformance' }
fn (_ &SwiftErrorSelfFailure) code() int { return 1 }
__global swift_error_self_failure_value = SwiftErrorSelfFailure{}
fn swift_error_self_failure() IError { return unsafe { &swift_error_self_failure_value } }
fn swift_error_self_active() ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_error_self_failure()
	}
}

// Borrowed Error owner and caller's stack scratch/output. Reuse extraction's
// existing CFError provenance checks; Swift error boxes remain unsupported.
// Extraction releases its registry lock before any contained witness runs.
fn swift_error_self_value_checked(owner u64, scratch &u64, output &SwiftErrorValue) ! {
	swift_error_self_active()!
	swift_error_value_checked(owner, scratch, output)!
}
fn swift_error_self_value(owner u64, scratch &u64, output &SwiftErrorValue) {
	swift_error_self_value_checked(owner, scratch, output) or { panic(err) }
}

// The native self-conformance descriptor refers to Error's protocol context
// in both relative fields, followed by its concrete table pattern and flags0.
// These are data records, not a getter address or the CFError: Error table.
fn swift_error_self_emit(code u64, data u64, protocol u64) {
	table := data + 768
	descriptor := data + 816
	unsafe { *(&u64(table)) = descriptor }
	swift_protocol_relative(descriptor, protocol)
	swift_protocol_relative(descriptor + 4, protocol)
	swift_protocol_relative(descriptor + 8, table)
	write32(descriptor + 12, 0)
	for index in 0 .. 4 {
		entry := code + 256 + u64(index * 96)
		unsafe { *(&u64(table + 8 + u64(index * 8))) = entry }
		// Match the native stack layout: extracted value/metadata/table at0,
		// scratch owner at24, saved x20/x19 at32, saved frame/link at48.
		// Self is one borrowed readable Error reference word in x20. The input
		// metadata, self-conformance table and x8 are unused. Every requirement
		// returns directly in x0 or x0/x1; preserve those registers on return.
		for i, op in [u32(0xd10103ff), 0xa9024ff4, 0xa9037bfd, 0x9100c3fd,
			0xf9400280, 0x910063e1, 0x910003e2, 0x580001b0, 0xd63f0200,
			0xa94003f4, 0xf9400be1, u32(0x91000028 | ((index + 1) * 8 << 10)),
			0xf9400110, 0xd63f0200, 0xa9437bfd, 0xa9424ff4, 0x910103ff,
			0xd65f03c0, 0xd503201f, 0xd503201f]! { write32(entry + u64(i * 4), op) }
		unsafe { *(&u64(entry + 80)) = u64(voidptr(swift_error_self_value)) }
	}
}
fn swift_error_self_table_checked() !u64 {
	$if !arm64 { return swift_error_self_failure() }
	swift_error_self_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_error_self_active()!
	return swift_error_metadata_arena() + u64(C.getpagesize()) + 768
}
