// SPDX-License-Identifier: GPL-2.0-or-later
module main

type RegionCall = fn (u32, voidptr, voidptr, i32, voidptr, voidptr, voidptr) i32
type RegionWide = fn (u64, voidptr, voidptr, u64, voidptr, voidptr, voidptr) i32

fn region_native(task u32, address voidptr, size voidptr, flavor i32, info voidptr, count voidptr, object voidptr) i32 {
	$if macos { return C.vm_region_64(task, address, size, flavor, info, count, object) }
	return 46
}

fn test_region_bounds_parser() {
	for bad in ['', '1000-', '-2000 ', '1000-2000', '2000-1000 ', '1000-1000 ',
		'10000000000001000-2000 ', '1000-10000000000002000 ', '1000x2000 ']! {
		assert !vm_region_after(bad.str, bad.len, 0)
	}
	for line in ['1000-2000 r--p ', '000000001000-000000002000 rw-s ', '1000-2000 ' + 'x'.repeat(4096)]! {
		assert vm_region_after(line.str, line.len, 0)
		assert vm_region_after(line.str, line.len, 0x1005)
		assert vm_region_after(line.str, line.len, 0x1fff)
		assert !vm_region_after(line.str, line.len, 0x2000)
		assert !vm_region_after(line.str, line.len, ~u64(0))
	}
	upper := 'A000-B000 '
	assert vm_region_after(upper.str, upper.len, 0xAFFF)
}

fn region_invoke(client RegionCall, task u32, flavor i32, buffer &u8, layout [5]int) i32 {
	base := u64(buffer)
	wide := unsafe { RegionWide(voidptr(client)) }
	return wide(0x1234567800000000 | u64(task), voidptr(base + u64(layout[0])),
		voidptr(base + u64(layout[1])), 0x8765432100000000 | u64(u32(flavor)),
		voidptr(base + u64(layout[2])), voidptr(base + u64(layout[3])), voidptr(base + u64(layout[4])))
}

fn region_case(client RegionCall, task u32, requested u64, flavor i32, capacity u32, layout [5]int, failure i32) {
	mut actual := [256]u8{init: 0xa5}
	C.memcpy(unsafe { &actual[layout[0]] }, unsafe { &requested }, 8)
	C.memcpy(unsafe { &actual[layout[3]] }, unsafe { &capacity }, 4)
	mut expected := [256]u8{}
	C.memcpy(unsafe { &expected[0] }, unsafe { &actual[0] }, sizeof(actual))
	mut result := failure
	$if macos {
		darwin_set_errno(83)
		result = region_invoke(region_native, C.mach_task_self(), flavor, unsafe { &expected[0] }, layout)
		assert unsafe { *C.ios_errno_address() } == 83
	}
	darwin_set_errno(83)
	assert region_invoke(client, task, flavor, unsafe { &actual[0] }, layout) == result
	assert unsafe { *C.ios_errno_address() } == 83
	assert C.memcmp(unsafe { &actual[0] }, unsafe { &expected[0] }, sizeof(actual)) == 0
	$if macos {
		if result == 0 {
			mut object := u32(0)
			C.memcpy(unsafe { &object }, unsafe { &actual[layout[4]] }, 4)
			assert object == 0
		}
	}
}

fn region_error(client RegionCall, task u32, expected i32) {
	mut bytes := [256]u8{init: 0xa5}
	requested := ~u64(0)
	capacity := u32(0)
	C.memcpy(unsafe { &bytes[16] }, unsafe { &requested }, 8)
	C.memcpy(unsafe { &bytes[128] }, unsafe { &capacity }, 4)
	mut before := [256]u8{}
	C.memcpy(unsafe { &before[0] }, unsafe { &bytes[0] }, sizeof(bytes))
	darwin_set_errno(83)
	assert region_invoke(client, task, -1, unsafe { &bytes[0] }, [16, 40, 64, 128, 152]!) == expected
	assert unsafe { *C.ios_errno_address() } == 83
	assert C.memcmp(unsafe { &before[0] }, unsafe { &bytes[0] }, sizeof(bytes)) == 0
}

fn region_matrix(client RegionCall, task u32) {
	page := mach_page_size()
	mapped := C.mmap(unsafe { nil }, usize(page * 5), 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapped != unsafe { voidptr(-1) }
	defer { assert C.munmap(mapped, usize(page * 5)) == 0 }
	base := u64(mapped)
	assert C.mprotect(voidptr(base + page), usize(page), 1) == 0
	assert C.mprotect(voidptr(base + page * 2), usize(page), 0) == 0
	for requested in [u64(0), base + page + 31, base + page * 2 + 1, ~u64(0)]! {
		for flavor in [i32(-1), 0, 9, 10, 11, 12, 13, 14]! {
			for capacity in [u32(0), 4, 5, 7, 8, 9, 10, 11, 0xffffffff]! {
				minimum := if flavor == 12 { u32(5) } else { u32(9) }
				expected := if requested == ~u64(0) { i32(1) }
					else if flavor !in [i32(9), 10, 12, 13]! || capacity < minimum { i32(4) }
					else { i32(46) }
				region_case(client, task, requested, flavor, capacity, [16, 40, 64, 128, 152]!, expected)
			}
		}
	}
	for layout in [[17, 41, 65, 129, 153]!, [16, 16, 64, 128, 152]!, [16, 40, 16, 128, 152]!,
		[16, 40, 64, 16, 152]!, [16, 40, 64, 128, 16]!, [16, 40, 64, 64, 152]!, [16, 40, 64, 128, 64]!]! {
		region_case(client, task, 0, 9, 9, layout, 46)
	}
	assert C.munmap(voidptr(base + page * 2), usize(page)) == 0
	region_case(client, task, base + page * 2 + 31, 9, 9, [16, 40, 64, 128, 152]!, 46)
	assert C.mmap(voidptr(base + page * 2), usize(page), 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS | C.MAP_FIXED, -1, 0) == voidptr(base + page * 2)
}

fn region_worker(context voidptr) voidptr {
	task := u32(u64(context))
	for _ in 0 .. 40 {
		mut bytes := [256]u8{init: 0xa5}
		requested := u64(0); capacity := u32(9)
		C.memcpy(unsafe { &bytes[16] }, unsafe { &requested }, 8)
		C.memcpy(unsafe { &bytes[128] }, unsafe { &capacity }, 4)
		darwin_set_errno(83)
		expected := $if macos { i32(0) } $else { i32(46) }
		assert region_invoke(darwin_vm_region_64, task, 13, unsafe { &bytes[0] }, [16, 40, 64, 128, 152]!) == expected
		assert unsafe { *C.ios_errno_address() } == 83
	}
	return unsafe { nil }
}

fn test_vm_region_64() {
	client := unsafe { RegionCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_vm_region_64')!)) }
	region_error(client, 0, 0x10000003)
	for _ in 0 .. 2 {
		system_data_start()!
		task := system_data.task_self
		region_matrix(client, task)
		$if macos { println('NATIVE-VM-REGION-64: full guarded records, count thresholds, legacy/basic/top/extended flavors, end-of-map priority, split protections, holes and unaligned/aliased native output order compared') }
		worker := darwin_mach_thread_self(); host := darwin_mach_host_self()
		mut semaphore := u32(0)
		assert darwin_semaphore_create(task, unsafe { &semaphore }, 0, 1) == 0
		for name in [worker, host, semaphore]! { region_error(client, name, 4) }
		for name in [u32(0), 0xffffffff, 0x65432103]! { region_error(client, name, 0x10000003) }
		mut receive := u32(0)
		assert darwin_mach_port_allocate(task, 1, unsafe { &receive }) == 0
		region_error(client, receive, 0x10000003)
		assert darwin_mach_port_insert_right(task, receive, receive, 20) == 0
		region_error(client, receive, 46)
		assert darwin_mach_port_destroy(task, receive) == 0
		region_error(client, receive, 0x10000003)
		mut handles := [8]u64{}
		for index in 0 .. 8 { assert darwin_pthread_create(unsafe { &handles[index] }, unsafe { nil }, unsafe { voidptr(region_worker) }, voidptr(u64(task))) == 0 }
		for handle in handles { assert darwin_pthread_join(handle, unsafe { nil }) == 0 }
		image_atfork_start()!
		child := C.ios_fork(); assert child >= 0
		if child == 0 { region_worker(voidptr(u64(system_data.task_self))); C._exit(0) }
		mut status := i32(-1)
		assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
		image_atfork_stop()
		assert darwin_semaphore_destroy(task, semaphore) == 0
		assert darwin_mach_port_deallocate(task, worker) == 0 && darwin_mach_port_deallocate(task, host) == 0
		system_data_stop()
	}
	mut rejected := false
	runtime_symbol('/usr/lib/libobjc.A.dylib', '_vm_region_64') or { rejected = true }
	assert rejected
	println('IOS-VM-REGION-64: native seven-argument query forwarding; Vinix destination/end-of-map/flavor/count validation and explicit unsupported metadata with untouched outputs, dirty upper arguments, errno, eight workers, fork and two runtimes')
}
