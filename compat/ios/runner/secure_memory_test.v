// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <dlfcn.h>
}
fn C.dlsym(voidptr, &char) voidptr
type SecureMemSet = fn (voidptr, usize, i32, usize) i32

fn secure_memory_cases(set SecureMemSet) {
	limit := usize(u64(-1) >> 1)
	for maximum in [usize(0), 1, 8, 16, limit, limit + 1, usize(-1)]! {
		for count in [usize(0), 1, 8, 16, limit, limit + 1, usize(-1)]! {
			if maximum == limit && count > 16 { continue }
			for null_pointer in [false, true]! {
				for fill in [i32(-1), 0, 0x12340080]! {
					mut bytes := [32]u8{}
					C.memset(unsafe { &bytes[0] }, 0xa5, 32)
					darwin_set_errno(13)
					result := set(if null_pointer { unsafe { nil } } else { unsafe { voidptr(&bytes[8]) } }, maximum, fill, count)
					assert unsafe { *C.ios_errno_address() } == 13
					expected := if null_pointer { i32(22) } else if maximum > limit || count > limit { i32(7) } else if count > maximum { i32(84) } else { i32(0) }
					assert result == expected
					written := if null_pointer || maximum > limit { usize(0) } else if count < maximum { count } else { maximum }
					for i in 0 .. 32 { assert bytes[i] == if usize(i) >= 8 && usize(i) - 8 < written { u8(fill) } else { u8(0xa5) } }
				}
			}
		}
	}
}

fn test_secure_memory_native() {
	$if macos {
		entry := C.dlsym(unsafe { voidptr(-2) }, c'memset_s'); assert entry != unsafe { nil }
		secure_memory_cases(unsafe { SecureMemSet(entry) })
		println('IOS-MEMSET-NATIVE: installed memset_s matches null precedence, RSIZE_MAX, E2BIG7, EOVERFLOW84, bounded writes on oversize requests, three fill bytes and unchanged errno')
	}
}

fn test_secure_memory_runtime() {
	entry := libsystem_symbol('/usr/lib/libSystem.B.dylib', '_memset_s') or { panic(err) }
	assert entry == u64(unsafe { voidptr(darwin_memset_s) })
	set := unsafe { SecureMemSet(voidptr(entry)) }
	secure_memory_cases(set)
	if _ := libsystem_symbol('/usr/lib/libobjc.A.dylib', '_memset_s') { assert false }
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, usize(page * 3), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region + page) }, usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	start := region + page; end := start + page - 16
	for address in [start, end]! {
		C.memset(unsafe { voidptr(address) }, 0xa5, 16)
		assert set(unsafe { voidptr(address) }, 16, -1, usize(-1)) == 7
		for i in 0 .. 16 { assert unsafe { *(&u8(address + u64(i))) } == 0xff }
		assert set(unsafe { voidptr(address) }, 16, 0, 17) == 84
		for i in 0 .. 16 { assert unsafe { *(&u8(address + u64(i))) } == 0 }
	}
	// Invalid maximum and zero-length calls must not touch a protected pointer.
	assert set(unsafe { voidptr(region) }, usize(-1), 0, 16) == 7
	assert set(unsafe { voidptr(region) }, 0, 0, 0) == 0
	assert C.munmap(unsafe { voidptr(region) }, usize(page * 3)) == 0
	println('IOS-MEMSET: fixed four-argument ABI, native error/write matrix, zero/null and unsigned fill behavior, protected pointers and guard-adjacent bounded overwrites; no owner or scratch allocation')
}
