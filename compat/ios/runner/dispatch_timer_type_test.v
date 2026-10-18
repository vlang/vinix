// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

$if macos {
	#include <mach/mach.h>
	fn C.mach_task_self() u32
	fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
	fn C.mach_port_deallocate(u32, u32) i32
}

fn dtt_readonly(address u64) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(9)
		mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, 9, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + 8 <= start + size
		assert info[0] & C.PROT_READ != 0 && info[0] & C.PROT_WRITE == 0
		if object != 0 {
			assert C.mach_port_deallocate(task, object) == 0
		}
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			bounds := fields[0].split('-')
			if bounds.len != 2 { continue }
			start := strconv.parse_uint(bounds[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(bounds[1], 16, 64) or { panic(err) }
			if address >= start && address + 8 <= end {
				assert fields[1].starts_with('r-')
				found = true
				break
			}
		}
		assert found
	}
}

fn dtt_reader(entry u64) {
	for _ in 0 .. 1000 {
		darwin_set_errno(42)
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', '__dispatch_source_type_timer') or { panic(err) } == entry
		assert unsafe { *C.ios_errno_address() } == 42
	}
}

fn test_dispatch_timer_type() {
	assert ios_runtime == unsafe { nil } && system_data == unsafe { nil }
	entry := runtime_symbol('/usr/lib/libSystem.B.dylib', '__dispatch_source_type_timer') or { panic(err) }
	assert entry != 0 && entry & 7 == 0
	assert entry == dispatch_timer_type_address()
	assert entry != u64(unsafe { voidptr(darwin_dispatch_time) })
	dtt_readonly(entry)
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib',
		'/System/Library/Frameworks/Foundation.framework/Foundation']! {
		if _ := runtime_symbol(library, '__dispatch_source_type_timer') {
			assert false
		}
	}
	for name in ['_dispatch_source_type_timer', '__dispatch_source_type_timer_typo']! {
		if _ := dispatch_symbol(name) {
			assert false
		}
	}
	for _ in 0 .. 2 {
		objc_start()
		system_data_start()!
		dtt_reader(entry)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn dtt_reader(entry) }
		workers.wait()
		unsafe { workers.free() }
		objc_stop()
		system_data_stop()
		assert dispatch_runtime == unsafe { nil } && system_data == unsafe { nil }
		dtt_reader(entry)
		dtt_readonly(entry)
	}
	$if macos {
		handle := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2)
		assert handle != unsafe { nil }
		reference := C.dlsym(handle, c'_dispatch_source_type_timer')
		assert reference != unsafe { nil }
		dtt_readonly(u64(reference))
		assert C.dlclose(handle) == 0
	}
	println('IOS-DISPATCH-TIMER-TYPE: scoped direct opaque data export, read-only aligned static storage, unchanged errno, eight concurrent readers and identity across two retired runtimes')
}
