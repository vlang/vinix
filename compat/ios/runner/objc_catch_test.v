// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type CatchBegin = fn (u64) u64
type CatchEnd = fn ()
type CatchProbe = fn (&u64, u64, &u64)
struct CatchApi {
	@[required]
	begin CatchBegin
	@[required]
	end CatchEnd
}
struct CatchState {
mut:
	calls i64
	identity u64
}
const catch_foreign_class = u64(0x564e585f464f524e)

fn catch_cleanup(reason i32, exception u64) {
	assert reason == 1 && read64(exception) == catch_foreign_class
	state := unsafe { &CatchState(read64(exception + 32)) }
	assert state.identity == exception
	C.ios_ref_change(unsafe { &state.calls }, 1)
}
fn catch_record(state &CatchState) u64 {
	// A real foreign _Unwind_Exception (32 bytes on both tested ARM64 ABIs).
	// Prefix storage accommodates libc++abi's imaginary preceding header.
	base := u64(C.calloc(1, 256)); assert base != 0 && base & 15 == 0
	for i in 0 .. 16 { unsafe { *(&u64(base + u64(i * 8))) = 0xa5a5a5a5a5a5a5a5 } }
	exception := base + 128
	unsafe {
		*(&u64(exception)) = catch_foreign_class
		*(&u64(exception + 8)) = u64(voidptr(catch_cleanup))
		*(&u64(exception + 32)) = u64(state)
		state.identity = exception
	}
	return exception
}
fn catch_record_free(exception u64, state &CatchState) {
	assert state.calls == 1 && read64(exception) == catch_foreign_class
	assert read64(exception + 8) == u64(unsafe { voidptr(catch_cleanup) })
	assert read64(exception + 16) == 0 && read64(exception + 24) == 0
	for i in 0 .. 16 { assert read64(exception - 128 + u64(i * 8)) == 0xa5a5a5a5a5a5a5a5 }
	C.free(unsafe { voidptr(exception - 128) })
}
fn catch_cases(api CatchApi, backend CatchApi) {
	for begin in [api.begin, backend.begin]! {
		for end in [api.end, backend.end]! {
			for _ in 0 .. 100 {
				mut state := CatchState{}
				exception := catch_record(unsafe { &state })
				assert begin(exception) == exception + 32
				assert state.calls == 0
				end(); assert state.calls == 1
				end(); assert state.calls == 1 // Empty, already-initialized catch stack.
				catch_record_free(exception, unsafe { &state })
			}
		}
	}
}
fn catch_wait(slot &i64, expected i64) {
	deadline := time.sys_mono_now() + 30 * time.second
	for C.ios_ref_change(slot, 0) != expected {
		assert time.sys_mono_now() < deadline
		time.sleep(time.millisecond)
	}
}
fn catch_worker(api CatchApi, ready &i64, gate &i64) {
	mut state := CatchState{}; exception := catch_record(unsafe { &state })
	assert api.begin(exception) == exception + 32
	C.ios_ref_change(ready, 1); catch_wait(gate, 1)
	assert state.calls == 0
	api.end(); catch_record_free(exception, unsafe { &state })
}
fn catch_threads(api CatchApi) {
	mut ready := i64(0); mut gate := i64(0); mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn catch_worker(api, unsafe { &ready }, unsafe { &gate }) }
	catch_wait(unsafe { &ready }, 4)
	C.ios_ref_change(unsafe { &gate }, 1)
	workers.wait(); unsafe { workers.free() }
}
fn catch_resolve(symbol string) u64 {
	return runtime_symbol('/usr/lib/libobjc.A.dylib', symbol) or { panic(err) }
}
fn catch_reader() u64 {
	entry := catch_resolve('_objc_begin_catch')
	for _ in 0 .. 1024 { assert catch_resolve('_objc_begin_catch') == entry && catch_resolve('_objc_end_catch') != 0 }
	return entry
}
__global catch_callbacks = 0
fn catch_callback(object u64, selector u64) {
	assert catch_resolve('_objc_begin_catch') != 0 && catch_resolve('_objc_end_catch') != 0
	catch_callbacks++
}

fn catch_fallback(probe CatchProbe, code u64, pointer u64, guard u64, shared u64, symbol string) {
	mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
	child := C.ios_fork(); assert child >= 0
	if child == 0 {
		C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
		input := [pointer, guard, guard, guard, guard, guard, guard, guard, guard, guard, shared, guard, guard]!
		mut output := [6]u64{}; probe(unsafe { &input[0] }, code, unsafe { &output[0] }); C._exit(0)
	}
	C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
	for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
	C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(child, &status, 0) == child && status == 256
	output := unsafe { tos(&bytes[0], length) }
	assert output.contains('iOS: ' + symbol + ' requires the C++ exception runtime backend')
	for bad in ['runtime error:', 'AddressSanitizer', 'SIGSEGV', 'SIGBUS', 'Segmentation fault']! { assert !output.contains(bad), output }
}
fn catch_no_backend() {
	page := usize(C.getpagesize()); code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0)); shared := base + u64(page)
	assert code != u64(-1) && guard != u64(-1) && base != u64(-1)
	for i, op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 100)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { CatchProbe(voidptr(code)) }
	for writable in [true, false]! {
		assert C.mprotect(voidptr(shared), page, C.PROT_READ | C.PROT_WRITE) == 0; C.memset(voidptr(shared), 0xa5, page)
		if !writable { assert C.mprotect(voidptr(shared), page, C.PROT_READ) == 0 }
		for symbol in ['objc_begin_catch', 'objc_end_catch']! {
			entry := catch_resolve('_' + symbol)
			for pointer in [u64(0), 1, ~u64(0), guard, shared, shared + u64(page) - 32]! { catch_fallback(probe, entry, pointer, guard, shared, symbol) }
		}
		for i in u64(0) .. u64(page) { assert unsafe { *(&u8(shared + i)) } == 0xa5 }
	}
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0 && C.munmap(voidptr(base), page * 3) == 0
}
fn test_objc_catch() {
	$if macos {
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2); cpp := C.dlopen(c'/usr/lib/libc++.1.dylib', 2)
		assert objc != unsafe { nil } && cpp != unsafe { nil }
		api := CatchApi{begin: unsafe { CatchBegin(C.dlsym(objc, c'objc_begin_catch')) }, end: unsafe { CatchEnd(C.dlsym(objc, c'objc_end_catch')) }}
		backend := CatchApi{begin: unsafe { CatchBegin(C.dlsym(cpp, c'__cxa_begin_catch')) }, end: unsafe { CatchEnd(C.dlsym(cpp, c'__cxa_end_catch')) }}
		catch_cases(api, backend); catch_threads(api)
		assert C.dlclose(objc) == 0 && C.dlclose(cpp) == 0
		println('NATIVE-OBJC-CATCH: foreign adjusted pointers, four mixed Objective-C/C++ begin/end combinations, single cleanup, empty-stack end and four simultaneous thread-local catches; no throwing or unwinding')
	}
	begin := catch_resolve('_objc_begin_catch'); end := catch_resolve('_objc_end_catch')
	for symbol in ['objc_begin_catch', '_objc_begin_catchExtra', '_objc_end_catchExtra', '___cxa_begin_catch', '___cxa_end_catch', '_objc_exception_throw', '_objc_exception_rethrow']! { if _ := objc_catch_symbol(symbol) { assert false } }
	for _ in 0 .. 2 {
		objc_start(); mut readers := []thread u64{}
		for _ in 0 .. 8 { readers << spawn catch_reader() }; for reader in readers { assert reader.wait() == begin }; unsafe { readers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libc++.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! { for symbol in ['_objc_begin_catch', '_objc_end_catch']! { if _ := runtime_symbol(library, symbol) { assert false } } }
		$if ios_cxx ? {
			backend_begin := cxx_symbol('___cxa_begin_catch') or { panic(err) }; backend_end := cxx_symbol('___cxa_end_catch') or { panic(err) }
			assert begin == backend_begin && end == backend_end
			api := CatchApi{begin: unsafe { CatchBegin(voidptr(begin)) }, end: unsafe { CatchEnd(voidptr(end)) }}
			backend := CatchApi{begin: unsafe { CatchBegin(voidptr(backend_begin)) }, end: unsafe { CatchEnd(voidptr(backend_end)) }}
			catch_cases(api, backend); catch_threads(api)
		} $else { catch_no_backend() }
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.ns_exception_type_arena == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixCatchTeardown', 0)
		assert cls != 0 && objc_add_method(cls, u64(c'dealloc'), u64(unsafe { voidptr(catch_callback) }), c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := catch_callbacks
		objc_stop(); assert catch_callbacks == before + 1 && ios_runtime.live == 0
		assert catch_resolve('_objc_begin_catch') == begin && catch_resolve('_objc_end_catch') == end
	}
	$if ios_cxx ? { println('IOS-OBJC-CATCH: exact backend aliases, foreign adjusted pointers and mixed-language handler ownership, single cleanup, empty-stack end, four simultaneous TLS catches, eight resolver readers, callback access and two drained runtimes; Mach-O throwing/unwinding remain unsupported') }
	$else { println('IOS-OBJC-CATCH: exact no-backend diagnostics, 48 protected child calls with null/invalid/protected storage and unchanged writable/read-only result pages, eight resolver readers, callback access and two drained runtimes; no exception state or result fabricated') }
}
