// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32

const queue_initializer_symbol = '_$sSo17OS_dispatch_queueC8DispatchE5label3qos10attributes20autoreleaseFrequency6targetABSS_AC0D3QoSVAbCE10AttributesVAbCE011AutoreleaseI0OABSgtcfC'
type InitializerProbe = fn (u64, u64, u64, u64, u64, u64, u64, &u64)
type InitializerLiteral = fn (&u8, i64, bool) SwiftStringWords
type InitializerString = fn (&u8) SwiftStringWords
type InitializerKeep = fn (u64) u64
type InitializerRef = fn (u64)
type InitializerCreate = fn (&char, u64) u64
type InitializerLabel = fn (u64) &char
type InitializerSubmit = fn (u64, voidptr, DispatchFunction)
type InitializerSet = fn (u64, u64, voidptr, DispatchFunction)
type InitializerGet = fn (u64) voidptr
type InitializerContext = fn (u64, voidptr)
type InitializerFinalizer = fn (u64, DispatchFunction)
struct InitializerApi {
	native bool
	entry u64
	probe InitializerProbe
	literal InitializerLiteral
	keep InitializerKeep
	drop InitializerRef
	create InitializerCreate
	retain InitializerRef
	release InitializerRef
	label InitializerLabel
	async_queue InitializerSubmit
	sync_queue InitializerSubmit
	set InitializerSet
	get InitializerGet
	context InitializerContext
	finalizer InitializerFinalizer
}
struct InitializerState {
	api InitializerApi
mut:
	order int
	calls int
	finalized u64
}
fn initializer_lookup() u64 {
	mut entry := u64(0)
	for _ in 0 .. 64 { entry = runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', queue_initializer_symbol) or { panic(err) } }
	return entry
}
fn initializer_prior(context voidptr) {
	mut s := unsafe { &InitializerState(context) }; assert s.order == 0; s.order = 1
}
fn initializer_body(context voidptr) {
	mut s := unsafe { &InitializerState(context) }
	assert s.order == 1 && s.calls == 0 && s.api.get(u64(context)) == context
	s.order = 2; s.calls++
	if !s.api.native { worker := spawn initializer_lookup(); assert worker.wait() == s.api.entry }
}
fn initializer_finalized(context voidptr) {
	mut s := unsafe { &InitializerState(context) }
	assert C.ios_load_pointer(unsafe { &s.finalized }) == 0
	C.ios_store_pointer(unsafe { &s.finalized }, 1)
}
fn initializer_owned(api InitializerApi, text string) SwiftStringWords {
	$if macos { if api.native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		return unsafe { InitializerString(C.dlsym(core, c'$sSS7cStringSSSPys4Int8VG_tcfC'))(text.str) }
	} }
	mut words := swift_interpolation_init(i64(text.len), 0)
	swift_string_append_bytes(u64(unsafe { &words }), u64(text.str), u64(text.len))
	return words
}
fn initializer_refs(queue u64) int {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	registered := dispatch_runtime.queues[queue] or { panic('initializer queue is not registered') }
	return registered.refs
}
fn initializer_case(api InitializerApi, text string, owned bool, targeted bool, qos u64, attributes u64, autorelease u64) {
	mut state := InitializerState{api: api}; context := voidptr(unsafe { &state })
	parent := if targeted { api.create(c'vinix.swift.initializer.target', 0) } else { u64(0) }
	if parent != 0 {
		api.context(parent, context); api.finalizer(parent, initializer_finalized)
		api.set(parent, u64(context), context, unsafe { nil })
		api.retain(parent) // The initializer consumes this additional reference.
		if !api.native { assert initializer_refs(parent) == 2 }
	}
	words := if owned { initializer_owned(api, text) } else { api.literal(text.str, i64(text.len), text.is_ascii()) }
	if owned {
		api.keep(words.second)
		assert read64(words.second + 8) >> 33 == 1
	}
	mut observed := [u64(0xcafe), 0, 0, 0, 0xbeef]!
	api.probe(api.entry, words.first, words.second, qos, attributes, autorelease, parent, unsafe { &observed[1] })
	queue := observed[1]
	assert queue != 0 && observed[0] == 0xcafe && observed[4] == 0xbeef
	assert observed[2] == 0x5020 && observed[3] == 0x5021
	if owned {
		assert read64(words.second + 8) >> 33 == 0
		api.drop(words.second)
	}
	assert unsafe { api.label(queue).vstring() } == text.all_before('\x00')
	if parent != 0 {
		if !api.native { assert initializer_refs(parent) == 2 }
		api.release(parent) // The returned child now owns the last target reference.
	} else {
		api.context(queue, context); api.finalizer(queue, initializer_finalized)
		api.set(queue, u64(context), context, unsafe { nil })
	}
	api.async_queue(queue, context, initializer_prior)
	api.sync_queue(queue, context, initializer_body)
	assert state.order == 2 && state.calls == 1 && C.ios_load_pointer(unsafe { &state.finalized }) == 0
	api.release(queue)
	limit := time.sys_mono_now() + 5_000_000_000
	for C.ios_load_pointer(unsafe { &state.finalized }) == 0 {
		assert time.sys_mono_now() < limit; time.sleep(time.millisecond)
	}
	if !api.native { assert !dispatch_objc_is_queue(queue) && (parent == 0 || !dispatch_objc_is_queue(parent)) }
}
fn initializer_values(api InitializerApi, qos u64, attributes u64, autorelease u64) {
	for text in ['', 'Fortnite', 'abcdefghijklmno', 'π🎮', 'Fort\x00nite',
		'a long literal Fortnite queue label', 'long Unicode queue label 🎮π', 'x'.repeat(4097)]! {
		for target in [false, true]! { initializer_case(api, text, false, target, qos, attributes, autorelease) }
	}
	for target in [false, true]! { initializer_case(api, 'an owned heap queue label 🎮', true, target, qos, attributes, autorelease) }
}
fn initializer_bad(first u64, second u64, qos u64, attributes u64, autorelease u64, target u64) {
	if _ := swift_dispatch_initializer_checked(first, second, qos, attributes, autorelease, target) {
		assert false, 'unsupported Swift queue initializer accepted'
	}
}
fn initializer_invalid(qos u64, attributes u64, autorelease u64, guard u64) {
	words := initializer_owned(InitializerApi{}, 'owned rejected queue label')
	queue := darwin_dispatch_queue_create(c'vinix.swift.initializer.rejected', 0)
	darwin_dispatch_retain(queue)
	queues := dispatch_runtime.queues.len; buffers := ios_runtime.swift_buffers.len
	for pointers in [[u64(0), attributes, autorelease]!, [qos, 0, autorelease]!, [qos, attributes, 0]!]! {
		initializer_bad(words.first, words.second, pointers[0], pointers[1], pointers[2], queue)
	}
	initializer_bad(guard, guard, guard, guard, guard, guard)
	for change in [[u64(0), 0]!, [u64(8), 1]!, [u64(16), 1]!, [u64(16), 2]!,
		[u64(24), 1]!, [u64(24), 2]!, [u64(24), 255]!]! {
		where := if change[0] < 16 { qos + change[0] } else if change[0] == 16 { attributes } else { autorelease }
		if change[0] in [u64(0), 24]! { unsafe { *(&u8(where)) = u8(change[1]) } }
		else { unsafe { *(&u64(where)) = change[1] } }
		initializer_bad(words.first, words.second, qos, attributes, autorelease, queue)
		if change[0] in [u64(0), 24]! { unsafe { *(&u8(where)) = if change[0] == 0 { u8(5) } else { u8(0) } } }
		else { unsafe { *(&u64(where)) = 0 } }
	}
	for invalid in [SwiftStringWords{}, SwiftStringWords{second: u64(1) << 61},
		SwiftStringWords{first: u64(1) << 60, second: u64(1) << 60},
		SwiftStringWords{first: u64(1) << 60}, SwiftStringWords{second: 1}]! {
		initializer_bad(invalid.first, invalid.second, qos, attributes, autorelease, queue)
	}
	assert initializer_refs(queue) == 2 && read64(words.second + 8) >> 33 == 0
	assert dispatch_runtime.queues.len == queues && ios_runtime.swift_buffers.len == buffers
	swift_bridge_release(words.second); darwin_dispatch_release(queue); darwin_dispatch_release(queue)
}
fn test_swift_dispatch_initializer() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1)
	// C -> allocating Swift initializer; x20 metatype and incoming x21 survive.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0703f3,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0503e4, 0xaa0603e5,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 80))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { InitializerProbe(voidptr(code)) }
	mut mappings := [3]u64{}; mut pointers := [3]u64{}
	for i, size in [16, 8, 1]! {
		base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert base != u64(-1) && C.mprotect(voidptr(base + page), page, C.PROT_NONE) == 0
		mappings[i] = base; pointers[i] = base + page - u64(size)
	}
	qos := pointers[0]; attributes := pointers[1]; autorelease := pointers[2]
	unsafe { *(&u8(qos)) = 5 }
	for base in mappings { assert C.mprotect(voidptr(base), page, C.PROT_READ) == 0 }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		lib := C.dlopen(c'/usr/lib/swift/libswiftDispatch.dylib', 2)
		dispatch := C.dlopen(c'/usr/lib/system/libdispatch.dylib', 2)
		api := InitializerApi{native: true,
			entry: u64(C.dlsym(lib, c'$sSo17OS_dispatch_queueC8DispatchE5label3qos10attributes20autoreleaseFrequency6targetABSS_AC0D3QoSVAbCE10AttributesVAbCE011AutoreleaseI0OABSgtcfC')),
			probe: probe, literal: unsafe { InitializerLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) },
			keep: unsafe { InitializerKeep(C.dlsym(core, c'swift_bridgeObjectRetain')) }, drop: unsafe { InitializerRef(C.dlsym(core, c'swift_bridgeObjectRelease')) },
			create: unsafe { InitializerCreate(C.dlsym(dispatch, c'dispatch_queue_create')) },
			retain: unsafe { InitializerRef(C.dlsym(dispatch, c'dispatch_retain')) }, release: unsafe { InitializerRef(C.dlsym(dispatch, c'dispatch_release')) },
			label: unsafe { InitializerLabel(C.dlsym(dispatch, c'dispatch_queue_get_label')) },
			async_queue: unsafe { InitializerSubmit(C.dlsym(dispatch, c'dispatch_async_f')) }, sync_queue: unsafe { InitializerSubmit(C.dlsym(dispatch, c'dispatch_sync_f')) },
			set: unsafe { InitializerSet(C.dlsym(dispatch, c'dispatch_queue_set_specific')) }, get: unsafe { InitializerGet(C.dlsym(dispatch, c'dispatch_get_specific')) },
			context: unsafe { InitializerContext(C.dlsym(dispatch, c'dispatch_set_context')) }, finalizer: unsafe { InitializerFinalizer(C.dlsym(dispatch, c'dispatch_set_finalizer_f')) }}
		assert api.entry != 0
		initializer_values(api, qos, attributes, autorelease)
		println('IOS-DISPATCH-INITIALIZER-NATIVE: x0/x1 consumed String, borrowed x2 QoS/x3 attributes/x4 autorelease, consumed x5 target, preserved x20/x21, UTF-8/NUL/heap labels, target finalization and serial execution')
	}
	initializer_bad(guard, guard, guard, guard, guard, guard)
	for _ in 0 .. 2 {
		objc_start(); initializer_bad(guard, guard, guard, guard, guard, guard)
		if _ := swift_dispatch_symbol(queue_initializer_symbol) { assert false }
		assert ios_runtime.swift_dispatch_flags_arena == 0; system_data_start()!
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', queue_initializer_symbol) { assert false }
		if _ := swift_dispatch_symbol(queue_initializer_symbol + 'unknown') { assert false }
		assert ios_runtime.swift_dispatch_flags_arena == 0
		mut workers := []thread u64{}; for _ in 0 .. 8 { workers << spawn initializer_lookup() }; entries := workers.wait()
		for entry in entries { assert entry == entries[0] }
		api := InitializerApi{entry: entries[0], probe: probe, literal: swift_string_literal,
			keep: swift_bridge_retain, drop: swift_bridge_release, create: darwin_dispatch_queue_create,
			retain: darwin_dispatch_retain, release: darwin_dispatch_release, label: darwin_dispatch_queue_get_label,
			async_queue: darwin_dispatch_async_f, sync_queue: darwin_dispatch_sync_f,
			set: darwin_dispatch_queue_set_specific, get: darwin_dispatch_get_specific,
			context: darwin_dispatch_set_context, finalizer: darwin_dispatch_set_finalizer_f}
		for base in mappings { assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0 }
		initializer_invalid(qos, attributes, autorelease, guard)
		for base in mappings { assert C.mprotect(voidptr(base), page, C.PROT_READ) == 0 }
		initializer_values(api, qos, attributes, autorelease)
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0
		dispatch_stop(); initializer_bad(guard, guard, guard, guard, guard, guard)
		arena := ios_runtime.swift_dispatch_flags_arena; objc_stop(); initializer_bad(guard, guard, guard, guard, guard, guard)
		assert ios_runtime.swift_dispatch_flags_retired && ios_runtime.swift_dispatch_flags_arena == 0 && ios_runtime.live == 0
		$if macos { assert C.mprotect(voidptr(arena), page * 2, C.PROT_READ) == -1 }
		$else { mut resident := [u8(0), 0]!; assert C.mincore(voidptr(arena), page * 2, unsafe { &resident[0] }) == -1 }
		system_data_stop()
	}
	for base in mappings { assert C.munmap(voidptr(base), page * 2) == 0 }
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0
	println('IOS-DISPATCH-INITIALIZER: native allocating ABI, copied UTF-8/NUL/heap labels, consumed label/target ownership, target finalization, serial ordering and inherited specific context, unlocked resolution, protected input extents, unsupported/lifetime rejection, concurrent publication and unmapped lifetimes')
}
