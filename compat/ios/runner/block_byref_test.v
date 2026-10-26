// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
}
#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) int

type ByrefAssign = fn (&u64, u64, int)
type ByrefDispose = fn (u64, int)
type ByrefCopy = fn (u64) u64
type ByrefRelease = fn (u64)

struct ByrefApi {
	stack_isa u64
	assign ByrefAssign = block_object_assign
	dispose ByrefDispose = block_object_dispose
	copy ByrefCopy = block_copy
	release ByrefRelease = block_release
}

struct ByrefState {
	api ByrefApi
	weak bool
mut:
	copies int
	disposals int
	reentries int
}

fn byref_lock_reader() {
	C.ios_objc_initialize_lock()
	C.ios_objc_initialize_unlock()
}

fn byref_keep(destination u64, source u64) {
	state := unsafe { &ByrefState(read64(source + 48)) }
	assert read64(source + 8) == destination && read64(destination + 8) == destination
	assert read64(destination + 40) == 0x12345678 // Extended layout precedes payload.
	write64(destination + 48, read64(source + 48))
	if state.weak {
		objc_store_weak(unsafe { &u64(destination + 56) }, read64(source + 56))
		objc_destroy_weak(unsafe { &u64(source + 56) })
	} else {
		// ARC strong byref helpers move ownership from the stack slot.
		write64(destination + 56, read64(source + 56))
		write64(source + 56, 0)
	}
	write64(destination + 64, read64(source + 64))
	worker := spawn byref_lock_reader()
	worker.wait()
	unsafe { state.copies++; state.reentries++ }
}

fn byref_destroy(source u64) {
	state := unsafe { &ByrefState(read64(source + 48)) }
	assert read64(source + 8) == source && read32(source + 16) & 0xffff == 1
	if state.weak { objc_destroy_weak(unsafe { &u64(source + 56) }) }
	else { objc_release(read64(source + 56)) }
	worker := spawn byref_lock_reader()
	worker.wait()
	unsafe { state.disposals++; state.reentries++ }
}

fn byref_block_keep(destination u64, source u64) {
	state := unsafe { &ByrefState(read64(source + 40)) }
	state.api.assign(unsafe { &u64(destination + 32) }, read64(source + 32), 8)
}

fn byref_block_destroy(source u64) {
	state := unsafe { &ByrefState(read64(source + 40)) }
	state.api.dispose(read64(source + 32), 8)
}

fn byref_block_invoke(block u64) {
	forwarded := read64(read64(block + 32) + 8)
	write64(forwarded + 64, read64(forwarded + 64) + 1)
}

fn byref_worker(api ByrefApi, source u64) {
	for _ in 0 .. 1000 {
		mut copy := u64(0)
		api.assign(unsafe { &copy }, source, 8)
		assert copy == source
		api.dispose(copy, 8)
	}
}

fn byref_plain(api ByrefApi) {
	for flags in [8, 24]! {
		mut storage := [u64(0), 0, u64(32) << 32, 41]!
		source := u64(unsafe { &storage[0] })
		write64(source + 8, source)
		api.dispose(source, flags) // An uncopied stack scope has nothing to free.
		assert storage[1] == source && storage[3] == 41
		mut first := u64(0)
		api.assign(unsafe { &first }, source, flags)
		assert first != source && read64(first) == 0
		assert read64(source + 8) == first && read64(first + 8) == first
		assert read32(first + 16) == (u32(1) << 24) | 4 && read32(first + 20) == 32
		assert read64(first + 24) == 41
		mut second := u64(0)
		api.assign(unsafe { &second }, source, flags)
		assert second == first && read32(first + 16) & 0xfffe == 6
		write64(second + 24, 42)
		assert read64(read64(source + 8) + 24) == 42
		api.dispose(source, flags)
		assert read32(first + 16) & 0xfffe == 4
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn byref_worker(api, first) }
		workers.wait()
		unsafe { workers.free() }
		assert read32(first + 16) & 0xfffe == 4
		// Saturated refcounts remain latched rather than wrapping or freeing.
		write32(first + 16, (u32(1) << 24) | 0xfffe)
		mut latched := u64(0)
		api.assign(unsafe { &latched }, first, flags)
		api.dispose(latched, flags)
		assert latched == first && read32(first + 16) & 0xfffe == 0xfffe
		write32(first + 16, (u32(1) << 24) | 4)
		api.dispose(first, flags)
		assert read32(second + 16) & 0xfffe == 2
		api.dispose(second, flags)
	}
	// BYREF_CALLER payload helpers are unretained, including block and weak forms.
	for flags in [131, 135, 147, 151]! {
		mut destination := u64(0)
		api.assign(unsafe { &destination }, 0x1234, flags)
		assert destination == 0x1234
		api.dispose(destination, flags)
		api.assign(unsafe { &destination }, 0, flags)
		assert destination == 0
		api.dispose(0, flags)
	}
}

fn byref_lifetime(api ByrefApi, weak bool, stack_first bool) {
	mut state := ByrefState{api: api, weak: weak}
	mut storage := [9]u64{}
	source := u64(unsafe { &storage[0] })
	write64(source + 8, source)
	write32(source + 16, (u32(1) << 25) | (u32(1) << 28))
	write32(source + 20, 72)
	write64(source + 24, u64(unsafe { voidptr(byref_keep) }))
	write64(source + 32, u64(unsafe { voidptr(byref_destroy) }))
	write64(source + 40, 0x12345678)
	write64(source + 48, u64(unsafe { &state }))
	object := objc_new(ios_runtime.names['NSObject'])
	mut observer := u64(0)
	objc_store_weak(unsafe { &observer }, object)
	if weak { objc_store_weak(unsafe { &u64(source + 56) }, object) }
	else { write64(source + 56, object) }
	write64(source + 64, 19)
	mut descriptor := [u64(0), 48, u64(unsafe { voidptr(byref_block_keep) }), u64(unsafe { voidptr(byref_block_destroy) })]!
	mut literal := [api.stack_isa, u64(1) << 25, u64(unsafe { voidptr(byref_block_invoke) }), u64(unsafe { &descriptor[0] }), source, u64(unsafe { &state })]!
	first := api.copy(u64(unsafe { &literal[0] }))
	second := api.copy(u64(unsafe { &literal[0] })) // Distinct blocks share one byref allocation.
	alias := api.copy(first) // Retaining the same heap block does not recopy its capture.
	forwarded := read64(source + 8)
	assert first != second && alias == first && state.copies == 1
	assert read64(first + 32) == forwarded && read64(second + 32) == forwarded
	assert read32(forwarded + 16) & 0xfffe == 6
	block_invoke_void(second)
	assert read64(forwarded + 64) == 20 && read64(source + 56) == 0
	if weak {
		objc_release(object)
		assert observer == 0 && read64(forwarded + 56) == 0
	} else { assert observer == object && obj_header(object).refs == 1 }
	if stack_first { api.dispose(source, 8) }
	api.release(first)
	assert state.disposals == 0
	api.release(alias)
	assert state.disposals == 0
	api.release(second)
	if !stack_first {
		assert state.disposals == 0
		api.dispose(source, 8)
	}
	assert state.copies == 1 && state.disposals == 1 && state.reentries == 2
	assert observer == 0
	objc_destroy_weak(unsafe { &observer })
}

fn byref_checks(api ByrefApi) {
	byref_plain(api)
	for weak in [false, true]! {
		for stack_first in [false, true]! { byref_lifetime(api, weak, stack_first) }
	}
}

fn test_block_byref() {
	objc_start()
	$if macos {
		system := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2)
		assert system != unsafe { nil }
		byref_checks(ByrefApi{
			stack_isa: u64(C.dlsym(system, c'_NSConcreteStackBlock')),
			assign: unsafe { ByrefAssign(C.dlsym(system, c'_Block_object_assign')) },
			dispose: unsafe { ByrefDispose(C.dlsym(system, c'_Block_object_dispose')) },
			copy: unsafe { ByrefCopy(C.dlsym(system, c'_Block_copy')) },
			release: unsafe { ByrefRelease(C.dlsym(system, c'_Block_release')) }})
		assert C.dlclose(system) == 0
		println('NATIVE-BLOCK-BYREF: forwarding, refcounts, helpers, extended layout and MRC payload flags matched')
	}
	byref_checks(ByrefApi{stack_isa: block_isa(0)})
	assert ios_runtime.block_refs.len == 0 && ios_runtime.weak.len == 0 && ios_runtime.live == 0
	objc_stop()
	println('IOS-BLOCK-BYREF: stack/heap ownership orders, shared mutation, four concurrent retainers, saturated counts, ARC strong/weak moves, helper reentry and cleanup PASS')
}
