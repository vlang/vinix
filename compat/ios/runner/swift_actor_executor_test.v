// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)

struct ActorExecutorWords { identity u64 implementation u64 }
struct ActorFixture {
	metadata u64
	table u64
	expected ActorExecutorWords
	owner u64
	native bool
	reenter bool
	entry u64
mut:
	calls int
}
type ActorProbe = fn (u64, u64, u64, u64, u64, &u64)
type ActorSign = fn (u64, u64) u64

fn actor_refs(native bool, owner u64) i64 {
	$if macos { if native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) } }
	return obj_header(owner).refs
}

fn actor_resolve_worker() u64 {
	entry := runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', '_$sScA15unownedExecutorScevgTj') or { panic(err) }
	for _ in 0 .. 128 {
		assert runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', '_$sScP8rawValues5UInt8Vvg') or { panic(err) } == entry + 32
		assert read32(entry) == 0xf9400430 && read32(entry + 4) == 0xd61f0200
		assert read32(entry + 32) == 0x39400280 && read32(entry + 36) == 0xd65f03c0
	}
	return entry
}

fn actor_getter(metadata u64, table u64, receiver u64, error_word u64) ActorExecutorWords {
	mut state := unsafe { &ActorFixture(receiver) }
	assert metadata == state.metadata && table == state.table && error_word == 0x5021
	assert actor_refs(state.native, state.owner) == 1
	state.calls++
	if state.reenter && state.calls == 1 {
		worker := spawn actor_resolve_worker()
		assert worker.wait() == state.entry
	}
	return state.expected
}

fn actor_emit_probe(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0203f4,
		0xaa0303f5, 0xaa0403f0, 0xd63f0200, 0xa9000660, 0xa9015674,
		0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	// Witness -> ordinary V callback, retaining both Swift registers on entry.
	for i, op in [u32(0xaa1403e2), 0xaa1503e3, 0x58000090, 0xd61f0200, 0xd503201f, 0xd503201f]! { write32(code + 64 + u64(i * 4), op) }
	unsafe { *(&u64(code + 88)) = u64(voidptr(actor_getter)) }
	// PAC belongs only to the native arm64e comparison's witness fixture.
	write32(code + 96, 0xdac10020); write32(code + 100, 0xd65f03c0)
}

fn actor_fixture(probe ActorProbe, sign ActorSign, callback u64, entry u64, native bool, reenter bool) {
	page := usize(C.getpagesize())
	mut owner := u64(0)
	$if macos { if native { owner = u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
	if !native { owner = owned_string('borrowed actor dispatch fixture owner') }
	assert owner != 0 && actor_refs(native, owner) == 1
	for tail in [false, true]! {
		data := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert data != u64(-1)
		assert C.mprotect(unsafe { voidptr(data) }, page, C.PROT_NONE) == 0
		assert C.mprotect(unsafe { voidptr(data + u64(page * 2)) }, page, C.PROT_NONE) == 0
		table := if tail { data + u64(page * 2) - 16 } else { data + u64(page) - 8 }
		slot := table + 8
		pointer := if native { sign(callback, slot | u64(26998) << 48) } else { callback }
		unsafe { *(&u64(slot)) = pointer }
		assert C.mprotect(unsafe { voidptr(data + u64(page)) }, page, C.PROT_READ) == 0
		for expected in [ActorExecutorWords{}, ActorExecutorWords{ identity: 0, implementation: 1 },
			ActorExecutorWords{ identity: ~u64(0), implementation: 0x123456789abcdef0 },
			ActorExecutorWords{ identity: data, implementation: callback }]! {
			mut state := ActorFixture{ metadata: data, table: table, expected: expected,
				owner: owner, native: native, reenter: reenter, entry: entry }
			receiver := u64(unsafe { &state })
			for _ in 0 .. 128 {
				mut output := [u64(0x1234), 0, 0, 0, 0, 0x5678]!
				probe(data, table, receiver, 0x5021, entry, unsafe { &output[1] })
				assert output[0] == 0x1234 && output[5] == 0x5678
				assert output[1] == expected.identity && output[2] == expected.implementation
				assert output[3] == receiver && output[4] == 0x5021
			}
			assert state.calls == 128 && actor_refs(native, owner) == 1
		}
		assert C.munmap(unsafe { voidptr(data) }, page * 3) == 0
	}
	$if macos { if native { C.CFRelease(unsafe { voidptr(owner) }) } }
	if !native { objc_release(owner) }
}

fn actor_priority_fixture(probe ActorProbe, entry u64) {
	page := usize(C.getpagesize())
	data := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert data != u64(-1)
	assert C.mprotect(unsafe { voidptr(data) }, page, C.PROT_NONE) == 0
	assert C.mprotect(unsafe { voidptr(data + u64(page * 2)) }, page, C.PROT_NONE) == 0
	first := data + u64(page * 2) - 256
	for value in 0 .. 256 { unsafe { *(&u8(first + u64(value))) = u8(value) } }
	assert C.mprotect(unsafe { voidptr(data + u64(page)) }, page, C.PROT_READ) == 0
	for value in 0 .. 256 { for _ in 0 .. 8 {
		receiver := first + u64(value)
		mut output := [u64(0x1234), 0, 0, 0, 0, 0x5678]!
		probe(data, data + u64(page * 2), receiver, 0x5021, entry, unsafe { &output[1] })
		assert output[0] == 0x1234 && output[5] == 0x5678 && output[1] == u64(value)
		assert output[3] == receiver && output[4] == 0x5021
		// x1 is not a return value of this scalar getter.
	} }
	assert C.munmap(unsafe { voidptr(data) }, page * 3) == 0
}

fn test_swift_actor_executor() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	actor_emit_probe(code)
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 104) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { ActorProbe(voidptr(code)) }; sign := unsafe { ActorSign(voidptr(code + 96)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswift_Concurrency.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		entry := u64(C.dlsym(lib, c'$sScA15unownedExecutorScevgTj'))
		priority := u64(C.dlsym(lib, c'$sScP8rawValues5UInt8Vvg'))
		assert entry != 0 && priority != 0
		actor_fixture(probe, sign, code + 64, entry, true, false)
		actor_priority_fixture(probe, priority)
		println('IOS-SWIFT-ACTOR-EXECUTOR-NATIVE: authenticated word-1 protocol dispatch, unchanged opaque executor pair, borrowed metadata/table/self and owner, guarded x20/x21, protected descriptor/tail boundaries; TaskPriority indirect byte getter passes all 256 UInt8 values and an exact protected boundary. Fixtures do not create genuine actors or schedule tasks.')
	}
	if _ := swift_concurrency_entry(0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		assert ios_runtime.swift_concurrency_code == 0 && !ios_runtime.swift_concurrency_retired
		for name in ['_$sScPSgMa', '_$sScMScAsMc', '_swift_task_cancel', '_swift_once']! {
			if _ := runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', name) { assert false }
		}
		assert ios_runtime.swift_concurrency_code == 0
		mut resolvers := []thread u64{}
		for _ in 0 .. 8 { resolvers << spawn actor_resolve_worker() }
		addresses := resolvers.wait(); entry := addresses[0]
		for address in addresses { assert address == entry }
		assert ios_runtime.swift_concurrency_code == entry && ios_runtime.swift_hash_code == 0
		actor_fixture(probe, sign, code + 64, entry, false, true)
		actor_priority_fixture(probe, entry + 32)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn actor_fixture(probe, sign, code + 64, entry, false, false) }
		workers.wait()
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sScA15unownedExecutorScevgTj') { assert false }
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_objc_metadata.len == 0
		objc_stop()
		assert ios_runtime.swift_concurrency_code == 0 && ios_runtime.swift_concurrency_retired
		if _ := swift_concurrency_entry(0) { assert false }
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-ACTOR-EXECUTOR: caller witness forwarding and opaque two-word return, borrowed owners and x20/x21, protected read-only table and byte boundaries, UInt8 getter, eight concurrent resolvers and workers, callback joining a resolver, unsupported imports and wrong-library rejection, two sealed code-page lifetimes with joined callbacks before retirement')
}
