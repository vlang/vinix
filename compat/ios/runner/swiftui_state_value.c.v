// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUIStateValueFailure {}
fn (_ &SwiftUIStateValueFailure) msg() string { return 'iOS: SwiftUI State getter requires active sealed storage' }
fn (_ &SwiftUIStateValueFailure) code() int { return 1 }
__global swiftui_state_value_failure_value = SwiftUIStateValueFailure{}
fn swiftui_state_value_failure() IError { return unsafe { &swiftui_state_value_failure_value } }
type SwiftUIStateValueCopy = fn (u64, u64, u64) u64

// x0 carries complete State<Value> metadata, whose generic argument is Value
// at +16 and whose signed second field offset is at +28. Frozen _value starts
// at Self +0. Borrow it and initialize an owned result through Value's witness.
// A live AnyLocation needs graph/update tracking and its virtual getter; reject
// before touching that object, Value's metadata/bytes, or the result storage.
fn swiftui_state_value(result u64, self_value u64, metadata u64) {
	location_offset := i32(read32(metadata + 28))
	if location_offset < 0 { panic('iOS: invalid SwiftUI State location offset') }
	if read64(self_value + u64(location_offset)) != 0 {
		panic('iOS: SwiftUI State.wrappedValue live locations are not implemented')
	}
	value_metadata := read64(metadata + 16)
	witness := read64(value_metadata - 8)
	initialize := unsafe { SwiftUIStateValueCopy(voidptr(read64(witness + 16))) }
	initialize(result, self_value, value_metadata)
}

fn swiftui_state_value_arena_checked() !u64 {
	$if !arm64 { return swiftui_state_value_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_state_value_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_state_value_retired { return swiftui_state_value_failure() }
	if ios_runtime.swiftui_state_value_arena != 0 { return ios_runtime.swiftui_state_value_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_state_value_failure() }
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if code == voidptr(-1) { return swiftui_state_value_failure() }
	base := u64(code)
	// Swift x0 State metadata, x20 borrowed Self, x8 indirect result
	// -> V x0 result, x1 Self, x2 State metadata; preserve x20/x21 by tail call.
	for i, instruction in [u32(0xaa0003e2), 0xaa1403e1, 0xaa0803e0, 0x58000070, 0xd61f0200]! {
		write32(base + u64(i * 4), instruction)
	}
	unsafe { *(&u64(base + 24)) = u64(voidptr(swiftui_state_value)) }
	C.__builtin___clear_cache(code, voidptr(base + 32))
	if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0 {
		if C.munmap(code, page) != 0 { panic('iOS: cannot retire unsealed SwiftUI State getter') }
		return swiftui_state_value_failure()
	}
	ios_runtime.swiftui_state_value_arena = base
	return base
}

fn swiftui_state_value_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI5StateV12wrappedValuexvg' { return none }
	return swiftui_state_value_arena_checked() or { return none }
}

fn swiftui_state_value_stop() {
	ios_runtime.swiftui_state_value_retired = true
	if ios_runtime.swiftui_state_value_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swiftui_state_value_arena), usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire SwiftUI State getter')
	}
	ios_runtime.swiftui_state_value_arena = 0
}
