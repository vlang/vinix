// SPDX-License-Identifier: GPL-2.0-or-later
module main

type VmReadCall = fn (u32, u64, u64, u64, voidptr) i32
type VmReadWide = fn (u64, u64, u64, u64, voidptr) i32

fn vr_native(task u32, source u64, size u64, destination u64, output voidptr) i32 {
	$if macos { return C.vm_read_overwrite(task, source, size, destination, output) }
	return 46
}

fn test_vm_read_mapping_prefixes() {
	for bad in ['', '1000-2000 rw-p', '1000-2000 rwzp ', '1000-2000 rw-q ',
		'1000-2000 qw-p ', '2000-1000 rw-p ', '1000-1000 rw-p ', '-2000 rw-p ',
		'10000000000001000-2000 rw-p ', '1000-10000000000002000 rw-p ', '1000-2000xrw-p ']! {
		mut ranges := VmReadRanges{0x1005, 0x1012, 0x2001, 0x2010, 0, 0}
		vm_read_map_line(bad.str, bad.len, mut ranges)
		assert ranges.read_cursor == 0x1005 && ranges.write_cursor == 0x2001
	}
	mut ranges := VmReadRanges{0x1005, 0x1012, 0x2001, 0x2010, 0, 0}
	for line in ['1000-1010 r--p ', '1010-1020 r-xp ', '2000-2008 -w-s ', '2008-3000 rw-p ']! {
		vm_read_map_line(line.str, line.len, mut ranges)
	}
	assert ranges.read_cursor == 0x1012 && ranges.write_cursor == 0x2010
	mut gap := VmReadRanges{0x1005, 0x1020, 0x2001, 0x2010, 0, 0}
	for line in ['1000-1010 rw-p ', '1011-1020 rw-p ', '2000-2008 r--p ', '2008-2010 rw-p ']! {
		vm_read_map_line(line.str, line.len, mut gap)
	}
	assert gap.read_cursor == 0x1010 && gap.write_cursor == 0x2001
	mut upper := VmReadRanges{0xA005, 0xA010, 0xA008, 0xA010, 0, 0}
	line := 'A000-A010 rw-s '
	vm_read_map_line(line.str, line.len, mut upper)
	assert upper.read_cursor == 0xA010 && upper.write_cursor == 0xA010
}

fn vr_mapping(size u64) u64 {
	address := C.mmap(unsafe { nil }, usize(size), 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert address != unsafe { voidptr(-1) }
	return u64(address)
}

fn vr_pattern(address u64, size u64) {
	for index in u64(0) .. size { unsafe { *(&u8(address + index)) = u8(index % 127 + 1) } }
}

fn vr_call(client VmReadCall, task u32, source u64, size u64, destination u64, expected i32) {
	mut count := [25]u8{init: 0xa5}
	wide := unsafe { VmReadWide(voidptr(client)) }
	darwin_set_errno(83)
	assert wide(0x1234567800000000 | u64(task), source, size, destination, unsafe { &count[9] }) == expected
	assert unsafe { *C.ios_errno_address() } == 83
	mut written := u64(0)
	C.memcpy(unsafe { &written }, unsafe { &count[9] }, 8)
	assert written == if expected == 0 { size } else { u64(0xa5a5a5a5a5a5a5a5) }
	for index in 0 .. 9 { assert count[index] == 0xa5 }
	for index in 17 .. count.len { assert count[index] == 0xa5 }
}

fn vr_matrix(client VmReadCall, task u32) {
	page := mach_page_size()
	length := page * 5 + 65536
	source := vr_mapping(length)
	destination := vr_mapping(length)
	expected := vr_mapping(length)
	defer {
		assert C.munmap(voidptr(source), usize(length)) == 0
		assert C.munmap(voidptr(destination), usize(length)) == 0
		assert C.munmap(voidptr(expected), usize(length)) == 0
	}
	vr_pattern(source, length)
	for offset in [u64(0), 1, 7]! {
		for size in [u64(0), 1, 37, 4096, 4097, page + 17, page * 2 + 27]! {
			C.memset(voidptr(destination), 0xa5, usize(length))
			C.memset(voidptr(expected), 0xa5, usize(length))
			C.memcpy(voidptr(expected + offset), voidptr(source + 5), usize(size))
			vr_call(client, task, source + 5, size, destination + offset, 0)
			assert C.memcmp(voidptr(destination), voidptr(expected), usize(length)) == 0
		}
	}
	for spec in [[u64(0), 0, 0]!, [0, ~u64(0), ~u64(0)]!, [1, 0, destination]!,
		[1, ~u64(0), destination]!, [2, source, ~u64(0)]!, [1, source, 0]!,
		[~u64(0), source, destination]!, [0x8000000000000000, source, destination]!,
		[0x100000000, source, destination]!]! {
		C.memset(voidptr(destination), 0xa5, usize(length))
		C.memset(voidptr(expected), 0xa5, usize(length))
		vr_call(client, task, spec[1], spec[0], spec[2], if spec[0] == 0 { i32(0) } else { i32(1) })
		assert C.memcmp(voidptr(destination), voidptr(expected), usize(length)) == 0
	}
	for source_protection in [i32(0), 1, 3]! {
		for destination_protection in [i32(0), 1, 3]! {
			for size in [u64(19), page * 2 + 19, 32768, 32769]! {
				C.memset(voidptr(destination), 0xa5, usize(length))
				C.memset(voidptr(expected), 0xa5, usize(length))
				result := if source_protection == 0 || destination_protection != 3 { if size <= 32768 { i32(1) } else { i32(2) } } else { i32(0) }
				if result == 0 { C.memcpy(voidptr(expected + page - 7), voidptr(source + page - 7), usize(size)) }
				if result == 2 && source_protection != 0 { C.memcpy(voidptr(expected + page - 7), voidptr(source + page - 7), 7) }
				assert C.mprotect(voidptr(source + page), usize(page), source_protection) == 0
				assert C.mprotect(voidptr(destination + page), usize(page), destination_protection) == 0
				vr_call(client, task, source + page - 7, size, destination + page - 7, result)
				assert C.mprotect(voidptr(source + page), usize(page), 3) == 0
				assert C.mprotect(voidptr(destination + page), usize(page), 3) == 0
				assert C.memcmp(voidptr(destination), voidptr(expected), usize(length)) == 0
			}
		}
	}
	assert C.munmap(voidptr(source + page), usize(page)) == 0
	C.memset(voidptr(destination), 0xa5, usize(length)); C.memset(voidptr(expected), 0xa5, usize(length))
	for size in [u64(19), 32769]! {
		vr_call(client, task, source + page - 7, size, destination, 1)
		assert C.memcmp(voidptr(destination), voidptr(expected), usize(length)) == 0
	}
	assert C.mmap(voidptr(source + page), usize(page), 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS | C.MAP_FIXED, -1, 0) == voidptr(source + page)
	vr_pattern(source, length)
	assert C.munmap(voidptr(destination + page), usize(page)) == 0
	for size in [u64(19), 32769]! {
		C.memset(voidptr(destination), 0xa5, usize(page)); C.memset(voidptr(expected), 0xa5, usize(page))
		if size > 32768 { C.memcpy(voidptr(expected + page - 7), voidptr(source + page * 2), 7) }
		vr_call(client, task, source + page * 2, size, destination + page - 7, 1)
		assert C.memcmp(voidptr(destination), voidptr(expected), usize(page)) == 0
	}
	assert C.mmap(voidptr(destination + page), usize(page), 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS | C.MAP_FIXED, -1, 0) == voidptr(destination + page)
	for delta in [i64(-4097), -17, -1, 0, 1, 17, 4097]! {
		vr_pattern(destination, length)
		C.memcpy(voidptr(expected), voidptr(destination), usize(length))
		offset := page * 2
		size := page + 27
		target := u64(i64(destination + offset) + delta)
		C.memmove(voidptr(u64(i64(expected + offset) + delta)), voidptr(expected + offset), usize(size))
		vr_call(client, task, destination + offset, size, target, 0)
		assert C.memcmp(voidptr(destination), voidptr(expected), usize(length)) == 0
	}
	for alias_source in [false, true]! {
		vr_pattern(source, length)
		C.memset(voidptr(destination), 0xa5, usize(length)); C.memset(voidptr(expected), 0xa5, usize(length))
		size := u64(37)
		C.memcpy(voidptr(expected), voidptr(source), usize(size))
		output := if alias_source { source + 9 } else { destination + 5 }
		if !alias_source { C.memcpy(voidptr(expected + 5), unsafe { &size }, 8) }
		darwin_set_errno(83)
		assert client(task, source, size, destination, voidptr(output)) == 0 && unsafe { *C.ios_errno_address() } == 83
		mut written := u64(0)
		C.memcpy(unsafe { &written }, voidptr(output), 8)
		assert written == size && C.memcmp(voidptr(destination), voidptr(expected), usize(length)) == 0
	}
}

fn vr_worker(context voidptr) voidptr {
	task := u32(u64(context))
	for _ in 0 .. 40 {
		mut source := [64]u8{init: u8(index + 1)}
		mut destination := [64]u8{}
		vr_call(darwin_vm_read_overwrite, task, u64(unsafe { &source[0] }), 64, u64(unsafe { &destination[0] }), 0)
		assert C.memcmp(unsafe { &source[0] }, unsafe { &destination[0] }, 64) == 0
	}
	return unsafe { nil }
}

fn test_vm_read_overwrite() {
	client := unsafe { VmReadCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_vm_read_overwrite')!)) }
	vr_call(client, 0, 0, 0, 0, 0x10000003)
	$if macos {
		vr_matrix(vr_native, C.mach_task_self())
		println('NATIVE-VM-READ: full records, small/large guarded failures, zero/overflow, overlap and aliased output count compared')
	}
	for _ in 0 .. 2 {
		system_data_start()!
		task := system_data.task_self
		vr_matrix(client, task)
		worker := darwin_mach_thread_self(); host := darwin_mach_host_self()
		mut semaphore := u32(0)
		assert darwin_semaphore_create(task, unsafe { &semaphore }, 0, 1) == 0
		for name in [worker, host, semaphore]! { vr_call(client, name, 0, 0, 0, 4) }
		for name in [u32(0), 0xffffffff, 0x65432103]! { vr_call(client, name, 0, ~u64(0), 0, 0x10000003) }
		mut receive := u32(0)
		assert darwin_mach_port_allocate(task, 1, unsafe { &receive }) == 0
		vr_call(client, receive, 0, 0, 0, 0x10000003)
		assert darwin_mach_port_insert_right(task, receive, receive, 20) == 0
		vr_call(client, receive, 0, 0, 0, 46)
		assert darwin_mach_port_destroy(task, receive) == 0
		vr_call(client, receive, 0, 0, 0, 0x10000003)
		mut source := u64(0)
		page := mach_page_size()
		assert darwin_vm_allocate(task, unsafe { &source }, page, 1) == 0
		vr_pattern(source, page)
		mut destination := [64]u8{}
		vr_call(client, task, source + 3, 64, u64(unsafe { &destination[0] }), 0)
		assert C.memcmp(voidptr(source + 3), unsafe { &destination[0] }, 64) == 0
		mut size := page; mut entry := u32(0)
		assert darwin_mach_make_memory_entry_64(task, unsafe { &size }, source, 3, unsafe { &entry }, 0) == 0
		vr_call(client, entry, source, 1, 0, 4)
		assert darwin_mach_port_deallocate(task, entry) == 0 && darwin_vm_deallocate(task, source, page) == 0
		mut handles := [8]u64{}
		for index in 0 .. 8 { assert darwin_pthread_create(unsafe { &handles[index] }, unsafe { nil }, unsafe { voidptr(vr_worker) }, voidptr(u64(task))) == 0 }
		for handle in handles { assert darwin_pthread_join(handle, unsafe { nil }) == 0 }
		image_atfork_start()!
		child := C.ios_fork(); assert child >= 0
		if child == 0 { vr_worker(voidptr(u64(system_data.task_self))); C._exit(0) }
		mut status := i32(-1)
		assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
		image_atfork_stop()
		assert darwin_semaphore_destroy(task, semaphore) == 0
		assert darwin_mach_port_deallocate(task, worker) == 0 && darwin_mach_port_deallocate(task, host) == 0
		system_data_stop()
	}
	mut rejected := false
	runtime_symbol('/usr/lib/libobjc.A.dylib', '_vm_read_overwrite') or { rejected = true }
	assert rejected
	println('IOS-VM-READ-OVERWRITE: native current-task snapshots, 64-bit size/output and 32-bit destination, zero/overflow, stack and owned/foreign mappings, static holes/protections, small/large overlap, aliased output-last writes, errno, namespace errors, eight concurrent workers, fork and two runtimes')
}
