// SPDX-License-Identifier: GPL-2.0-or-later
module main
import time
#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFError.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr, usize, &u8) i32
type SyncProbe = fn (u64, u64, u64, u64, u64, u64, u64, &u64)
type SyncSign = fn (u64, u64) u64
type SyncCreate = fn (&char, u64) u64
type SyncRelease = fn (u64)
type SyncSubmit = fn (u64, voidptr, DispatchFunction)
type SyncSet = fn (u64, u64, voidptr, DispatchFunction)
type SyncGet = fn (u64) voidptr
type SyncTuple = fn (u64, u64, &u64, u64, u64) SwiftAssociatedMetadata
struct SyncApi {
	native bool
	entry u64
	closure u64
	guard u64
	int_type u64
	void_type u64
	string_type u64
	tuple_type u64
	@[required]
	probe SyncProbe
	@[required]
	create SyncCreate
	@[required]
	release SyncRelease
	@[required]
	async_queue SyncSubmit
	@[required]
	set SyncSet
	@[required]
	get SyncGet
}
struct SyncState {
	api SyncApi
	queue u64
	kind int
	throwing bool
	owner u64
	error_owner u64
	on_main bool
mut:
	order int
	calls int
	copies int
	takes int
	destroys int
	finished u64
}
fn sync_keep(api SyncApi, owner u64) {
	$if macos { if api.native { C.CFRetain(voidptr(owner)); return } }
	objc_retain(owner)
}
fn sync_drop(api SyncApi, owner u64) {
	$if macos { if api.native { C.CFRelease(voidptr(owner)); return } }
	objc_release(owner)
}
fn sync_refs(api SyncApi, owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(voidptr(owner)) } }
	return obj_header(owner).refs
}
fn sync_witness(metadata u64, slot u64) u64 {
	return read64((read64(metadata - 8) & 0x0000ffffffffffff) + slot * 8) & 0x0000ffffffffffff
}
fn sync_lookup() u64 {
	mut entry := u64(0)
	for _ in 0 .. 64 { entry = runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', '_$sSo17OS_dispatch_queueC8DispatchE4sync7executexxyKXE_tKlF') or { panic(err) } }
	return entry
}
fn sync_prior(context voidptr) {
	mut s := unsafe { &SyncState(context) }; assert s.order == 0; s.order = 1
}
fn sync_body(context u64, output u64) u64 {
	if context == 0 { unsafe { *(&u64(output)) = 0xabcdef }; return 0 }
	mut s := unsafe { &SyncState(context) }
	assert s.order == 1 && s.calls == 0
	assert u64(s.api.get(context)) == context
	if s.on_main { assert u64(C.pthread_self()) == ios_runtime.main_thread }
	s.calls++; s.order = 2
	if !s.api.native { worker := spawn sync_lookup(); assert worker.wait() == s.api.entry }
	if s.throwing {
		// A throwing closure owns no initialized result, even if it touched its
		// temporary. Destruction or publishing these invalid words would fail.
		if s.kind != 1 { unsafe { *(&u64(output)) = 0xdeadbeef } }
		sync_keep(s.api, s.error_owner); return s.error_owner
	}
	if s.kind == 0 { unsafe { *(&u64(output)) = 0x123456789abcdef0 } }
	if s.kind in [2, 3]! {
		sync_keep(s.api, s.owner)
		unsafe { *(&SwiftStringWords(output)) = SwiftStringWords{first: 21, second: s.owner | u64(0x5000000000000000)} }
	}
	if s.kind == 3 {
		unsafe { *(&u64(output + 16)) = 0x332211; *(&u64(output + 24)) = 0x665544 }
		// A second Swift sync on a distinct serial queue must be callable while
		// the first callback owns its queue, without holding runtime locks.
		sync_case(s.api, 0, false, false)
	}
	return 0
}
fn sync_result_copy(destination u64, source u64, metadata u64) u64 {
	mut s := unsafe { &SyncState(read64(metadata + 8)) }; s.copies++
	copy_value := unsafe { SwiftSequenceCopy(voidptr(sync_witness(s.api.string_type, 2))) }
	copy_value(destination, source, s.api.string_type)
	C.memcpy(voidptr(destination + 16), voidptr(source + 16), 16)
	return destination
}
fn sync_result_take(destination u64, source u64, metadata u64) u64 {
	mut s := unsafe { &SyncState(read64(metadata + 8)) }; s.takes++
	C.memcpy(voidptr(destination), voidptr(source), 32); return destination
}
fn sync_result_destroy(value u64, metadata u64) {
	mut s := unsafe { &SyncState(read64(metadata + 8)) }; s.destroys++
	destroy := unsafe { SwiftSequenceDestroy(voidptr(sync_witness(s.api.string_type, 1))) }
	destroy(value, s.api.string_type)
}
fn sync_result_tag(_value u64, _cases u32, _metadata u64) u32 { return 0 }
fn sync_invoke(api SyncApi, context u64, metadata u64, queue u64, output u64, incoming u64) u64 {
	mut observed := [u64(0xcafe), 0, 0, 0xbeef]!
	api.probe(api.entry, api.closure, context, metadata, queue, output, incoming, unsafe { &observed[1] })
	assert observed[0] == 0xcafe && observed[3] == 0xbeef && observed[1] == queue
	return observed[2]
}
fn sync_case(api SyncApi, kind int, throwing bool, on_main bool) {
	queue := if on_main { darwin_dispatch_queue_create_with_target(c'vinix.swift.sync.main', 0, darwin_dispatch_get_main_queue()) }
		else { api.create(c'vinix.swift.sync', 0) }
	mut owner := u64(0); mut error_owner := u64(0)
	$if macos { if api.native {
		owner = u64(C.CFStringCreateWithBytes(unsafe { nil }, c'sync owned value text', 21, 0x08000100, false))
		domain := C.CFStringCreateWithBytes(unsafe { nil }, c'sync', 4, 0x08000100, false)
		error_owner = u64(C.CFErrorCreate(unsafe { nil }, domain, -9, unsafe { nil })); C.CFRelease(domain)
	} }
	if !api.native { owner = owned_string('sync owned value text'); error_owner = objc_allocate(cf_error_type_id()) }
	mut state := SyncState{api: api, queue: queue, kind: kind, throwing: throwing, owner: owner, error_owner: error_owner, on_main: on_main}
	context := u64(unsafe { &state })
	api.set(queue, context, voidptr(context), unsafe { nil })
	api.async_queue(queue, voidptr(context), sync_prior)
	mut table := [12]u64{}
	for i in 0 .. 8 { table[i] = u64(unsafe { voidptr(sync_result_take) }) }
	table[1] = u64(unsafe { voidptr(sync_result_destroy) }); table[2] = u64(unsafe { voidptr(sync_result_copy) })
	table[6] = u64(unsafe { voidptr(sync_result_tag) }); table[8] = 32; table[9] = 32; table[10] = 0x10007
	mut record := [u64(unsafe { &table[0] }), u64(0x200), context]!
	metadata := if kind == 0 { api.int_type } else if kind == 1 { api.void_type }
		else if kind == 2 { api.string_type } else if api.native { api.tuple_type } else { u64(unsafe { &record[1] }) }
	mut output := [u64(0xcafe), 0x7171717171717171, 0x7171717171717171, 0x7171717171717171, 0x7171717171717171, 0xbeef]!
	result := if kind == 1 { api.guard } else { u64(unsafe { &output[1] }) }
	incoming := if throwing { u64(0) } else { u64(0x5021) }
	if on_main {
		worker := spawn sync_background(api, context, metadata, queue, result, incoming)
		limit := time.sys_mono_now() + 5_000_000_000
		for C.ios_load_pointer(unsafe { &state.finished }) == 0 {
			assert time.sys_mono_now() < limit; dispatch_main_drain(); time.sleep(time.millisecond)
		}
		assert worker.wait() == if throwing { error_owner } else { incoming }
	} else { assert sync_invoke(api, context, metadata, queue, result, incoming) == if throwing { error_owner } else { incoming } }
	assert state.order == 2 && state.calls == 1 && output[0] == 0xcafe && output[5] == 0xbeef
	assert sync_refs(api, error_owner) == if throwing { i64(2) } else { i64(1) }
	if throwing { sync_drop(api, error_owner) }
	if throwing || kind == 1 {
		for i in 1 .. 5 { assert output[i] == 0x7171717171717171 }
		assert state.copies == 0 && state.takes == 0 && state.destroys == 0
	} else {
		if kind == 0 { assert output[1] == 0x123456789abcdef0 && output[2] == 0x7171717171717171 }
		if kind in [2, 3]! {
			assert output[1] == 21 && output[2] == owner | u64(0x5000000000000000) && sync_refs(api, owner) == 2
			if kind == 2 { assert output[3] == 0x7171717171717171 }
			if kind == 3 {
				assert output[3] == 0x332211 && output[4] == 0x665544
				if !api.native { assert state.copies == 1 && state.takes == 1 && state.destroys == 1 }
			}
		}
		destroy := unsafe { SwiftSequenceDestroy(voidptr(sync_witness(metadata, 1))) }; destroy(result, metadata)
	}
	assert sync_refs(api, owner) == 1 && sync_refs(api, error_owner) == 1
	api.set(queue, context, unsafe { nil }, unsafe { nil }); api.release(queue)
	if !api.native { assert !dispatch_objc_is_queue(queue) }
	sync_drop(api, owner); sync_drop(api, error_owner)
}
fn sync_background(api SyncApi, context u64, metadata u64, queue u64, output u64, incoming u64) u64 {
	result := sync_invoke(api, context, metadata, queue, output, incoming)
	mut s := unsafe { &SyncState(context) }; C.ios_store_pointer(unsafe { &s.finished }, 1); return result
}
fn sync_emit(code u64) {
	// C -> Swift sync, including borrowed x20 and incoming/outgoing x21.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0703f3,
		0xaa0403f4, 0xaa0503e8, 0xaa0603f5, 0xaa0103e0, 0xaa0203e1, 0xaa0303e2,
		0xd63f0200, 0xa9005674, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	// Swift closure -> C body, returning an owned error in Swift's x21.
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e0, 0xaa0803e1, 0x58000130,
		0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! { write32(code + 128 + u64(i * 4), op) }
	unsafe { *(&u64(code + 176)) = u64(voidptr(sync_body)) }
	write32(code + 256, 0xdac10020); write32(code + 260, 0xd65f03c0)
}
fn sync_bad(function u64, context u64, metadata u64, queue u64, output u64) {
	if _ := swift_dispatch_sync_checked(function, context, metadata, queue, output) { assert false, 'unsupported Swift sync accepted' }
}
fn test_swift_dispatch_sync() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1); sync_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 264)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { SyncProbe(voidptr(code)) }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); lib := C.dlopen(c'/usr/lib/swift/libswiftDispatch.dylib', 2)
		dispatch := C.dlopen(c'/usr/lib/system/libdispatch.dylib', 2)
		int_type := u64(C.dlsym(core, c'$sSiN')); string_type := u64(C.dlsym(core, c'$sSSN'))
		mut elements := [string_type, int_type, int_type]!
		get_tuple := unsafe { SyncTuple(C.dlsym(core, c'swift_getTupleTypeMetadata')) }
		tuple := get_tuple(0, 3, unsafe { &elements[0] }, 0, 0)
		sign := unsafe { SyncSign(voidptr(code + 256)) }
		api := SyncApi{native: true, entry: u64(C.dlsym(lib, c'$sSo17OS_dispatch_queueC8DispatchE4sync7executexxyKXE_tKlF')),
			closure: sign(code + 128, 29199), guard: guard, int_type: int_type, string_type: string_type,
			void_type: u64(C.dlsym(core, c'$sytN')) + 8, tuple_type: tuple.metadata, probe: probe,
			create: unsafe { SyncCreate(C.dlsym(dispatch, c'dispatch_queue_create')) }, release: unsafe { SyncRelease(C.dlsym(dispatch, c'dispatch_release')) },
			async_queue: unsafe { SyncSubmit(C.dlsym(dispatch, c'dispatch_async_f')) },
			set: unsafe { SyncSet(C.dlsym(dispatch, c'dispatch_queue_set_specific')) }, get: unsafe { SyncGet(C.dlsym(dispatch, c'dispatch_get_specific')) }}
		assert api.entry != 0 && tuple.state == 0
		for kind in 0 .. 4 { for throwing in [false, true]! { sync_case(api, kind, throwing, false) } }
		println('IOS-DISPATCH-SYNC-NATIVE: x0 closure/x1 context/x2 Result metadata/x8 indirect result/x20 queue/x21 owned error, incoming x21 preservation, Int/protected Void/String/four-word tuple, untouched throwing outputs, balanced result/error ownership, serial ordering/specific context and nested Swift sync')
	}
	sync_bad(guard, guard, guard, guard, guard)
	for _ in 0 .. 2 {
		objc_start(); sync_bad(guard, guard, guard, guard, guard)
		if _ := swift_dispatch_symbol('_$sSo17OS_dispatch_queueC8DispatchE4sync7executexxyKXE_tKlF') { assert false }
		assert ios_runtime.swift_dispatch_flags_arena == 0; system_data_start()!
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSo17OS_dispatch_queueC8DispatchE4sync7executexxyKXE_tKlF') { assert false }
		if _ := swift_dispatch_symbol('_$sSo17OS_dispatch_queueC8DispatchE4syncUnsafe7executexxyKXE_tKlF') { assert false }
		assert ios_runtime.swift_dispatch_flags_arena == 0
		mut workers := []thread u64{}; for _ in 0 .. 8 { workers << spawn sync_lookup() }; entries := workers.wait()
		for other in entries { assert other == entries[0] }
		api := SyncApi{entry: entries[0], closure: code + 128, guard: guard, int_type: swift_integer_metadata(),
			string_type: swift_string_metadata(), void_type: swift_void_full_metadata() + 8, probe: probe,
			create: darwin_dispatch_queue_create, release: darwin_dispatch_release, async_queue: darwin_dispatch_async_f,
			set: darwin_dispatch_queue_set_specific, get: darwin_dispatch_get_specific}
		queue := api.create(c'vinix.swift.sync.validation', 0)
		for args in [[u64(0), guard, api.int_type, queue, guard]!, [code + 129, guard, api.int_type, queue, guard]!,
			[api.closure, guard, 0, queue, guard]!, [api.closure, guard, 1, queue, guard]!,
			[api.closure, guard, api.int_type, queue, 0]!, [api.closure, guard, api.int_type, queue, guard + 1]!,
			[guard, guard, guard, guard, guard]!]! { sync_bad(args[0], args[1], args[2], args[3], args[4]) }
		mut invalid_table := [12]u64{}
		mut invalid_type := [u64(unsafe { &invalid_table[0] }), u64(0x200)]!
		for change in [[u64(8), 65537]!, [u64(9), 0]!, [u64(9), 7]!, [u64(8), 16]!,
			[u64(10), 6]!, [u64(10), 0x400007]!, [u64(1), 0]!, [u64(2), 0]!,
			[u64(4), 0]!, [u64(6), 0]!, [u64(2), code + 129]!]! {
			C.memcpy(unsafe { &invalid_table[0] }, voidptr(read64(api.int_type - 8)), 88)
			invalid_table[int(change[0])] = change[1]
			sync_bad(api.closure, guard, u64(unsafe { &invalid_type[1] }), queue, guard)
		}
		mut null_context_result := u64(0)
		assert sync_invoke(api, 0, api.int_type, queue, u64(unsafe { &null_context_result }), 0) == 0
		assert null_context_result == 0xabcdef
		api.release(queue)
		for kind in 0 .. 4 { for throwing in [false, true]! { sync_case(api, kind, throwing, false) } }
		for throwing in [false, true]! { sync_case(api, 3, throwing, true) }
		main_queue := darwin_dispatch_get_main_queue()
		dispatch_stop(); sync_bad(guard, guard, guard, main_queue, guard)
		arena := ios_runtime.swift_dispatch_flags_arena; objc_stop(); sync_bad(guard, guard, guard, guard, guard)
		assert ios_runtime.swift_dispatch_flags_retired && ios_runtime.swift_dispatch_flags_arena == 0 && ios_runtime.live == 0
		$if macos { assert C.mprotect(voidptr(arena), page * 2, C.PROT_READ) == -1 }
		$else { mut resident := [u8(0), 0]!; assert C.mincore(voidptr(arena), page * 2, unsafe { &resident[0] }) == -1 }
		system_data_stop()
	}
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0
	println('IOS-DISPATCH-SYNC: native generic throwing ABI, owned String/four-word results and copy/destroy/take witnesses, protected Void/throwing outputs, null context, serial ordering/specific context, nested resolution and Swift sync, background-to-main completion, unsupported/lifetime rejection, eight-worker shared publication and unmapped lifetimes')
}
