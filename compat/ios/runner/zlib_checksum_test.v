// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type AdlerCall = fn (u64, &u8, u32) u64

// Independent per-byte reduction avoids the implementation's block algorithm.
fn adler_reference(seed u64, bytes &u8, count u32) u64 {
	mut a := (seed & 0xffff) % 65521
	mut b := ((seed >> 16) & 0xffff) % 65521
	for i in 0 .. u64(count) {
		a = (a + unsafe { bytes[i] }) % 65521
		b = (b + a) % 65521
	}
	return (b << 16) | a
}

fn adler_cases(call AdlerCall) {
	page := u64(C.getpagesize())
	capacity := page * 256
	region := u64(C.mmap(unsafe { nil }, usize(capacity + page * 2), C.PROT_NONE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region + page) }, usize(capacity), C.PROT_READ | C.PROT_WRITE) == 0
	end := region + page + capacity
	for pattern in 0 .. 3 {
		for i in 0 .. capacity {
			unsafe { *(&u8(region + page + i)) = if pattern == 0 { u8(0) } else if pattern == 1 { u8(255) } else { u8(i * 73 + i / 251) } }
		}
		assert C.mprotect(unsafe { voidptr(region + page) }, usize(capacity), C.PROT_READ) == 0
		for seed in [u64(0), 1, 0xffffffff, ~u64(0), 0xffff, 0xffff0000,
			0x123456789abcdef0, 0x8000000000000001]! {
			for count in [u32(0), 1, 2, 15, 16, 17, 31, 32, 63, 64, 255, 256,
				5551, 5552, 5553, 11103, 11104, 11105, 65520, 65521, 65535, 65536, 1048576]! {
				assert u64(count) <= capacity
				bytes := unsafe { &u8(end - count) }
				expected := adler_reference(seed, bytes, count)
				darwin_set_errno(13)
				assert call(seed, bytes, count) == expected
				assert unsafe { *C.ios_errno_address() } == 13
				assert zlib_adler32(seed, bytes, count) == expected
			}
			// Native zlib's one-byte fast path dereferences a null buffer. Avoid
			// invoking that invalid read; the V entry safely handles it below.
			for count in [u32(0), 2, 5552, 0xffffffff]! {
				assert call(seed, unsafe { nil }, count) == 1
				assert zlib_adler32(seed, unsafe { nil }, count) == 1
			}
			assert zlib_adler32(seed, unsafe { nil }, 1) == 1
		}
		// Arbitrarily partitioned updates must reproduce one whole-buffer call.
		bytes := unsafe { &u8(end - 65536) }
		mut sum := u64(1)
		mut offset := u32(0)
		for offset < 65536 {
			count := if 65536 - offset > 997 { u32(997) } else { 65536 - offset }
			sum = call(sum, unsafe { bytes + offset }, count)
			offset += count
		}
		assert sum == adler_reference(1, bytes, 65536)
		assert C.mprotect(unsafe { voidptr(region + page) }, usize(capacity), C.PROT_READ | C.PROT_WRITE) == 0
	}
	assert C.munmap(unsafe { voidptr(region) }, usize(capacity + page * 2)) == 0
	assert call(1, c'Wikipedia', 9) == 0x11e60398
	assert call(1, c'123456789', 9) == 0x091e01de
}

fn adler_worker(call AdlerCall) {
	for _ in 0 .. 1000 { assert call(1, c'Fortnite', 8) == adler_reference(1, c'Fortnite', 8) }
}

fn test_zlib_checksum() {
	$if macos {
		handle := C.dlopen(c'/usr/lib/libz.1.dylib', 2)
		assert handle != unsafe { nil }
		entry := C.dlsym(handle, c'adler32')
		assert entry != unsafe { nil }
		adler_cases(unsafe { AdlerCall(entry) })
		assert C.dlclose(handle) == 0
		println('IOS-ZLIB-CHECKSUM-NATIVE: installed adler32 matches V/reference for guarded zero/unaligned buffers, three byte patterns, arbitrary 64-bit seeds, null buffers, boundary lengths through 1MiB, incremental updates and unchanged errno')
	}
	objc_start()
	entry := runtime_symbol('/usr/lib/libz.1.dylib', '_adler32') or { panic(err) }
	assert entry == u64(unsafe { voidptr(zlib_adler32) })
	if _ := zlib_checksum_symbol('_adler32_z') { assert false }
	for library in ['/usr/lib/libSystem.B.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation',
		'/System/Library/Frameworks/StoreKit.framework/StoreKit']! {
		if _ := runtime_symbol(library, '_adler32') { assert false }
	}
	call := unsafe { AdlerCall(voidptr(entry)) }
	adler_cases(call)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn adler_worker(call) }
	for worker in workers { worker.wait() }
	unsafe { workers.free() }
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	objc_stop()
	assert call(1, c'Wikipedia', 9) == 0x11e60398
	println('IOS-ZLIB-CHECKSUM: scoped Adler-32 C ABI in V, guarded/read-only inputs, reset and seed semantics, independent/native vectors, incremental and concurrent callers, no runtime storage')
}
