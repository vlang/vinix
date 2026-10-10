// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type IntegerPointerBits = fn (u64) i64
type IntegerContextCall = fn (u64, u64, &u64) i64

fn integer_worker(construct IntegerPointerBits, initial u64) {
	mut bits := initial
	for _ in 0 .. 4096 {
		bits ^= bits << 13
		bits ^= bits >> 7
		bits ^= bits << 17
		assert u64(construct(bits)) == bits
	}
}
fn integer_run(construct IntegerPointerBits) {
	assert construct(0) == 0 && construct(0xffffffffffffffff) == -1
	assert construct(0x7fffffffffffffff) == 9223372036854775807
	assert construct(0x8000000000000000) == i64(-9223372036854775807) - 1
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page) == 0 }
	base := u64(code)
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa0203f3, 0x58000134,
		0xaa0103f0, 0xd63f0200, 0xf9000274, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0,
		0xd503201f, 0xd503201f]! { write32(base + u64(i * 4), op) }
	unsafe { *(&u64(base + 48)) = 0xdeadbeefcafe1234 }
	C.__builtin___clear_cache(code, unsafe { voidptr(base + 56) })
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	call := unsafe { IntegerContextCall(code) }
	for bit in 0 .. 64 {
		for bits in [u64(1) << u32(bit), ~(u64(1) << u32(bit))]! {
			mut context := u64(0)
			assert u64(call(bits, u64(unsafe { voidptr(construct) }), &context)) == bits
			assert context == 0xdeadbeefcafe1234
		}
	}
	mut workers := []thread{}
	for i in 0 .. 8 { workers << spawn integer_worker(construct, 0xdefa000000000001 + u64(i)) }
	workers.wait()
}
fn test_swift_integer_pointer_bit_pattern() {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		construct := unsafe { IntegerPointerBits(C.dlsym(lib, c'$sSi10bitPatternSis13OpaquePointerVSg_tcfC')) }
		integer_run(construct)
		println('IOS-SWIFT-INTEGER-NATIVE: nil/signed boundaries, every single/complemented bit, preserved Swift context and 32768 concurrent bit patterns')
	}
	for _ in 0 .. 2 {
		objc_start()
		construct := unsafe { IntegerPointerBits(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSi10bitPatternSis13OpaquePointerVSg_tcfC') or { panic(err) })) }
		integer_run(construct)
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_array_metadata.len == 0
		assert ios_runtime.swift_array_arena == 0 && ios_runtime.swift_metadata_arena == 0
		assert ios_runtime.swift_hash_code == 0 && ios_runtime.swift_arc_code == 0
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
		objc_stop()
	}
	println('IOS-SWIFT-INTEGER: exact 64-bit Optional<OpaquePointer> to signed Int conversion without pointer access or ownership, preserved context, concurrent calls and two empty teardowns')
}
