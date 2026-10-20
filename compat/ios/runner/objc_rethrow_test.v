// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type RethrowProbe = fn (&u64, u64, &u64)
type RethrowBegin = fn (u64) u64
const rethrow_foreign_class = u64(0x564e585f464f524e)

fn rethrow_cleanup(reason i32, exception u64) { C._exit(87) }
fn rethrow_resolve() u64 { return runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_exception_rethrow') or { panic(err) } }
fn rethrow_reader() u64 {
	entry := rethrow_resolve(); for _ in 0 .. 1024 { assert rethrow_resolve() == entry }; return entry
}
__global rethrow_callbacks = 0
fn rethrow_callback(object u64, selector u64) { assert rethrow_resolve() != 0; rethrow_callbacks++ }
fn rethrow_child(probe RethrowProbe, entry u64, pointer u64, guard u64, result u64, record u64, active bool) {
	mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
	child := C.ios_fork(); assert child >= 0
	if child == 0 {
		C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
		$if ios_cxx ? {
			if active {
				begin := cxx_symbol('___cxa_begin_catch') or { panic(err) }
				assert unsafe { RethrowBegin(voidptr(begin))(record) } == record + 32
			}
		}
		// Rethrow has no arguments: all these registers/stack words are unused.
		input := [pointer, guard, guard, guard, guard, guard, guard, guard, guard, guard, result, guard, guard]!
		mut output := [6]u64{}; probe(unsafe { &input[0] }, entry, unsafe { &output[0] }); C._exit(0)
	}
	C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
	for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
	C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(child, &status, 0) == child && status == 256
	output := unsafe { tos(&bytes[0], length) }
	$if ios_cxx ? { assert output.contains('iOS: C++ exception unwinding through Mach-O frames is not implemented') && !output.contains('requires the C++ exception runtime backend'), output }
	$else { assert output.contains('iOS: objc_exception_rethrow requires the C++ exception runtime backend') && !output.contains('C++ exception unwinding through Mach-O frames'), output }
	for bad in ['runtime error:', 'AddressSanitizer', 'SIGSEGV', 'SIGBUS', 'Segmentation fault']! { assert !output.contains(bad), output }
}
fn test_objc_rethrow() {
	$if macos {
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2); cpp := C.dlopen(c'/usr/lib/libc++.1.dylib', 2)
		assert objc != unsafe { nil } && cpp != unsafe { nil }
		assert C.dlsym(objc, c'objc_exception_rethrow') != unsafe { nil } && C.dlsym(cpp, c'__cxa_rethrow') != unsafe { nil }
		assert C.dlclose(objc) == 0 && C.dlclose(cpp) == 0
		println('NATIVE-OBJC-RETHROW: Objective-C and C++ exports present; native rethrowing and unwinding not invoked')
	}
	entry := rethrow_resolve()
	$if ios_cxx ? { assert entry == (cxx_symbol('___cxa_rethrow') or { panic(err) }) }
	$else { assert entry == u64(unsafe { voidptr(objc_rethrow_unavailable) }) }
	for symbol in ['objc_exception_rethrow', '_objc_exception_rethrowExtra', '___cxa_rethrow', '_objc_exception_throw', '_objc_begin_catch', '_objc_end_catch']! { if _ := objc_rethrow_symbol(symbol) { assert false } }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0)); shared := base + u64(page)
	assert code != u64(-1) && guard != u64(-1) && base != u64(-1)
	for i, op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 100)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { RethrowProbe(voidptr(code)) }; record := shared + 128
	mut expected := []u8{len: int(page)}
	for _ in 0 .. 2 {
		objc_start(); mut readers := []thread u64{}
		for _ in 0 .. 8 { readers << spawn rethrow_reader() }; for reader in readers { assert reader.wait() == entry }; unsafe { readers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libc++.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/swift/libswiftCore.dylib']! { if _ := runtime_symbol(library, '_objc_exception_rethrow') { assert false } }
		assert C.mprotect(voidptr(shared), page, C.PROT_READ | C.PROT_WRITE) == 0; C.memset(voidptr(shared), 0xa5, page)
		// A standard foreign unwind record, with prefix space for libc++abi's
		// imaginary header. Only begin-catch bookkeeping is used in children.
		unsafe { *(&u64(record)) = rethrow_foreign_class; *(&u64(record + 8)) = u64(voidptr(rethrow_cleanup)); *(&u64(record + 16)) = 0; *(&u64(record + 24)) = 0 }
		for i in 0 .. int(page) { expected[i] = unsafe { *(&u8(shared + u64(i))) } }
		for writable in [true, false]! {
			assert C.mprotect(voidptr(shared), page, C.PROT_READ | if writable { C.PROT_WRITE } else { 0 }) == 0
			for result in [shared, shared + u64(page) - 32]! { for pointer in [u64(0), 1, ~u64(0), guard, shared, shared + u64(page) - 32]! {
				rethrow_child(probe, entry, pointer, guard, result, record, false)
				$if ios_cxx ? { rethrow_child(probe, entry, pointer, guard, result, record, true) }
				for i in 0 .. int(page) { assert unsafe { *(&u8(shared + u64(i))) } == expected[i] }
			} }
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.ns_exception_type_arena == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixRethrowTeardown', 0)
		assert cls != 0 && objc_add_method(cls, u64(c'dealloc'), u64(unsafe { voidptr(rethrow_callback) }), c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := rethrow_callbacks
		objc_stop(); assert rethrow_callbacks == before + 1 && ios_runtime.live == 0 && rethrow_resolve() == entry
	}
	unsafe { expected.free() }; assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0 && C.munmap(voidptr(base), page * 3) == 0
	$if ios_cxx ? { println('IOS-OBJC-RETHROW: exact C++ backend alias, 96 terminal child calls with empty/foreign catch bookkeeping, protected unused arguments/stack/Self/x8 and unchanged writable/read-only pages at both boundaries, eight resolver readers, callback access and two drained runtimes; no exception reads, writes, cleanup or unwind result; actual rethrowing remains unsupported') }
	$else { println('IOS-OBJC-RETHROW: exact no-backend diagnostic, 48 terminal child calls with protected unused arguments/stack/Self/x8 and unchanged writable/read-only pages at both boundaries, eight resolver readers, callback access and two drained runtimes; no exception state or unwind result fabricated') }
}
