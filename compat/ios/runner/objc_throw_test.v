// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type ThrowProbe = fn (&u64, u64, &u64)
fn throw_resolve() u64 { return runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_exception_throw') or { panic(err) } }
fn throw_reader() u64 {
	entry := throw_resolve(); for _ in 0 .. 1024 { assert throw_resolve() == entry }; return entry
}
__global throw_in_child = false
__global throw_destroyed = 0
__global throw_callbacks = 0
fn throw_object_dealloc(object u64, selector u64) { if throw_in_child { C._exit(87) }; throw_destroyed++ }
fn throw_uncaught(object u64) { C._exit(88) }
fn throw_callback(object u64, selector u64) { assert throw_resolve() == u64(unsafe { voidptr(objc_throw_unavailable) }); throw_callbacks++ }
fn throw_child(probe ThrowProbe, entry u64, object u64, guard u64, result u64) {
	mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
	child := C.ios_fork(); assert child >= 0
	if child == 0 {
		throw_in_child = true
		C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
		input := [object, guard, guard, guard, guard, guard, guard, guard, guard, guard, result, guard, guard]!
		mut output := [6]u64{}; probe(unsafe { &input[0] }, entry, unsafe { &output[0] }); C._exit(0)
	}
	C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
	for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
	C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(child, &status, 0) == child && status == 256
	output := unsafe { tos(&bytes[0], length) }
	assert output.contains('iOS: Objective-C exception throwing through Mach-O frames is not implemented') && !output.contains('iOS: C++ exception unwinding'), output
	for bad in ['runtime error:', 'AddressSanitizer', 'SIGSEGV', 'SIGBUS', 'Segmentation fault']! { assert !output.contains(bad), output }
}
fn test_objc_throw() {
	$if macos {
		library := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2); assert library != unsafe { nil }
		assert C.dlsym(library, c'objc_exception_throw') != unsafe { nil }; assert C.dlclose(library) == 0
		println('NATIVE-OBJC-THROW: libobjc export present; native throwing and unwinding not invoked')
	}
	entry := throw_resolve(); assert entry == u64(unsafe { voidptr(objc_throw_unavailable) })
	$if ios_cxx ? { assert entry != (cxx_symbol('___cxa_throw') or { panic(err) }) }
	for symbol in ['objc_exception_throw', '_objc_exception_throwExtra', '_objc_exception_throw_v0']! { if _ := objc_runtime_symbol(symbol) { assert false } }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0)); shared := base + u64(page)
	assert code != u64(-1) && guard != u64(-1) && base != u64(-1)
	for i, op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 100)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { ThrowProbe(voidptr(code)) }
	for _ in 0 .. 2 {
		objc_start(); mut readers := []thread u64{}
		for _ in 0 .. 8 { readers << spawn throw_reader() }; for reader in readers { assert reader.wait() == entry }; unsafe { readers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libc++.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/swift/libswiftCore.dylib']! { if _ := runtime_symbol(library, '_objc_exception_throw') { assert false } }
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixThrowObject', 0)
		assert cls != 0 && objc_add_method(cls, u64(c'dealloc'), u64(unsafe { voidptr(throw_object_dealloc) }), c'v16@0:8'); objc_register_class(cls)
		object := objc_new(cls); before_destroyed := throw_destroyed
		for handler in [u64(0), u64(unsafe { voidptr(throw_uncaught) }), guard]! {
			ns_set_uncaught_handler(handler)
			assert C.mprotect(voidptr(shared), page, C.PROT_READ | C.PROT_WRITE) == 0; C.memset(voidptr(shared), 0xa5, page)
			for writable in [true, false]! {
				assert C.mprotect(voidptr(shared), page, C.PROT_READ | if writable { C.PROT_WRITE } else { 0 }) == 0
				for result in [shared, shared + u64(page) - 32]! { for value in [u64(0), 1, ~u64(0), guard, shared, shared + u64(page) - 32, object, cls]! {
					throw_child(probe, entry, value, guard, result)
					for i in u64(0) .. u64(page) { assert unsafe { *(&u8(shared + i)) } == 0xa5 }
					assert ns_get_uncaught_handler() == handler && obj_header(object).refs == 1 && throw_destroyed == before_destroyed
				} }
			}
		}
		ns_set_uncaught_handler(0); objc_release(object); assert throw_destroyed == before_destroyed + 1
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.ns_exception_type_arena == 0
		callback_cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixThrowTeardown', 0)
		assert callback_cls != 0 && objc_add_method(callback_cls, u64(c'dealloc'), u64(unsafe { voidptr(throw_callback) }), c'v16@0:8')
		objc_register_class(callback_cls); objc_autorelease(objc_new(callback_cls)); before := throw_callbacks
		objc_stop(); assert throw_callbacks == before + 1 && ios_runtime.live == 0 && throw_resolve() == entry && ios_runtime.uncaught_exception_handler == 0
	}
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0 && C.munmap(voidptr(base), page * 3) == 0
	println('IOS-OBJC-THROW: exact Objective-C terminal diagnostic in either backend configuration, 192 child calls with null/invalid/protected/managed/class objects and nil/trapping/protected uncaught handlers, protected unused registers/stack/Self/x8, unchanged writable/read-only pages at both guard boundaries, eight resolver readers, callback access and two drained runtimes; no object reads, ownership, handler calls, exception record or unwind result; actual throwing remains unsupported')
}
