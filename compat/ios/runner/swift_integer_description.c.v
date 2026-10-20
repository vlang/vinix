// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Decimal Int text is at most 20 bytes, including Int.min's sign. Keep the
// formatting buffer in this frame and return an owned frozen Swift String.
fn swift_integer_description_checked(value i64) !SwiftStringWords {
	mut number := [32]u8{}
	length := unsafe { C.snprintf(&char(&number[0]), 32, c'%lld', value) }
	if length < 1 || length >= 32 { return swift_describing_failure() }
	words := unsafe { &SwiftStringWords(C.__builtin_alloca(16)) }
	unsafe { *words = swift_interpolation_init(i64(length), 0) }
	swift_string_append_bytes(u64(words), u64(unsafe { &number[0] }), u64(length))
	return unsafe { *words }
}

fn swift_integer_description(value i64) SwiftStringWords {
	return swift_integer_description_checked(value) or { panic(err) }
}

fn swift_integer_description_active() ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_integer_description_retired
		|| ios_runtime.swift_concurrency_retired {
		return swift_describing_failure()
	}
}

// String already owns the canonical protocol declaration, and its metadata
// builder uses Int. Initialize both dependencies before publishing a separate
// sealed table/adapter arena; no registry lock spans a description callback.
fn swift_integer_description_arena_checked() !u64 {
	swift_integer_description_active()!
	integer := swift_integer_metadata()
	protocol := swift_string_metadata() - 16 + 352
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_integer_description_active()!
	if ios_runtime.swift_integer_description_arena != 0 {
		return ios_runtime.swift_integer_description_arena
	}
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_describing_failure() }
	base := u64(allocation)
	data := base + u64(page)
	conformance := data + 16
	unsafe {
		*(&u64(data)) = conformance
		*(&u64(data + 8)) = base
	}
	swift_protocol_relative(conformance, protocol)
	swift_protocol_relative(conformance + 4, read64(integer + 8))
	swift_protocol_relative(conformance + 8, data)
	// Witness Self is an indirect borrowed Int in x20. C returns String in
	// x0/x1 and preserves Swift's context/error registers.
	swift_integer_witness_emit(base, u64(voidptr(swift_integer_description)), true)
	write32(base + 32, 0xf9400430) // Generic dispatch: ldr x16,[x1,#8]
	write32(base + 36, 0xd61f0200) // br x16; Self x20, metadata x0.
	C.__builtin___clear_cache(allocation, voidptr(base + 40))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), page, C.PROT_READ) != 0 {
		C.munmap(allocation, page * 2)
		return swift_describing_failure()
	}
	ios_runtime.swift_integer_description_arena = base
	return base
}

fn swift_integer_description_stop() {
	// All workers and owned values have drained; String/Int metadata is live.
	ios_runtime.swift_integer_description_retired = true
	if ios_runtime.swift_integer_description_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_integer_description_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Int description conformance')
	}
	ios_runtime.swift_integer_description_arena = 0
}

fn swift_integer_description_symbol(symbol string) ?u64 {
	if symbol !in ['_$sSis23CustomStringConvertiblesWP', '_$sSis23CustomStringConvertiblesMc',
		'_$ss23CustomStringConvertibleTL', '_$ss23CustomStringConvertibleP11descriptionSSvgTq',
		'_$ss23CustomStringConvertibleP11descriptionSSvgTj']! {
		return none
	}
	base := swift_integer_description_arena_checked() or { return none }
	page := u64(C.getpagesize())
	return match symbol {
		'_$sSis23CustomStringConvertiblesWP' { base + page }
		'_$sSis23CustomStringConvertiblesMc' { base + page + 16 }
		'_$ss23CustomStringConvertibleP11descriptionSSvgTj' { base + 32 }
		else {
			protocol := ios_runtime.swift_metadata_arena + page + 352
			protocol + if symbol == '_$ss23CustomStringConvertibleTL' { u64(16) } else { u64(24) }
		}
	}
}
