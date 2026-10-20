// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUITupleInitFailure {}
fn (_ &SwiftUITupleInitFailure) msg() string { return 'iOS: SwiftUI TupleView initializer requires active sealed storage' }
fn (_ &SwiftUITupleInitFailure) code() int { return 1 }
__global swiftui_tuple_init_failure_value = SwiftUITupleInitFailure{}
fn swiftui_tuple_init_failure() IError { return unsafe { &swiftui_tuple_init_failure_value } }
type SwiftUITupleInitTake = fn (u64, u64, u64) u64

// Frozen TupleView<T> stores T at offset zero. Consume the incoming T with
// its initializeWithTake witness; the moved source is now uninitialized.
// Complete TupleView metadata and View graph operations are not needed here.
fn swiftui_tuple_init(result u64, source u64, metadata u64) {
	witness := read64(metadata - 8)
	initialize := unsafe { SwiftUITupleInitTake(voidptr(read64(witness + 32))) }
	initialize(result, source, metadata)
}

fn swiftui_tuple_init_arena_checked() !u64 {
	$if !arm64 { return swiftui_tuple_init_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_tuple_init_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_tuple_init_retired { return swiftui_tuple_init_failure() }
	if ios_runtime.swiftui_tuple_init_arena != 0 { return ios_runtime.swiftui_tuple_init_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_tuple_init_failure() }
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if code == voidptr(-1) { return swiftui_tuple_init_failure() }
	base := u64(code)
	// Swift x0 consumed source, x1 T metadata, x8 indirect result ->
	// V x0 result, x1 source, x2 T metadata. Tail call preserves x20/x21.
	for i, instruction in [u32(0xaa0103e2), 0xaa0003e1, 0xaa0803e0, 0x58000070, 0xd61f0200]! {
		write32(base + u64(i * 4), instruction)
	}
	unsafe { *(&u64(base + 24)) = u64(voidptr(swiftui_tuple_init)) }
	C.__builtin___clear_cache(code, voidptr(base + 32))
	if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0 {
		if C.munmap(code, page) != 0 { panic('iOS: cannot retire unsealed SwiftUI TupleView initializer') }
		return swiftui_tuple_init_failure()
	}
	ios_runtime.swiftui_tuple_init_arena = base
	return base
}

fn swiftui_tuple_init_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI9TupleViewVyACyxGxcfC' { return none }
	return swiftui_tuple_init_arena_checked() or { return none }
}

// Runtime lock held, after workers, owners and metadata users have drained.
fn swiftui_tuple_init_stop() {
	ios_runtime.swiftui_tuple_init_retired = true
	if ios_runtime.swiftui_tuple_init_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swiftui_tuple_init_arena), usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire SwiftUI TupleView initializer')
	}
	ios_runtime.swiftui_tuple_init_arena = 0
}
