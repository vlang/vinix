// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUIStateSetFailure {}
fn (_ &SwiftUIStateSetFailure) msg() string { return 'iOS: SwiftUI State setter requires active sealed storage' }
fn (_ &SwiftUIStateSetFailure) code() int { return 1 }
__global swiftui_state_set_failure_value = SwiftUIStateSetFailure{}
fn swiftui_state_set_failure() IError { return unsafe { &swiftui_state_set_failure_value } }
type SwiftUIStateSetDestroy = fn (u64, u64)

// A nonmutating State setter with nil _location leaves cached _value alone.
// The new Value is consumed even on that path: destroy it through its witness,
// using complete State<Value> metadata's generic argument, not the State VWT.
// Live locations require virtual set/transaction behavior and remain unsupported.
fn swiftui_state_set(value u64, metadata u64, self_value u64) {
	location_offset := i32(read32(metadata + 28))
	if location_offset < 0 { panic('iOS: invalid SwiftUI State setter location offset') }
	if read64(self_value + u64(location_offset)) != 0 {
		panic('iOS: SwiftUI State.wrappedValue live location writes are not implemented')
	}
	value_metadata := read64(metadata + 16)
	witness := read64(value_metadata - 8)
	destroy := unsafe { SwiftUIStateSetDestroy(voidptr(read64(witness + 8))) }
	destroy(value, value_metadata)
}

fn swiftui_state_set_arena_checked() !u64 {
	$if !arm64 { return swiftui_state_set_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_state_set_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_state_set_retired { return swiftui_state_set_failure() }
	if ios_runtime.swiftui_state_set_arena != 0 { return ios_runtime.swiftui_state_set_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_state_set_failure() }
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if code == voidptr(-1) { return swiftui_state_set_failure() }
	base := u64(code)
	// Swift x0 consumed new Value, x1 State metadata, x20 borrowed Self
	// -> V x0 new Value, x1 State metadata, x2 Self. No result in x8.
	for i, instruction in [u32(0xaa1403e2), 0x58000070, 0xd61f0200]! {
		write32(base + u64(i * 4), instruction)
	}
	unsafe { *(&u64(base + 16)) = u64(voidptr(swiftui_state_set)) }
	C.__builtin___clear_cache(code, voidptr(base + 24))
	if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0 {
		if C.munmap(code, page) != 0 { panic('iOS: cannot retire unsealed SwiftUI State setter') }
		return swiftui_state_set_failure()
	}
	ios_runtime.swiftui_state_set_arena = base
	return base
}

fn swiftui_state_set_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI5StateV12wrappedValuexvs' { return none }
	return swiftui_state_set_arena_checked() or { return none }
}

fn swiftui_state_set_stop() {
	ios_runtime.swiftui_state_set_retired = true
	if ios_runtime.swiftui_state_set_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swiftui_state_set_arena), usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire SwiftUI State setter')
	}
	ios_runtime.swiftui_state_set_arena = 0
}
