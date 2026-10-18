// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>
fn C.dlsym(voidptr, &char) voidptr

type HostPageSize = fn (u32, &u64) i32
type HostPageSizeWide = fn (u64, &u64) i32

fn hps_outputs(get HostPageSize, expected u64, id int) {
	mut environment := [32]u64{}
	assert C.fegetenv(unsafe { voidptr(&environment[0]) }) == 0
	previous := unsafe { *C.ios_errno_address() }
	defer { C.fesetenv(unsafe { voidptr(&environment[0]) }); darwin_set_errno(previous) }
	page := u64(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, usize(page * 3), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapping != unsafe { voidptr(-1) }
	defer { assert C.munmap(mapping, usize(page * 3)) == 0 }
	assert C.mprotect(voidptr(u64(mapping) + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	wide := unsafe { HostPageSizeWide(voidptr(get)) }
	for rounding in [i32(C.FE_TONEAREST), C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! {
		assert C.fesetround(rounding) == 0
		C.feclearexcept(C.FE_ALL_EXCEPT); C.feraiseexcept(C.FE_DIVBYZERO | C.FE_INEXACT)
		flags := C.fetestexcept(C.FE_ALL_EXCEPT)
		for port in [u32(0), 1, 0xffffffff, 0x12345678]! {
			// Both guard boundaries and unaligned outputs expose widened,
			// truncated or misplaced writes. Bytes outside vm_size_t survive.
			for offset in [u64(0), 1, 7, page - 8]! {
				start := u64(mapping) + page; output := start + offset
				C.memset(voidptr(start), 0xa5, usize(page))
				darwin_set_errno(80 + id)
				assert wide(0xdecafbad00000000 | u64(port), unsafe { &u64(output) }) == 0
				assert unsafe { *C.ios_errno_address() } == 80 + id
				assert C.fegetround() == rounding && C.fetestexcept(C.FE_ALL_EXCEPT) == flags
				for i in 0 .. 8 { assert unsafe { *(&u8(output + u64(i))) } == u8(expected >> u64(i * 8)) }
				for i in u64(0) .. page { if i < offset || i >= offset + 8 { assert unsafe { *(&u8(start + i)) } == 0xa5 } }
			}
		}
	}
}

fn test_host_page_size() {
	if os.getenv('VINIX_IOS_HOST_PAGE_SIZE_UNCONFIGURED') != '' { darwin_host_page_size(0, unsafe { nil }); assert false }
	assert system_data == unsafe { nil }
	address := runtime_symbol('/usr/lib/libSystem.B.dylib', '_host_page_size') or { panic(err) }
	get := unsafe { HostPageSize(voidptr(address)) }
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		expected := u64(C.getpagesize())
		cell := runtime_symbol('/usr/lib/libSystem.B.dylib', '_vm_page_size') or { panic(err) }
		assert cell == u64(unsafe { &system_data.page_size }) && read64(cell) == expected
		hps_outputs(get, expected, 0)
		$if macos {
			native := unsafe { HostPageSize(C.dlsym(voidptr(-2), c'host_page_size')) }
			assert native != unsafe { nil }; hps_outputs(native, expected, 0)
		}
		// Follow the writable exported cache, including all eight bytes;
		// host getpagesize() would silently return a different answer here.
		unsafe { *(&u64(cell)) = 0x0102030405060708 }
		hps_outputs(get, 0x0102030405060708, 0)
		mut workers := []thread{cap: 8}
		for id in 0 .. 8 { workers << spawn hps_outputs(get, 0x0102030405060708, id) }
		workers.wait(); unsafe { workers.free() }
		unsafe { *(&u64(cell)) = expected }
		assert get(0, unsafe { &u64(cell) }) == 0 && read64(cell) == expected
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', '_host_page_size')! == address
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
			mut rejected := false; runtime_symbol(library, '_host_page_size') or { rejected = true }; assert rejected
		}
		system_data_stop(); objc_stop(); assert system_data == unsafe { nil }
	}
	mut child := os.new_process(os.executable())
	mut environment := os.environ(); environment['VINIX_IOS_HOST_PAGE_SIZE_UNCONFIGURED'] = '1'
	child.set_environment(environment); child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	assert code != 0 && output.contains('iOS: host page size requires configured system data') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	println('IOS-HOST-PAGE-SIZE: native cached value, ignored/dirty-upper port, eight-byte guarded unaligned outputs, writable cache alias, errno/fenv, eight workers, scoping and two system-data lifecycles passed')
}
