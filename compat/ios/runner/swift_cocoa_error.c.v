// SPDX-License-Identifier: GPL-2.0-or-later
module main

// This profile supplies Code's concrete metadata/equality and the layout of
// its associated CocoaError value. The wider stored-error protocol needs
// CustomNSError/bridging/Hashable/RawRepresentable/FixedWidthInteger witnesses;
// its associated-conformance accessor rejects before publishing a table.
fn swift_cocoa_error_associated_checked(associated u64, metadata u64, table u64) !u64 {
	expected := swift_cocoa_error_table_checked(metadata)!
	if table != expected || associated != expected - 592 {
		return error('iOS: CocoaError associated conformance requires canonical metadata and table')
	}
	return error('iOS: CocoaError _BridgedStoredNSError witnesses are not implemented')
}
fn swift_cocoa_error_associated(associated u64, metadata u64, table u64) u64 {
	return swift_cocoa_error_associated_checked(associated, metadata, table) or { panic(err) }
}
fn swift_cocoa_symbolic_relative(field u64, destination u64) {
	delta := i64(destination) - i64(field); assert delta >= -2147483648 && delta <= 2147483647
	bits := u32(i32(delta))
	for i in u64(0) .. 4 { unsafe { *(&u8(field + i)) = u8(bits >> (i * 8)) } }
}
fn swift_cocoa_error_arena_checked() !u64 {
	$if !arm64 { return error('iOS: CocoaError metadata requires ARM64') }
	if ios_runtime == unsafe { nil } { return error('iOS: CocoaError metadata outside runtime lifetime') }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_cocoa_error_retired { return error('iOS: CocoaError metadata outside runtime lifetime') }
	if ios_runtime.swift_cocoa_error_arena != 0 { return ios_runtime.swift_cocoa_error_arena }
	integer := swift_integer_metadata(); swift_error_metadata_arena()
	page := usize(C.getpagesize()); allocation := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == voidptr(-1) { return error('iOS: cannot allocate CocoaError metadata') }
	base := u64(allocation); data := base + u64(page)
	code_type := data + 16; error_type := data + 48
	code_descriptor := data + 192; error_descriptor := data + 224; module_descriptor := data + 256
	code_protocol := data + 320; bridge_protocol := data + 448
	conformance := data + 608; table := data + 640; equal_descriptor := data + 672; equal_table := data + 688
	// Complete nonreflectable nominal identities, with packed zero field offsets.
	for i, metadata in [code_type, error_type]! {
		entry := base + u64(i * 32); descriptor := if i == 0 { code_descriptor } else { error_descriptor }
		write32(entry, 0x58000080); write32(entry + 4, 0xd2800001); write32(entry + 8, 0xd65f03c0)
		unsafe { *(&u64(entry + 16)) = metadata; *(&u64(metadata)) = 0x200; *(&u64(metadata + 8)) = descriptor }
		write32(descriptor, 0x51); swift_protocol_relative(descriptor + 4, if i == 0 { error_descriptor } else { module_descriptor })
		swift_protocol_relative(descriptor + 8, data + if i == 0 { u64(848) } else { u64(832) })
		swift_protocol_relative(descriptor + 12, entry); write32(descriptor + 20, 1); write32(descriptor + 24, 2)
	}
	unsafe { *(&u64(code_type - 8)) = data + 96; *(&u64(error_type - 8)) = data + 1120 }
	C.memcpy(voidptr(data + 1120), voidptr(ios_runtime.swift_error_arena + u64(page) + 32), 88)
	write32(data + 1200, 0x02010007)
	// Code is a POD word, with no extra inhabitants and the native enum witnesses.
	C.memcpy(voidptr(data + 96), voidptr(read64(integer - 8)), 88)
	write32(data + 176, 0x02000007)
	swift_protocol_relative(module_descriptor + 8, data + 864)
	C.memcpy(voidptr(data + 832), c'CocoaError', 11); C.memcpy(voidptr(data + 848), c'Code', 5); C.memcpy(voidptr(data + 864), c'Foundation', 11)
	C.memcpy(voidptr(data + 880), c'_ErrorCodeProtocol', 19); C.memcpy(voidptr(data + 912), c'_ErrorType', 11)
	C.memcpy(voidptr(data + 928), c'_BridgedStoredNSError', 22); C.memcpy(voidptr(data + 960), c'x', 2)
	// Native signature: Self:Equatable, Self == Self._ErrorType.Code,
	// Self._ErrorType:_BridgedStoredNSError. Preserve its three requirements.
	write32(code_protocol, 0x30043); swift_protocol_relative(code_protocol + 4, module_descriptor)
	swift_protocol_relative(code_protocol + 8, data + 880); write32(code_protocol + 12, 3); write32(code_protocol + 16, 3)
	swift_protocol_relative(code_protocol + 20, data + 912)
	equal_protocol := integer - 16 + 432
	write32(code_protocol + 24, 0x80); swift_protocol_relative(code_protocol + 28, data + 960); swift_protocol_relative(code_protocol + 32, equal_protocol)
	write32(code_protocol + 36, 1); swift_protocol_relative(code_protocol + 40, data + 960); swift_protocol_relative(code_protocol + 44, data + 976)
	write32(code_protocol + 48, 0x80); swift_protocol_relative(code_protocol + 52, data + 1040); swift_protocol_relative(code_protocol + 56, bridge_protocol)
	for i, flags in [u32(0), 0xae890008, 0x77e00007]! { write32(code_protocol + 60 + u64(i * 8), flags) }
	// Symbolic generic paths retain their protocol contexts rather than naming
	// a different associated type. Reflection beyond nominal lookup is absent.
	for item in [[u64(976), 0]!, [u64(1040), 1]!]! {
		address := data + item[0]; C.memcpy(voidptr(address), c'10_ErrorType', 12)
		unsafe { *(&u8(address + 12)) = 1 }; swift_cocoa_symbolic_relative(address + 13, code_protocol)
		if item[1] == 0 { C.memcpy(voidptr(address + 17), c'_4Code', 6); unsafe { *(&u8(address + 23)) = 1 }; swift_cocoa_symbolic_relative(address + 24, bridge_protocol); C.memcpy(voidptr(address + 28), c'QZ', 3) }
		else { C.memcpy(voidptr(address + 17), c'Qz', 3) }
	}
	// The associated protocol is an opaque declaration here. Its generic
	// conformance is unavailable, including through native Swift lookup.
	write32(bridge_protocol, 0x30043); swift_protocol_relative(bridge_protocol + 4, module_descriptor)
	swift_protocol_relative(bridge_protocol + 8, data + 928); write32(bridge_protocol + 16, 9)
	for i, flags in [u32(0), 0, 0, 0x5ccf0008, 0x6b5e0008, 0x77730008, 0x38eb0007, 0xb6c80013, 0x40b70002]! { write32(bridge_protocol + 24 + u64(i * 8), flags) }
	// Concrete specialized Code table; the native generic factory only fills
	// inherited Equatable. Direct associated metadata needs no mutable cache.
	swift_protocol_relative(conformance, code_protocol); swift_protocol_relative(conformance + 4, code_descriptor); swift_protocol_relative(conformance + 8, table)
	swift_protocol_relative(equal_descriptor, equal_protocol); swift_protocol_relative(equal_descriptor + 4, code_descriptor); swift_protocol_relative(equal_descriptor + 8, equal_table)
	unsafe { *(&u64(table)) = conformance; *(&u64(table + 8)) = equal_table; *(&u64(table + 24)) = error_type
		*(&u64(equal_table)) = equal_descriptor; *(&u64(equal_table + 8)) = u64(voidptr(swift_integer_equal_indirect)) }
	// Swift 6's associated-conformance slot is tagged data, not callable code:
	// FF 07 <relative accessor function> NUL. Native lookup invokes it with
	// associated metadata, Self metadata and Self witness table in x0/x1/x2.
	record := data + 1088; unsafe { *(&u8(record)) = 0xff; *(&u8(record + 1)) = 7; *(&u64(table + 16)) = record | 1 }
	swift_cocoa_symbolic_relative(record + 2, base + 64)
	write32(base + 64, 0x58000050); write32(base + 68, 0xd61f0200)
	unsafe { *(&u64(base + 72)) = u64(voidptr(swift_cocoa_error_associated)) }
	C.__builtin___clear_cache(allocation, voidptr(base + 80))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0 || C.mprotect(voidptr(data), page, C.PROT_READ) != 0 {
		C.munmap(allocation, page * 2); return error('iOS: cannot seal CocoaError metadata')
	}
	ios_runtime.swift_cocoa_error_arena = base
	return base
}
fn swift_cocoa_error_table_checked(metadata u64) !u64 {
	base := swift_cocoa_error_arena_checked()!
	if metadata != base + u64(C.getpagesize()) + 16 { return error('iOS: CocoaError conformance requires canonical Code metadata') }
	return base + u64(C.getpagesize()) + 640
}
fn swift_cocoa_error_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$s10Foundation10CocoaErrorV4CodeVAA01_cD8ProtocolAAMc' { u64(C.getpagesize()) + 608 }
		'_$s10Foundation10CocoaErrorV4CodeVMa' { u64(0) }
		else { return none }
	}
	return (swift_cocoa_error_arena_checked() or { return none }) + offset
}
fn swift_cocoa_error_stop() {
	ios_runtime.swift_cocoa_error_retired = true
	if ios_runtime.swift_cocoa_error_arena == 0 { return }
	ios_runtime.swift_cocoa_error_retired_arena = ios_runtime.swift_cocoa_error_arena
	if C.munmap(voidptr(ios_runtime.swift_cocoa_error_arena), usize(C.getpagesize()) * 2) != 0 { panic('iOS: cannot retire CocoaError metadata') }
	ios_runtime.swift_cocoa_error_arena = 0
}
