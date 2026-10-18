// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type ZBBound = fn (voidptr, u64) u64
type ZBInit = fn (voidptr, i32, i32, i32, i32, i32, &char, i32) i32
type ZBEnd = fn (voidptr) i32
type ZBRun = fn (voidptr, i32) i32
type ZBHeader = fn (voidptr, voidptr) i32
type ZBDictionary = fn (voidptr, &u8, u32) i32
type ZBVersion = fn () &char
type ZBInflateInit = fn (voidptr, i32, &char, i32) i32

fn zb_store64(address u64, value u64) { unsafe { *(&u64(address)) = value } }

fn zb_compare(bound ZBBound, stream voidptr, count u64) {
	darwin_set_errno(13)
	actual := zlib_deflate_bound(stream, count)
	assert unsafe { *C.ios_errno_address() } == 13
	if bound != unsafe { nil } {
		native := bound(stream, count)
		if actual != native {
			// Deliberately loosen Darwin's underestimated dictionary bound.
			address := u64(stream); assert address != 0
			state := read64(address + 56); assert state != 0 && read64(state) == address
			assert read32(state + 8) in [u32(42), 57, 69, 73, 91, 103, 113, 666]!
			wrap := read32(state + 48)
			assert wrap in [u32(0), 1]! && read32(state + 172) != 0
			assert read32(state + 84) == 15 && read32(state + 136) == 15
			assert actual == count + ((count + 7) >> 3) + ((count + 63) >> 6) + 5 + if wrap == 1 { u64(10) } else { u64(0) }
			assert actual > native
		}
	}
}

fn zb_synthetic(bound ZBBound) {
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, usize(page * 6), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	for index in [u64(0), 2, 4]! { assert C.mprotect(unsafe { voidptr(region + index * page) }, usize(page), C.PROT_READ | C.PROT_WRITE) == 0 }
	stream := region + page - 112
	state := region + page * 3 - 176
	header := region + page * 5 - 80
	// Each ABI object ends immediately before a guard page.
	zb_store64(stream + 56, state); zb_store64(stream + 64, 1); zb_store64(stream + 72, 1)
	zb_store64(state, stream); write32(state + 8, 42)
	write32(state + 84, 15); write32(state + 136, 15)
	for status in [u32(0), 42, 57, 69, 73, 91, 103, 113, 666, 667, 0xffffffff]! {
		write32(state + 8, status)
		for wrap in [u32(0), 1, 2, 3, 0xffffffff]! {
			write32(state + 48, wrap)
			for customized in [false, true]! {
				zb_store64(state + 56, if customized { header } else { u64(0) })
				zb_store64(header + 24, if customized { u64(c'extra') } else { u64(0) }); write32(header + 32, 5)
				zb_store64(header + 40, u64(c'name')); zb_store64(header + 56, u64(c'comment')); write32(header + 68, 1)
				for window in [u32(9), 15]! { for hash in [u32(8), 15, 16]! { for dictionary in [u32(0), 1, 32768]! {
					write32(state + 84, window); write32(state + 136, hash); write32(state + 172, dictionary)
					for index in [u64(0), 2, 4]! { assert C.mprotect(unsafe { voidptr(region + index * page) }, usize(page), C.PROT_READ) == 0 }
					for count in [u64(0), 1, 7, 8, 63, 64, 4095, 4096, 65535, 65536, 0xffffffff, 0x100000000, 0x7fffffffffffffff, ~u64(0) - 63, ~u64(0) - 7, ~u64(0)]! {
						zb_compare(bound, unsafe { voidptr(stream) }, count)
						zb_compare(bound, unsafe { nil }, count)
					}
					for index in [u64(0), 2, 4]! { assert C.mprotect(unsafe { voidptr(region + index * page) }, usize(page), C.PROT_READ | C.PROT_WRITE) == 0 }
				}}}
			}
		}
	}
	// Reject incomplete and foreign state before reading the private prefix.
	for offset in [u64(56), 64, 72]! {
		saved := read64(stream + offset); zb_store64(stream + offset, 0)
		assert zlib_deflate_bound(unsafe { voidptr(stream) }, 0) == 11
		zb_compare(bound, unsafe { voidptr(stream) }, 0); zb_store64(stream + offset, saved)
	}
	zb_store64(state, 0); zb_compare(bound, unsafe { voidptr(stream) }, 1000)
	assert zlib_deflate_bound(unsafe { nil }, 0) == 11
	assert zlib_deflate_bound(unsafe { nil }, 1) == 14
	assert zlib_deflate_bound(unsafe { nil }, 0x100000000) == 0x12400000b
	assert C.munmap(unsafe { voidptr(region) }, usize(page * 6)) == 0
}

fn zb_native(handle voidptr, exact bool) {
	bound := unsafe { ZBBound(C.dlsym(handle, c'deflateBound')) }
	init := unsafe { ZBInit(C.dlsym(handle, c'deflateInit2_')) }
	end := unsafe { ZBEnd(C.dlsym(handle, c'deflateEnd')) }
	run := unsafe { ZBRun(C.dlsym(handle, c'deflate')) }
	reset := unsafe { ZBEnd(C.dlsym(handle, c'deflateReset')) }
	set_header := unsafe { ZBHeader(C.dlsym(handle, c'deflateSetHeader')) }
	set_dictionary := unsafe { ZBDictionary(C.dlsym(handle, c'deflateSetDictionary')) }
	version := unsafe { ZBVersion(C.dlsym(handle, c'zlibVersion'))() }
	inflate_init := unsafe { ZBInflateInit(C.dlsym(handle, c'inflateInit2_')) }
	inflate := unsafe { ZBRun(C.dlsym(handle, c'inflate')) }
	inflate_end := unsafe { ZBEnd(C.dlsym(handle, c'inflateEnd')) }
	assert bound != unsafe { nil } && init != unsafe { nil } && end != unsafe { nil }
	println('IOS-ZLIB-BOUND-NATIVE: zlib '+unsafe { version.vstring() })
	if exact { zb_synthetic(bound) }
	mut input := [65536]u8{}
	mut random := u32(0x4fd3021a)
	for i in 0 .. input.len { random ^= random << 13; random ^= random >> 17; random ^= random << 5; input[i] = u8(random) }
	for window in [i32(-15), 9, 15, 25, 31]! { for memory in [i32(1), 2, 8, 9]! { for level in [i32(0), 1, 6, 9]! { for strategy in [i32(0), 2, 4]! {
		mut stream := [14]u64{}
		address := u64(unsafe { &stream[0] })
		assert init(unsafe { voidptr(address) }, level, 8, window, memory, strategy, version, 112) == 0
		state := stream[7]
		assert state != 0 && read64(state) == address
		assert read32(state + 84) == u32(if window < 0 { -window } else if window > 15 { window - 16 } else { window })
		assert read32(state + 136) == u32(memory + 7)
		for custom in [false, true]! {
			assert reset(unsafe { voidptr(address) }) == 0
			mut header := [10]u64{}
			if custom {
				if window > 15 {
					header[3] = u64(c'extra'); header[4] = 5; header[5] = u64(c'fixture.bin'); header[7] = u64(c'Vinix header');
					write32(u64(unsafe { &header[0] }) + 68, 1)
					assert set_header(unsafe { voidptr(address) }, unsafe { &header[0] }) == 0
				} else { assert set_dictionary(unsafe { voidptr(address) }, unsafe { &input[0] }, 257) == 0 }
			}
			for count in [u64(0), 1, 63, 4096, 65536, 0x100000000, ~u64(0)]! {
				if exact { zb_compare(bound, unsafe { voidptr(address) }, count) }
				// Newer zlib uses different conservative constants for tiny inputs.
				else if count >= 63 && count <= 65536 { assert zlib_deflate_bound(unsafe { voidptr(address) }, count) >= bound(unsafe { voidptr(address) }, count) }
			}
			capacity := zlib_deflate_bound(unsafe { voidptr(address) }, u64(input.len))
			page := u64(C.getpagesize()); pages := (capacity + page - 1) / page
			region := u64(C.mmap(unsafe { nil }, usize((pages + 2) * page), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
			assert region != u64(-1)
			assert C.mprotect(unsafe { voidptr(region + page) }, usize(pages * page), C.PROT_READ | C.PROT_WRITE) == 0
			output := region + (pages + 1) * page - capacity
			unsafe { *(&u8(output - 1)) = 0xa5 }
			stream[0] = u64(unsafe { &input[0] }); write32(address + 8, u32(input.len))
			stream[3] = output; write32(address + 32, u32(capacity))
			status := run(unsafe { voidptr(address) }, 4)
			assert status == 1, 'window=${window} memory=${memory} level=${level} strategy=${strategy} custom=${custom} capacity=${capacity} written=${stream[5]} input_left=${read32(address + 8)} output_left=${read32(address + 32)}'
			assert stream[5] <= capacity && unsafe { *(&u8(output - 1)) } == 0xa5
			if exact { zb_compare(bound, unsafe { voidptr(address) }, 65536) }
			// Independently consume every byte of wrapper/header/trailer through
			// the backend inflater. Dictionary streams need a matching dictionary;
			// their bound is checked above, and their compression must still finish.
			if !custom || window > 15 {
				mut decoded := [65537]u8{}; mut reader := [14]u64{}
				raddr := u64(unsafe { &reader[0] })
				assert inflate_init(unsafe { voidptr(raddr) }, window, version, 112) == 0
				reader[0] = output; write32(raddr + 8, u32(stream[5])); reader[3] = u64(unsafe { &decoded[0] }); write32(raddr + 32, u32(decoded.len))
				assert inflate(unsafe { voidptr(raddr) }, 4) == 1
				assert reader[5] == u64(input.len) && C.memcmp(unsafe { &decoded[0] }, unsafe { &input[0] }, input.len) == 0
				assert inflate_end(unsafe { voidptr(raddr) }) == 0
			}
			assert C.munmap(unsafe { voidptr(region) }, usize((pages + 2) * page)) == 0
		}
		assert end(unsafe { voidptr(address) }) == 0
		assert stream[7] == 0
	}}}}
	println('Native deflateBound stream, wrapper, dictionary and overflow behavior inspected')
}

fn zb_worker() { for _ in 0 .. 10000 { assert zlib_deflate_bound(unsafe { nil }, 65536) == 74763 } }

fn test_zlib_bound() {
	$if macos {
		handle := C.dlopen(c'/usr/lib/libz.1.dylib', 2); assert handle != unsafe { nil }
		zb_native(handle, true); assert C.dlclose(handle) == 0
	}
	$if ios_gles ? {
		handle := C.dlopen(c'libz.so.1', 2); assert handle != unsafe { nil }
		zb_native(handle, false); assert C.dlclose(handle) == 0
	}
	zb_synthetic(unsafe { nil })
	objc_start()
	$if ios_text ? { text_start() or { panic(err) } }
	$if ios_gles ? { gles_start() or { panic(err) } }
	entry := runtime_symbol('/usr/lib/libz.1.dylib', '_deflateBound') or { panic(err) }
	assert entry == u64(unsafe { voidptr(zlib_deflate_bound) })
	for library in ['/usr/lib/libSystem.B.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! { if _ := runtime_symbol(library, '_deflateBound') { assert false } }
	if _ := zlib_bound_symbol('_deflate') { assert false }
	assert unsafe { ZBBound(voidptr(entry)) }(unsafe { nil }, 0) == 11
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn zb_worker() }; workers.wait()
	unsafe { workers.free() }
	objc_stop()
	$if ios_gles ? { gles_stop() }
	println('IOS-ZLIB-BOUND: scoped C ABI, guarded read-only stream/state/header, native initialized streams, raw/zlib/gzip, custom headers and dictionaries, memory levels and strategies, exact-capacity finish, overflow and concurrent callers')
}
