// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.usleep(u32) i32

type SwiftOnce = fn (u64, u64, u64)
type OnceProbe = fn (u64, u64, u64, u64, &u64)
type OnceInline = fn (u64, u64, u64, u64)

__global once_test_tokens = [42]u64{}
__global once_null_calls = u64(0)
__global once_inline_entries = u64(0)

struct OnceState {
mut:
	calls u64
	first u64
	second u64
	once SwiftOnce = unsafe { nil }
	nested u64
	threaded u64
}

fn once_test_callback(context voidptr) {
	mut state := unsafe { &OnceState(context) }
	assert state.calls == 0
	state.calls++
	state.first = 0x12345678
	assert C.usleep(10000) == 0
	state.second = 0x87654321
}

fn once_test_reader(once SwiftOnce, token u64, context u64, inline_once OnceInline) {
	inline_once(token, u64(unsafe { voidptr(once_test_callback) }), context, u64(unsafe { voidptr(once) }))
	state := unsafe { &OnceState(context) }
	assert state.calls == 1 && state.first == 0x12345678 && state.second == 0x87654321
}

fn once_test_null(context voidptr) {
	assert context == unsafe { nil }
	once_null_calls++
}

fn once_test_counted_entry(predicate u64, function u64, context u64) {
	once_inline_entries++
	swift_once(predicate, function, context)
}

fn once_test_nested(context voidptr) {
	mut state := unsafe { &OnceState(context) }
	assert state.calls == 0
	state.calls++
	mut nested := OnceState{}
	state.once(state.nested, u64(unsafe { voidptr(once_test_callback) }), u64(unsafe { &nested }))
	assert nested.calls == 1 && nested.second == 0x87654321
	// Waiting for an independent token on another thread would deadlock if
	// either Swift or dispatch held the global runtime lock across callbacks.
	mut threaded := OnceState{}
	worker := spawn once_test_direct_reader(state.once, state.threaded, u64(unsafe { &threaded }))
	worker.wait()
	assert threaded.calls == 1 && threaded.second == 0x87654321
	state.first = 0x12345678
	state.second = 0x87654321
}

fn once_test_direct_reader(once SwiftOnce, token u64, context u64) {
	once(token, u64(unsafe { voidptr(once_test_callback) }), context)
	state := unsafe { &OnceState(context) }
	assert state.calls == 1 && state.first == 0x12345678 && state.second == 0x87654321
}

fn once_test_dispatch_entry(token u64, function u64, context u64) {
	darwin_dispatch_once_f(unsafe { &u64(token) }, unsafe { voidptr(context) }, unsafe { DispatchFunction(voidptr(function)) })
}

fn once_test_raw(probe OnceProbe, once SwiftOnce, token u64, function u64, context u64) {
	mut output := [u64(0x1234), 0, 0, 0, 0x5678]!
	probe(token, function, context, u64(unsafe { voidptr(once) }), unsafe { &output[1] })
	// The C entry returns void; x0 is deliberately ignored.
	assert output[0] == 0x1234 && output[4] == 0x5678
	assert output[2] == 0x5020 && output[3] == 0x5021
}

fn once_test_suite(once SwiftOnce, probe OnceProbe, inline_once OnceInline, start int, native bool, protected u64) {
	for index in start .. start + 16 {
		mut state := OnceState{}
		token := u64(unsafe { &once_test_tokens[index] })
		assert C.ios_load_pointer(unsafe { &u64(token) }) == 0
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn once_test_reader(once, token, u64(unsafe { &state }), inline_once) }
		workers.wait()
		assert C.ios_load_pointer(unsafe { &u64(token) }) != 0
		if !native { assert once_test_tokens[index] == swift_once_done && once_test_tokens[index] != ~u64(0) }
		for _ in 0 .. 128 {
			once_test_raw(probe, once, token, u64(unsafe { voidptr(once_test_callback) }), u64(unsafe { &state }))
			assert state.calls == 1
		}
		if !native {
			once_inline_entries = 0
			for _ in 0 .. 128 {
				inline_once(token, protected, protected, u64(unsafe { voidptr(once_test_counted_entry) }))
				once_test_raw(probe, once, token, 0, protected)
			}
			assert once_inline_entries == 128
		}
		unsafe { workers.free() }
	}
	mut nested := OnceState{once: once, nested: u64(unsafe { &once_test_tokens[start + 17] }), threaded: u64(unsafe { &once_test_tokens[start + 18] })}
	once_test_raw(probe, once, u64(unsafe { &once_test_tokens[start + 16] }), u64(unsafe { voidptr(once_test_nested) }), u64(unsafe { &nested }))
	assert nested.calls == 1 && nested.first == 0x12345678 && nested.second == 0x87654321
	once_null_calls = 0
	once_test_raw(probe, once, u64(unsafe { &once_test_tokens[start + 19] }), u64(unsafe { voidptr(once_test_null) }), 0)
	assert once_null_calls == 1
	// A canonical completed token needs no callback or context, and the token
	// can be read-only at the exact boundary before an inaccessible page.
	for _ in 0 .. 128 {
		once_test_raw(probe, once, protected - 8, 0, protected)
		once_test_raw(probe, once, protected - 8, protected, protected)
	}
}

fn once_test_reject(predicate u64, function u64) {
	if _ := swift_once_checked(predicate, function, 0) { assert false, 'invalid Swift once accepted' }
}

fn test_swift_once() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0303f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	// Match Swift's Darwin barrier-free compiler fast path: LDR, CMN #-1,
	// skip the runtime for -1 only, otherwise tail-call the C entry in x3.
	for i, op in [u32(0xf9400008), 0xb100051f, 0x54000040, 0xd61f0060, 0xd65f03c0]! { write32(code + 64 + u64(i * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 84) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { OnceProbe(voidptr(code)) }
	inline_once := unsafe { OnceInline(voidptr(code + 64)) }
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	protected := base + u64(page)
	unsafe { *(&u64(protected - 8)) = ~u64(0) }
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ) == 0
	assert C.mprotect(unsafe { voidptr(protected) }, page, C.PROT_NONE) == 0
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		once := unsafe { SwiftOnce(C.dlsym(lib, c'swift_once')) }
		assert once != unsafe { nil }
		once_test_suite(once, probe, inline_once, 0, true, protected)
		println('IOS-SWIFT-ONCE-NATIVE: static word tokens, eight readers per token publish both writes exactly once, 2048 completed raw calls preserve x20/x21, C context order, nested tokens and callback thread join, null context, protected completed token with unread callback/context')
	}
	once_test_reject(0, 0)
	once_test_reject(1, 0)
	once_test_reject(~u64(0) - 3, 0)
	for _ in 0 .. 2 {
		for index in 20 .. 42 { C.ios_store_pointer(unsafe { &once_test_tokens[index] }, 0) }
		once_test_reject(u64(unsafe { &once_test_tokens[20] }), u64(unsafe { voidptr(once_test_callback) }))
		objc_start()
		system_data_start()!
		once := unsafe { SwiftOnce(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_once') or { panic(err) })) }
		once_test_reject(u64(unsafe { &once_test_tokens[20] }), 0)
		assert system_data.dispatch_once.len == 0
		once_test_suite(once, probe, inline_once, 20, false, protected)
		assert system_data.dispatch_once.len == 20
		// The shared driver still provides dispatch_once's existing -1 token
		// convention and its distinct context-before-function argument order.
		for index in 40 .. 42 {
			mut state := OnceState{}
			token := u64(unsafe { &once_test_tokens[index] })
			mut workers := []thread{}
			for _ in 0 .. 8 { workers << spawn once_test_direct_reader(once_test_dispatch_entry, token, u64(unsafe { &state })) }
			workers.wait()
			assert once_test_tokens[index] == ~u64(0) && state.calls == 1
			unsafe { workers.free() }
		}
		assert system_data.dispatch_once.len == 22
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
		objc_stop()
		system_data_stop()
		assert system_data == unsafe { nil } && dispatch_runtime == unsafe { nil }
		// Fast completion does not allocate a mutex after teardown.
		once_test_raw(probe, once, protected - 8, protected, protected)
		once_test_raw(probe, once, u64(unsafe { &once_test_tokens[20] }), protected, protected)
	}
	assert C.munmap(unsafe { voidptr(base) }, page * 2) == 0
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-ONCE: native C argument order and preserved x20/x21, eight readers per token publish both writes exactly once through the Darwin compiler fast path, completed words keep that path entering the acquire adapter, nested callbacks with independent thread join, null context, unread completed callback/context and read-only boundary token, stable per-token cache, two joined and drained runtime cycles')
}
