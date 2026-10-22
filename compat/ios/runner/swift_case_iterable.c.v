// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftCaseIterableFailure {}

fn (_ &SwiftCaseIterableFailure) msg() string {
	return 'iOS: Swift CaseIterable requires an active runtime and sealed storage'
}

fn (_ &SwiftCaseIterableFailure) code() int { return 1 }

__global swift_case_iterable_failure_value = SwiftCaseIterableFailure{}

fn swift_case_iterable_failure() IError { return unsafe { &swift_case_iterable_failure_value } }

// Symbolic manglings put relative references immediately after a one-byte tag,
// without alignment. Byte stores avoid unaligned typed access on the host.
fn swift_case_iterable_relative(field u64, destination u64) {
	offset := i64(destination) - i64(field)
	assert offset >= -2147483648 && offset <= 2147483647
	bits := u32(i32(offset))
	for i in u64(0) .. 4 { unsafe { *(&u8(field + i)) = u8(bits >> (i * 8)) } }
}

// Native's type-relative associated-conformance accessor receives the already
// constructed AllCases (= Array<Self>) metadata in x0 and returns its table in
// x0. It does not receive Self metadata or create an Array specialization.
fn swift_case_iterable_default_conformance_checked(metadata u64) !u64 {
	if ios_runtime == unsafe { nil } { return swift_case_iterable_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_case_iterable_retired || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_case_iterable_arena == 0 {
		return swift_case_iterable_failure()
	}
	conformance := ios_runtime.swift_collection_arena + u64(C.getpagesize()) + 32
	return swift_witness_table_checked(conformance, metadata, 0)
}

fn swift_case_iterable_default_conformance(metadata u64) u64 {
	return swift_case_iterable_default_conformance_checked(metadata) or { panic(err) }
}

fn swift_case_iterable_arena_checked() !u64 {
	$if !arm64 { return swift_case_iterable_failure() }
	if ios_runtime == unsafe { nil } { return swift_case_iterable_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_case_iterable_retired || ios_runtime.swift_concurrency_retired {
		return swift_case_iterable_failure()
	}
	if ios_runtime.swift_case_iterable_arena != 0 { return ios_runtime.swift_case_iterable_arena }
	// Hold the recursive publication lock while acquiring dependencies so that
	// the declaration borrows their canonical identities for its whole lifetime.
	collection := swift_collection_arena()
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return swift_case_iterable_failure() }
	base := u64(arena)
	data := base + page
	write32(data, 0x30043) // Unique Swift protocol, unconstrained by class.
	swift_protocol_relative(data + 4, ios_runtime.swift_array_arena + page + 224)
	swift_protocol_relative(data + 8, data + 128)
	write32(data + 12, 2) // Generic signature requirements.
	write32(data + 16, 3) // Associated conformance, associated type, static getter.
	swift_protocol_relative(data + 20, data + 144)
	C.memcpy(voidptr(data + 128), c'CaseIterable', 13)
	C.memcpy(voidptr(data + 144), c'AllCases', 9)
	C.memcpy(voidptr(data + 160), c'x', 2)
	// Self == AllCases.Element, AllCases: Collection. Both dependent-member
	// paths reference this declaration, rather than a duplicate protocol graph.
	write32(data + 24, 1)
	swift_protocol_relative(data + 28, data + 160)
	swift_protocol_relative(data + 32, data + 176)
	write32(data + 36, 0x80)
	swift_protocol_relative(data + 40, data + 224)
	swift_protocol_relative(data + 44, collection + page + 256)
	for offset in [u64(176), 224]! {
		C.memcpy(voidptr(data + offset), c'8AllCases', 9)
		unsafe { *(&u8(data + offset + 9)) = 1 }
		swift_case_iterable_relative(data + offset + 10, data)
	}
	C.memcpy(voidptr(data + 190), c'_7ElementSTQZ', 13)
	C.memcpy(voidptr(data + 238), c'Qz', 3)
	// Preserve the measured requirement discriminators for descriptor consumers.
	// The first two defaults are symbolic conformance/type names, not callable
	// witness slots; the concrete allCases getter has no default implementation.
	write32(data + 48, 0x20050008)
	swift_protocol_relative(data + 52, data + 272)
	write32(data + 56, 0xdf690007)
	swift_protocol_relative(data + 60, data + 256)
	write32(data + 64, 0x8ed40003)
	C.memcpy(voidptr(data + 256), c'SayxG', 6)
	unsafe { *(&u8(data + 272)) = 8 }
	swift_case_iterable_relative(data + 273, base)
	write32(base, 0x58000050) // ldr x16,literal at +8
	write32(base + 4, 0xd61f0200) // br x16
	unsafe { *(&u64(base + 8)) = u64(voidptr(swift_case_iterable_default_conformance)) }
	C.__builtin___clear_cache(arena, voidptr(base + 16))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 {
			panic('iOS: cannot retire unsealed Swift CaseIterable declaration')
		}
		return swift_case_iterable_failure()
	}
	ios_runtime.swift_case_iterable_arena = base
	return base
}

fn swift_case_iterable_stop() {
	// Workers and callbacks have drained. Retire before the borrowed Collection
	// and Array declaration pages, under the runtime lock.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	ios_runtime.swift_case_iterable_retired = true
	if ios_runtime.swift_case_iterable_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_case_iterable_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Swift CaseIterable declaration')
	}
	ios_runtime.swift_case_iterable_arena = 0
}

fn swift_case_iterable_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$ss12CaseIterableMp' { 0 }
		'_$ss12CaseIterableTL' { 40 }
		'_$ss12CaseIterableP8AllCasesAB_SlTn' { 48 }
		'_$s8AllCasess12CaseIterablePTl' { 56 }
		'_$ss12CaseIterableP8allCases03AllD0QzvgZTq' { 64 }
		else { return none }
	}
	base := swift_case_iterable_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + u64(offset)
}
