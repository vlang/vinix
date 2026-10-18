// SPDX-License-Identifier: GPL-2.0-or-later
module main

import compress.deflate

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type ZCCompress = fn (&u8, &u64, &u8, u64, i32) i32
type ZCBound = fn (u64) u64
type ZCInflate = fn (&u8, &u64, &u8, u64) i32
struct ZCApi { pack ZCCompress bound ZCBound inflate ZCInflate = unsafe { nil } }

fn zc_decode(api ZCApi, encoded &u8, length u64, source &u8, count u64) {
	data := unsafe { encoded.vbytes(int(length)) }
	decoded := deflate.decompress_zlib(data) or { panic(err) }
	assert u64(decoded.len) == count
	if count != 0 { assert C.memcmp(decoded.data, source, usize(count)) == 0 }
	unsafe { decoded.free() }
	if api.inflate != unsafe { nil } {
		storage := C.malloc(usize(count + 1))
		assert storage != unsafe { nil }
		mut size := count + 1
		assert api.inflate(unsafe { &u8(storage) }, unsafe { &size }, encoded, length) == 0
		assert size == count
		if count != 0 { assert C.memcmp(storage, source, usize(count)) == 0 }
		C.free(storage)
	}
}

fn zc_case(api ZCApi, source &u8, count u64, level i32, capacity u64, must_fit bool) {
	page := u64(C.getpagesize())
	allocated := ((capacity + page - 1) / page + 1) * page
	region := u64(C.mmap(unsafe { nil }, usize(allocated + page * 2), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region + page) }, usize(allocated), C.PROT_READ | C.PROT_WRITE) == 0
	unsafe { C.memset(voidptr(region + page), 0xa5, usize(allocated)) }
	output := unsafe { &u8(region + page + allocated - capacity) }
	// uLongf is an aligned 64-bit cell, with canaries on both sides.
	mut length_cell := [u64(0xa5a5a5a5a5a5a5a5), capacity, 0xa5a5a5a5a5a5a5a5]!
	length_pointer := unsafe { &length_cell[1] }
	darwin_set_errno(13)
	status := api.pack(output, length_pointer, source, count, level)
	assert unsafe { *C.ios_errno_address() } == 13
	length := length_cell[1]
	assert length_cell[0] == 0xa5a5a5a5a5a5a5a5 && length_cell[2] == 0xa5a5a5a5a5a5a5a5
	assert length <= capacity
	assert unsafe { *(output - 1) } == 0xa5
	if must_fit { assert status == 0, 'compressBound must accommodate every valid level' }
	if status == 0 {
		assert length >= 8
		assert unsafe { output[0] } == 0x78
		normalized := if level == -1 { i32(6) } else { level }
		expected_header := if normalized <= 1 { u8(0x01) } else if normalized <= 5 { u8(0x5e) } else if normalized == 6 { u8(0x9c) } else { u8(0xda) }
		assert unsafe { output[1] } == expected_header
		zc_decode(api, output, length, source, count)
		if normalized > 0 && count >= 8192 {
			// Repeated bytes must actually compress, including history wraps.
			if unsafe { source[0] == source[1] && source[0] == source[4096] } { assert length < count / 4 }
		}
	} else {
		assert status == -5 && length == capacity
	}
	assert C.munmap(unsafe { voidptr(region) }, usize(allocated + page * 2)) == 0
}

fn zc_errors(api ZCApi) {
	mut output := [32]u8{}
	for level in [i32(-2), -1, 0, 9, 10]! {
		for count in [u64(0), 1, ~u64(0)]! {
			for capacity in [u64(0), 32]! {
				for null_output in [false, true]! {
					unsafe { C.memset(&output[0], 0xa5, 32) }
					mut length := capacity
					status := api.pack(if null_output { unsafe { nil } } else { unsafe { &output[0] } }, unsafe { &length }, unsafe { nil }, count, level)
					if level < -1 || level > 9 || null_output || count != 0 {
						assert status == -2 && length == 0
						for byte in output { assert byte == 0xa5 }
					} else if capacity == 0 { assert status == -5 && length == 0 }
					else { assert status == 0; zc_decode(api, unsafe { &output[0] }, length, unsafe { nil }, 0) }
				}
			}
		}
	}
	// An unsigned-long output capacity must not truncate to 32 bits.
	for capacity in [u64(0x100000000), 0x100000001, ~u64(0)]! {
		mut length := capacity
		assert api.pack(unsafe { &output[0] }, unsafe { &length }, unsafe { nil }, 0, 6) == 0
		assert length == 8
	}
}

fn zc_suite(api ZCApi) {
	for count in [u64(0), 1, 4095, 4096, 65535, 65536, 0xffffffff, 0x100000000,
		0x100000001, 0x7fffffffffffffff, ~u64(0)]! {
		assert api.bound(count) == zlib_compress_bound(count)
	}
	assert api.bound(0) == 13 && api.bound(0x100000000) == 0x10014008d
	assert api.bound(~u64(0)) == 0x14008000000009
	zc_errors(api)
	page := u64(C.getpagesize())
	capacity := page * 64
	region := u64(C.mmap(unsafe { nil }, usize(capacity + page * 2), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region + page) }, usize(capacity), C.PROT_READ | C.PROT_WRITE) == 0
	end := region + page + capacity
	for pattern in 0 .. 4 {
		mut random := u32(0x7a31c295)
		for i in 0 .. capacity {
			random ^= random << 13; random ^= random >> 17; random ^= random << 5
			unsafe { *(&u8(region + page + i)) = if pattern == 0 { u8(65) } else if pattern == 1 { u8(i % 251) }
				else if pattern == 3 && i >= 32768 { *(&u8(region + page + i - 32768)) } else { u8(random) } }
		}
		assert C.mprotect(unsafe { voidptr(region + page) }, usize(capacity), C.PROT_READ) == 0
		for count in [u64(0), 1, 2, 3, 257, 258, 259, 32767, 32768, 32769, 65534, 65535, 65536, 131071]! {
			source := unsafe { &u8(end - count) }
			for level in [i32(-1), 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]! { zc_case(api, source, count, level, api.bound(count), true) }
		}
		for count in [u64(0), 257, 65536]! {
			for cap in [u64(0), 1, 2, 3, 7, 8, 11, 31, 128]! {
				for level in [i32(0), 6, 9]! { zc_case(api, unsafe { &u8(end - count) }, count, level, cap, false) }
			}
		}
		assert C.mprotect(unsafe { voidptr(region + page) }, usize(capacity), C.PROT_READ | C.PROT_WRITE) == 0
	}
	assert C.munmap(unsafe { voidptr(region) }, usize(capacity + page * 2)) == 0
}

fn zc_worker(api ZCApi) {
	mut input := [8192]u8{}
	for i in 0 .. input.len { input[i] = u8(i % 7) }
	for _ in 0 .. 16 { zc_case(api, unsafe { &input[0] }, u64(input.len), 9, api.bound(u64(input.len)), true) }
}

fn test_zlib_compress() {
	$if macos {
		handle := C.dlopen(c'/usr/lib/libz.1.dylib', 2)
		assert handle != unsafe { nil }
		api := ZCApi{unsafe { ZCCompress(C.dlsym(handle, c'compress2')) }, unsafe { ZCBound(C.dlsym(handle, c'compressBound')) }, unsafe { ZCInflate(C.dlsym(handle, c'uncompress')) }}
		zc_suite(api)
		// Also decode the V encoder's actual output with native zlib.
		zc_suite(ZCApi{zlib_compress2, zlib_compress_bound, api.inflate})
		assert C.dlclose(handle) == 0
		println('IOS-ZLIB-COMPRESS-NATIVE: native capacity/error/header and 64-bit bound comparison; independent and native decoders accept V output across levels, patterns, guarded buffers and window/block boundaries')
	}
	objc_start()
	for symbol in ['_compress2', '_compressBound']! {
		assert runtime_symbol('/usr/lib/libz.1.dylib', symbol) or { panic(err) } != 0
		for library in ['/usr/lib/libSystem.B.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
			if _ := runtime_symbol(library, symbol) { assert false }
		}
	}
	if _ := zlib_compress_symbol('_deflate') { assert false }
	pack_entry := runtime_symbol('/usr/lib/libz.1.dylib', '_compress2') or { panic(err) }
	bound_entry := runtime_symbol('/usr/lib/libz.1.dylib', '_compressBound') or { panic(err) }
	assert pack_entry == u64(unsafe { voidptr(zlib_compress2) }) && bound_entry == u64(unsafe { voidptr(zlib_compress_bound) })
	assert zlib_compress2(unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, 6) == -2
	api := ZCApi{unsafe { ZCCompress(voidptr(pack_entry)) }, unsafe { ZCBound(voidptr(bound_entry)) }, unsafe { nil }}
	zc_suite(api)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn zc_worker(api) }
	for worker in workers { worker.wait() }
	unsafe { workers.free() }
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	objc_stop()
	println('IOS-ZLIB-COMPRESS: scoped C ABI, bounded LZ77/fixed Huffman and stored fallback, all levels, 64-bit lengths, guarded buffers, buffer errors, real compression and eight workers; owned history freed on every path')
}
