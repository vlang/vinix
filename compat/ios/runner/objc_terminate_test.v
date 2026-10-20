// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
#include <sys/resource.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.setrlimit(i32, voidptr) i32
fn C.ios_signal(i32, voidptr) voidptr
// Typed declarations for test-only access to the linked backend's handler
// state. These symbols are not added to the application's import resolver.
@[c_extern]
fn C._ZSt13set_terminatePFvvE(fn ()) fn ()
@[c_extern]
fn C._ZSt13get_terminatev() fn ()
type TerminateCall = fn ()
type TerminateProbe = fn (&u64, u64, &u64)
type TerminateBegin = fn (u64) u64
const terminate_foreign_class = u64(0x564e585f464f524e)

fn terminate_first() { C._exit(85) }
fn terminate_second() { C._exit(86) }
fn terminate_returning() {}
fn terminate_uncaught(object u64) { C._exit(88) }
fn terminate_cleanup(reason i32, exception u64) { C._exit(87) }
fn terminate_resolve() u64 { return runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_terminate') or { panic(err) } }
fn terminate_reader() u64 {
	entry := terminate_resolve(); for _ in 0 .. 1024 { assert terminate_resolve() == entry }; return entry
}
__global terminate_callbacks = 0
fn terminate_callback(object u64, selector u64) { assert terminate_resolve() != 0; terminate_callbacks++ }

fn terminate_child(probe TerminateProbe, entry u64, pointer u64, guard u64, result u64, record u64, active bool, handler TerminateCall, expected i32, native bool) {
	mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
	child := C.ios_fork(); assert child >= 0
	if child == 0 {
		C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
		mut limit := [u64(0), 0]!; assert C.setrlimit(i32(C.RLIMIT_CORE), unsafe { voidptr(&limit[0]) }) == 0
		C.ios_signal(C.SIGABRT, unsafe { nil })
		if active {
			$if ios_cxx ? { begin := cxx_symbol('___cxa_begin_catch') or { panic(err) }; assert unsafe { TerminateBegin(voidptr(begin))(record) } == record + 32 }
		}
		C._ZSt13set_terminatePFvvE(handler)
		assert C._ZSt13get_terminatev() == handler
		// All argument registers, stack words, Swift Self and x8 are unused.
		input := [pointer, guard, guard, guard, guard, guard, guard, guard, guard, guard, result, guard, guard]!
		mut output := [6]u64{}; probe(unsafe { &input[0] }, entry, unsafe { &output[0] }); C._exit(0)
	}
	C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
	for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
	C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(child, &status, 0) == child
	output := unsafe { tos(&bytes[0], length) }
	mut backend := native
	$if ios_cxx ? { backend = true }
	if backend {
		if expected == -1 { assert status & 127 == i32(C.SIGABRT), output } else { assert status == expected << 8, output }
		assert !output.contains('requires the C++ exception runtime backend')
	} else {
		assert status == 256 && output.contains('iOS: objc_terminate requires the C++ exception runtime backend'), output
	}
	for bad in ['runtime error:', 'AddressSanitizer', 'SIGSEGV', 'SIGBUS', 'Segmentation fault', 'Mach-O frames is not implemented']! { assert !output.contains(bad), output }
}

fn test_objc_terminate() {
	entry := terminate_resolve()
	$if ios_cxx ? { assert entry == (cxx_symbol('__ZSt9terminatev') or { panic(err) }) }
	$else { assert entry == u64(unsafe { voidptr(objc_terminate_unavailable) }) }
	for symbol in ['objc_terminate', '_objc_terminateExtra', '__ZSt9terminatev', '_objc_exception_throw', '_objc_exception_rethrow', '_objc_begin_catch', '_objc_end_catch']! { if _ := objc_terminate_symbol(symbol) { assert false } }
	// The original backend handler is restored in the parent and tested only
	// in children, including a handler that returns (which must still abort).
	original := C._ZSt13get_terminatev(); assert unsafe { voidptr(original) } != unsafe { nil }
	defer { C._ZSt13set_terminatePFvvE(original) }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0)); shared := base + u64(page)
	assert code != u64(-1) && guard != u64(-1) && base != u64(-1)
	for i, op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 100)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { TerminateProbe(voidptr(code)) }; record := shared + 128
	mut expected := []u8{len: int(page)}
	for _ in 0 .. 2 {
		objc_start(); mut readers := []thread u64{}
		for _ in 0 .. 8 { readers << spawn terminate_reader() }; for reader in readers { assert reader.wait() == entry }; unsafe { readers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libc++.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/swift/libswiftCore.dylib']! { if _ := runtime_symbol(library, '_objc_terminate') { assert false } }
		ns_set_uncaught_handler(u64(unsafe { voidptr(terminate_uncaught) }))
		assert C.mprotect(voidptr(shared), page, C.PROT_READ | C.PROT_WRITE) == 0; C.memset(voidptr(shared), 0xa5, page)
		unsafe { *(&u64(record)) = terminate_foreign_class; *(&u64(record + 8)) = u64(voidptr(terminate_cleanup)); *(&u64(record + 16)) = 0; *(&u64(record + 24)) = 0 }
		for i in 0 .. int(page) { expected[i] = unsafe { *(&u8(shared + u64(i))) } }
		for writable in [true, false]! {
			assert C.mprotect(voidptr(shared), page, C.PROT_READ | if writable { C.PROT_WRITE } else { 0 }) == 0
			for result in [shared, shared + u64(page) - 32]! { for pointer in [u64(0), 1, ~u64(0), guard, shared, shared + u64(page) - 32]! {
				for index, handler in [TerminateCall(terminate_first), terminate_second, terminate_returning, original]! {
					status := if index == 0 { i32(85) } else if index == 1 { i32(86) } else { i32(-1) }
					terminate_child(probe, entry, pointer, guard, result, record, false, handler, status, false)
					$if ios_cxx ? { terminate_child(probe, entry, pointer, guard, result, record, true, handler, status, false) }
				}
				for i in 0 .. int(page) { assert unsafe { *(&u8(shared + u64(i))) } == expected[i] }
			} }
		}
		assert C._ZSt13get_terminatev() == original && ns_get_uncaught_handler() == u64(unsafe { voidptr(terminate_uncaught) })
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.ns_exception_type_arena == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixTerminateTeardown', 0)
		assert cls != 0 && objc_add_method(cls, u64(c'dealloc'), u64(unsafe { voidptr(terminate_callback) }), c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := terminate_callbacks
		objc_stop(); assert terminate_callbacks == before + 1 && ios_runtime.live == 0 && terminate_resolve() == entry && ns_get_uncaught_handler() == 0
	}
	$if macos {
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2); assert objc != unsafe { nil }
		native := u64(C.dlsym(objc, c'objc_terminate')); assert native != 0
		// Compare native no-argument forwarding with controlled process exits.
		for index, handler in [TerminateCall(terminate_first), terminate_second, terminate_returning]! {
			terminate_child(probe, native, guard, guard, shared, record, false, handler, if index == 0 { i32(85) } else if index == 1 { i32(86) } else { i32(-1) }, true)
		}
		assert C.dlclose(objc) == 0
		println('NATIVE-OBJC-TERMINATE: two installed C++ handlers and returning-handler SIGABRT compared in isolated children; no throwing or unwinding invoked')
	}
	unsafe { expected.free() }; assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0 && C.munmap(voidptr(base), page * 3) == 0
	$if ios_cxx ? { println('IOS-OBJC-TERMINATE: exact std::terminate backend alias, 384 terminal children with empty/foreign catch bookkeeping, two custom handlers and default/returning-handler SIGABRT, protected unused arguments/stack/Self/x8 and unchanged writable/read-only pages at both boundaries, eight resolver readers, callback access and two drained runtimes; Mach-O throwing/unwinding remains unsupported') }
	$else { println('IOS-OBJC-TERMINATE: exact no-backend diagnostic, 192 terminal children ignore C++ handlers, protected unused arguments/stack/Self/x8 and unchanged writable/read-only pages at both boundaries, eight resolver readers, callback access and two drained runtimes') }
}
