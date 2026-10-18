// SPDX-License-Identifier: GPL-2.0-or-later
module main

type AdviceCall = fn (voidptr, usize, i32) i32

fn advice_call(native bool, address u64, size u64, advice i32) i32 {
	$if macos { if native { return C.madvise(voidptr(address), usize(size), advice) } }
	call := unsafe { AdviceCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_madvise') or { panic(err) })) }
	return call(voidptr(address), usize(size), advice)
}

fn advice_result(native bool, address u64, size u64, advice i32, expected i32) {
	darwin_set_errno(83)
	result := advice_call(native, address, size, advice)
	value := unsafe { *C.ios_errno_address() }
	assert result == if expected == 0 { 0 } else { -1 }, 'advice ${advice} result ${result} errno ${value}'
	assert value == if expected == 0 { 83 } else { expected }, 'advice ${advice} errno ${value} expected ${expected}'
}

fn advice_profile(native bool) {
	page := mach_page_size()
	for advice in [i32(0), 1, 2, 3, 4, 5, 7, 8]! {
		base := u64(darwin_mmap(unsafe { nil }, usize(page * 5), 3, 0x1002, -1, 0))
		assert base != ~u64(0)
		for delta in [u64(0), 1, page - 1, page, page + 1]! {
			for length in [u64(0), 1, page, page + 1]! {
				unsafe { C.memset(voidptr(base), 0x5a, usize(page * 5)) }
				advice_result(native, base + page + delta, length, advice, 0)
				// All changed pages must lie within the rounded requested range.
				assert unsafe { *(&u8(base)) } == 0x5a
				assert unsafe { *(&u8(base + page * 5 - 1)) } == 0x5a
				if advice !in [i32(5), 7] || length == 0 {
					for i in u64(0) .. page * 5 { assert unsafe { *(&u8(base + i)) } == 0x5a }
				} else {
					advice_result(native, base + page + delta, length, 8, 0)
					unsafe { C.memset(voidptr(base + page + delta), 0x73, usize(length)) }
					for hint in [i32(0), 4, 8]! { advice_result(native, base + page + delta, length, hint, 0) }
					for i in u64(0) .. length { assert unsafe { *(&u8(base + page + delta + i)) } == 0x73 }
					$if linux {
						// Eager release must actually discard the entire rounded span.
						low := (base + page + delta) & ~(page - 1)
						advice_result(native, low, page, advice, 0)
						for i in u64(0) .. page { assert unsafe { *(&u8(low + i)) } == 0 }
					}
				}
			}
		}
		for address in [u64(0), page, ~u64(0)]! { advice_result(native, address, 0, advice, 0) }
		for address in [base, ~u64(0)]! { advice_result(native, address, ~u64(0), advice, 22) }
		for bad in [i32(-1), 99, 0x7fffffff]! { advice_result(native, base, page, bad, 22); advice_result(native, 0, 0, bad, 22) }
		assert darwin_munmap(voidptr(base + page * 2), usize(page)) == 0
		unsafe { *(&u8(base + page)) = 0x7c; *(&u8(base + page * 3)) = 0x7d }
		advice_result(native, base + page * 2, page, advice, 22)
		advice_result(native, base + page, page * 3, advice, 22)
		assert unsafe { *(&u8(base + page)) } == 0x7c && unsafe { *(&u8(base + page * 3)) } == 0x7d
		assert darwin_munmap(voidptr(base), usize(page * 5)) == 0
	}
	base := u64(darwin_mmap(unsafe { nil }, usize(page), 3, 0x1002, -1, 0)); assert base != ~u64(0)
	for protection in [i32(0), 1, 3]! {
		assert darwin_mprotect(voidptr(base), usize(page), protection) == 0
		for advice in [i32(0), 1, 2, 3, 4, 5, 7, 8]! {
			expected := if (advice == 3 && protection & 1 == 0) || (advice == 7 && protection & 2 == 0) { i32(1) } else { i32(0) }
			advice_result(native, base, page, advice, expected)
		}
	}
	assert darwin_munmap(voidptr(base), usize(page)) == 0
}

fn advice_shared() {
	page := mach_page_size(); task := system_data.task_self
	mut source := u64(0); assert darwin_vm_allocate(task, unsafe { &source }, page, 1) == 0
	mut alias := u64(0); mut current := i32(0); mut maximum := i32(0)
	assert darwin_vm_remap(task, unsafe { &alias }, page, 0, 1, task, source, 0, unsafe { &current }, unsafe { &maximum }, 1) == 0
	unsafe { *(&u8(source)) = 0x49 }
	for advice in [i32(0), 1, 2, 3, 4, 8]! { advice_result(false, source, page, advice, 0); assert unsafe { *(&u8(alias)) } == 0x49 }
	$if linux {
		for advice in [i32(5), 7]! { advice_result(false, source, page, advice, 45); assert unsafe { *(&u8(source)) } == 0x49 && unsafe { *(&u8(alias)) } == 0x49 }
	}
	assert darwin_vm_deallocate(task, source, page) == 0 && darwin_vm_deallocate(task, alias, page) == 0
	// Reject shared and private file discards before changing their bytes.
	name := c'/vinix-ios-advice-test'; C.shm_unlink(name)
	fd := C.shm_open(name, C.O_CREAT | C.O_EXCL | C.O_RDWR, 384); assert fd >= 0
	assert C.shm_unlink(name) == 0 && C.ftruncate(fd, page) == 0
	shared := u64(C.mmap(unsafe { nil }, usize(page), 3, C.MAP_SHARED, fd, 0)); assert shared != ~u64(0)
	unsafe { *(&u8(shared)) = 0x61 }
	for advice in [i32(0), 4, 8]! { advice_result(false, shared, page, advice, 0); assert unsafe { *(&u8(shared)) } == 0x61 }
	$if linux {
		private := u64(C.mmap(unsafe { nil }, usize(page), 3, C.MAP_PRIVATE, fd, 0)); assert private != ~u64(0)
		unsafe { *(&u8(private)) = 0x62 }
		for advice in [i32(5), 7]! {
			advice_result(false, shared, page, advice, 45); advice_result(false, private, page, advice, 45)
			assert unsafe { *(&u8(shared)) } == 0x61 && unsafe { *(&u8(private)) } == 0x62
		}
		assert C.munmap(voidptr(private), usize(page)) == 0
	}
	assert C.munmap(voidptr(shared), usize(page)) == 0 && C.close(fd) == 0
}

fn advice_maps_profile() {
	// Both sanitizer and Vinix runs exercise the Linux maps validation. Long
	// paths may continue across fgets chunks; their continuation is not a new
	// mapping. Permissions and backing checks cover the entire extent.
	for sample in [
		['00001000-00002000 rw-p 00000000 00:00 0\n', '0']!,
		['00000000-00001000 rw-p 00000000 00:00 0 /'+ 'x'.repeat(1536) +'\n00001000-00002000 rw-p 00000000 00:00 0\n', '0']!,
		['00001000-00002000 rw-s 00000000 00:01 5 /shared\n', '45']!,
		['00001000-00002000 rw-p 00000000 08:01 5 /file\n', '45']!,
		['00001000-00002000 r--p 00000000 00:00 0\n', '1']!,
		['00002000-00003000 rw-p 00000000 00:00 0\n', '22']!,
		['malformed\n', '45']!,
	]! {
		file := C.tmpfile(); assert file != unsafe { nil }
		assert C.fwrite(sample[0].str, 1, usize(sample[0].len), file) == usize(sample[0].len)
		assert C.fseek(file, 0, 0) == 0
		assert darwin_advice_maps(file, 0x1000, 0x2000, 7) == sample[1].int()
		assert C.fclose(file) == 0
	}
	for tail in ['00002000-00003000 rw-p 00000000 00:00 0\n', '00002000-00003000 rw-s 00000000 00:01 5 /shared\n', '00003000-00004000 rw-p 00000000 00:00 0\n']! {
		file := C.tmpfile(); assert file != unsafe { nil }
		header := '00001000-00002000 rw-p 00000000 00:00 0\n'; text := header + tail
		assert C.fwrite(text.str, 1, usize(text.len), file) == usize(text.len) && C.fseek(file, 0, 0) == 0
		assert darwin_advice_maps(file, 0x1000, 0x3000, 5) == if tail.starts_with('00003000') { 22 } else if tail.contains('rw-s') { 45 } else { 0 }
		assert C.fclose(file) == 0
	}
}

fn test_madvise_compatibility() {
	advice_maps_profile()
	objc_start()
	for _ in 0 .. 2 {
		system_data_start()!
		$if macos { advice_profile(true) }
		advice_profile(false); advice_shared()
		$if linux { for advice in [i32(6), 9, 10, 11]! { advice_result(false, 0, 0, advice, 45) } }
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
			mut rejected := false; runtime_symbol(library, '_madvise') or { rejected = true }; assert rejected
		}
		system_data_stop()
	}
	objc_stop()
	println('IOS-MADVISE: native extent and protection comparisons, reusable/reuse contents, eager private discard, non-destructive DONTNEED, holes, overflow, errno, shared aliases and file guards, import scope and two image lifetimes passed')
}
