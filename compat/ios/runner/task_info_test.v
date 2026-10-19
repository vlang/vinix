// SPDX-License-Identifier: GPL-2.0-or-later
module main

type TaskInfoTestCall = fn (u32, i32, voidptr, voidptr) i32
type TaskInfoTestWide = fn (u64, i64, voidptr, voidptr) i32

fn ti_pack_test() {
	memory := TaskInfoMemory{virtual: 0x123456789, resident: 0x23456789a, peak: 0x3456789ab, swap: 0x456789abc, regions: 77, page: 16384}
	for flavor in [i32(20),22]! {
		mut words := [93]u32{}
		task_info_pack(memory, flavor, unsafe { &words[0] })
		mut expected := [93]u32{}
		expected[0] = 0x23456789; expected[1] = 1
		if flavor == 20 { expected[2] = 0x3456789a; expected[3] = 2; expected[4] = 0x456789ab; expected[5] = 3; expected[10] = 1 }
		else { expected[2] = 77; expected[3] = 16384; expected[4] = 0x3456789a; expected[5] = 2; expected[6] = 0x456789ab; expected[7] = 3; expected[36] = 0x8acf1356; expected[37] = 6 }
		assert C.memcmp(unsafe { &words[0] }, unsafe { &expected[0] }, sizeof(words)) == 0
	}
	mut memory_map := TaskInfoMemory{}
	for line in ['00001000-00003000 rw-p pathname', '100000000-100004000 r-xp']! { assert task_info_map_line(line.str, line.len, unsafe { &memory_map }) }
	assert memory_map.virtual == 24576 && memory_map.regions == 2
	for line in ['', '0-0 ', '20-10 ', '1-2', 'x-2 ', '-2 ', '1--2 ', '10000000000000000-20000000000000000 ']! {
		before := memory_map.virtual
		assert !task_info_map_line(line.str, line.len, unsafe { &memory_map }) && memory_map.virtual == before
	}
	memory_map.virtual = ~u64(0); assert !task_info_map_line(c'1-2 ', 4, unsafe { &memory_map })
}

fn ti_word(bytes &u8, offset int) u32 { mut word := u32(0); C.memcpy(unsafe { voidptr(&word) }, unsafe { bytes + offset }, 4); return word }
fn ti_long(bytes &u8, offset int) u64 { mut word := u64(0); C.memcpy(unsafe { voidptr(&word) }, unsafe { bytes + offset }, 8); return word }

fn ti_calls(client TaskInfoTestCall, task u32) {
	dirty := unsafe { TaskInfoTestWide(voidptr(client)) }
	for flavor in [i32(20),22,999]! { for requested in u32(0) .. 106 { for shift in [0,1,3]! {
		mut bytes := [448]u8{init: 0xa5}; mut count_bytes := [12]u8{init: 0xa5}
		C.memcpy(unsafe { &count_bytes[shift] }, unsafe { &requested }, 4)
		darwin_set_errno(83)
		result := dirty(0x1234567800000000 | u64(task), i64(0x1234567800000000 | u64(u32(flavor))), unsafe { &bytes[16 + shift] }, unsafe { &count_bytes[shift] })
		assert unsafe { *C.ios_errno_address() } == 83
		length := task_info_count(flavor, requested)
		assert result == if length == 0 { i32(4) } else { i32(0) }
		assert ti_word(unsafe { &count_bytes[0] }, shift) == if result == 0 { length } else { requested }
		for i,b in count_bytes { if i < shift || i >= shift + 4 { assert b == 0xa5 } }
		for i,b in bytes { if i < 16 + shift || i >= 16 + shift + int(if result == 0 { length * 4 } else { u32(0) }) { assert b == 0xa5 } }
		if result == 0 {
			pointer := unsafe { &bytes[16 + shift] }
			resident := ti_long(pointer, if flavor == 20 { 8 } else { 16 })
			peak := ti_long(pointer, if flavor == 20 { 16 } else { 24 })
			assert ti_long(pointer, 0) > 0 && resident > 0 && peak >= resident
			if flavor == 22 { assert ti_word(pointer, 8) > 0 && ti_word(pointer, 12) == u32(C.getpagesize()) }
			$if linux {
				if flavor == 20 { for i in 24 .. 40 { assert unsafe { pointer[i] } == 0 }; assert ti_word(pointer,40) == 1 && ti_word(pointer,44) == 0 }
				else { for i in 32 .. 144 { assert unsafe { pointer[i] } == 0 }; if length >= 38 { assert ti_long(pointer,144) >= resident }; for i in 152 .. int(length * 4) { assert unsafe { pointer[i] } == 0 } }
			}
			$if macos {
				mut native := [93]u32{}; mut native_count := requested
				assert C.task_info(C.mach_task_self(), flavor, unsafe { &native[0] }, unsafe { &native_count }) == 0 && native_count == length
				native_bytes := unsafe { &u8(&native[0]) }
				for offset in if flavor == 20 { [0,8,16]! } else { [0,16,24]! } {
					left := ti_long(pointer,offset); right := ti_long(native_bytes,offset)
					assert (if left > right { left - right } else { right - left }) < 67108864
				}
				if flavor == 22 { assert ti_word(pointer,12) == native[3] }
			}
		}
	} } }
	$if macos { println('NATIVE-TASK-INFO: counts, guarded extents, memory fields and page size match live native task_info') }
}

fn ti_error(client TaskInfoTestCall, task u32, expected i32) {
	for flavor in [i32(20),22,999]! { for requested in [u32(0),12,93,0xffffffff]! {
		mut bytes := [384]u8{init: 0xa5}; mut count := requested; darwin_set_errno(83)
		assert client(task,flavor,unsafe { &bytes[0] },unsafe { &count }) == expected && count == requested
		for b in bytes { assert b == 0xa5 }; assert unsafe { *C.ios_errno_address() } == 83
		assert client(task,flavor,unsafe { nil },unsafe { &count }) == expected && count == requested
	} }
}

fn ti_guard_alias(client TaskInfoTestCall, task u32) {
	page := usize(C.getpagesize()); mapping := C.mmap(unsafe { nil }, page * 4, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	assert mapping != voidptr(-1); defer { assert C.munmap(mapping,page * 4) == 0 }
	assert C.mprotect(voidptr(u64(mapping)+u64(page)),page,C.PROT_NONE) == 0
	assert C.mprotect(voidptr(u64(mapping)+u64(page)*3),page,C.PROT_NONE) == 0
	for flavor in [i32(20),22]! { for requested in [u32(12),36,37,38,42,84,86,87,89,93,0xffffffff]! {
		length := task_info_count(flavor,requested); if length == 0 { continue }
		for shift in [u64(0),1,3]! {
			at := u64(mapping)+u64(page)-u64(length)*4-shift; count_at := u64(mapping)+u64(page)*3-4-shift
			C.memcpy(voidptr(count_at),unsafe { &requested },4)
			assert client(task,flavor,voidptr(at),voidptr(count_at)) == 0 && ti_word(unsafe { &u8(count_at) },0) == length
		}
		for offset in [0,1,4,8,44,140,368]! {
			mut bytes := [448]u8{init: 0xa5}; C.memcpy(unsafe { &bytes[16+offset] },unsafe { &requested },4)
			assert client(task,flavor,unsafe { &bytes[16] },unsafe { &bytes[16+offset] }) == 0 && ti_word(unsafe { &bytes[0] },16+offset) == length
			for i,b in bytes { if i < 16 || (i >= 16 + int(length * 4) && (i < 16+offset || i >= 20+offset)) { assert b == 0xa5 } }
		}
	} }
}

fn ti_allocation(client TaskInfoTestCall, task u32) {
	mut before := [12]u32{}; mut during := [93]u32{}; mut after := [12]u32{}; mut count := u32(12)
	assert client(task,20,unsafe { &before[0] },unsafe { &count }) == 0
	size := usize(32*1024*1024); page := usize(C.getpagesize()); memory := C.mmap(unsafe { nil },size,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert memory != voidptr(-1)
	for offset := usize(0); offset < size; offset += page { unsafe { *(&u8(u64(memory)+u64(offset))) = 0x7b } }
	count = 93; assert client(task,22,unsafe { &during[0] },unsafe { &count }) == 0 && count == 93
	assert ti_long(unsafe { &u8(&during[0]) },0) >= ti_long(unsafe { &u8(&before[0]) },0) + u64(size)
	assert ti_long(unsafe { &u8(&during[0]) },16) >= ti_long(unsafe { &u8(&before[0]) },8) + u64(size) / 2
	assert C.munmap(memory,size) == 0
	count = 12; assert client(task,20,unsafe { &after[0] },unsafe { &count }) == 0
	assert ti_long(unsafe { &u8(&after[0]) },16) >= ti_long(unsafe { &u8(&during[0]) },16)
}

struct TaskInfoWorker { client TaskInfoTestCall; task u32 }
fn ti_worker(context voidptr) voidptr {
	state := unsafe { &TaskInfoWorker(context) }
	for _ in 0 .. 24 { mut words := [93]u32{}; mut count := u32(93);darwin_set_errno(83);assert state.client(state.task,22,unsafe { &words[0] },unsafe { &count }) == 0 && count == 93 && words[3] == u32(C.getpagesize());assert unsafe { *C.ios_errno_address() } == 83 }
	return unsafe { nil }
}

fn test_task_info() {
	ti_pack_test()
	client := unsafe { TaskInfoTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_task_info')!)) }
	ti_error(client,0,0x10000003)
	for _ in 0 .. 2 {
		system_data_start()!; task := system_data.task_self
		ti_calls(client,task); ti_guard_alias(client,task); ti_allocation(client,task)
		for name in [u32(0),0xffffffff,0x65432103]! { ti_error(client,name,0x10000003) }
		thread_port := darwin_mach_thread_self(); host := darwin_mach_host_self(); mut semaphore := u32(0)
		assert darwin_semaphore_create(task,unsafe { &semaphore },0,1) == 0
		for name in [thread_port,host,semaphore]! { ti_error(client,name,4) }
		mut receive := u32(0);assert darwin_mach_port_allocate(task,1,unsafe { &receive }) == 0;ti_error(client,receive,0x10000003)
		assert darwin_mach_port_insert_right(task,receive,receive,20) == 0;ti_error(client,receive,46)
		mut handles := [8]u64{};state := TaskInfoWorker{client,task}
		for i in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[i]) },unsafe { nil },ti_worker,unsafe { voidptr(&state) }) == 0 }
		for handle in handles { assert C.pthread_join(voidptr(handle),unsafe { nil }) == 0 }
		image_atfork_start()!;child := C.ios_fork();assert child >= 0
		if child == 0 { ti_calls(client,task);C._exit(0) }
		mut status := i32(-1);assert C.ios_waitpid(child,unsafe { &status },0) == child && status == 0; image_atfork_stop()
		assert darwin_mach_port_destroy(task,receive) == 0 && darwin_semaphore_wait(semaphore) == 0 && darwin_semaphore_destroy(task,semaphore) == 0
		assert darwin_mach_port_deallocate(task,thread_port) == 0 && darwin_mach_port_deallocate(task,host) == 0
		system_data_stop();ti_error(client,task,0x10000003)
	}
	mut rejected := false;runtime_symbol('/usr/lib/libobjc.A.dylib','_task_info') or { rejected = true };assert rejected
	println('IOS-TASK-INFO: live basic/VM memory and allocation high-water mark, eight VM revisions, exact guarded/unaligned/aliased writes, destination and count validation, eight workers, fork and two runtime lifetimes; Darwin-only accounting remains unavailable')
}
