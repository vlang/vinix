// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <mach/mach_vm.h>
	fn C.mach_task_self() u32
	fn C.mach_vm_allocate(u32, &u64, u64, i32) i32
	fn C.mach_vm_deallocate(u32, u64, u64) i32
	fn C.mach_make_memory_entry_64(u32, &u64, u64, i32, &u32, u32) i32
	fn C.mach_vm_map(u32, &u64, u64, u64, i32, u32, u64, i32, i32, i32, i32) i32
	fn C.mach_port_type(u32, u32, &u32) i32
	fn C.mach_port_get_refs(u32, u32, i32, &u32) i32
	fn C.mach_port_mod_refs(u32, u32, i32, i32) i32
	fn C.mach_port_deallocate(u32, u32) i32
}

type MemoryEntryMake = fn (u32, &u64, u64, i32, &u32, u32) i32
type MemoryEntryMap = fn (u32, &u64, u64, u64, i32, u32, u64, i32, i32, i32, i32) i32

fn me_task(native bool) u32 {
	$if macos { if native { return C.mach_task_self() } }
	return system_data.task_self
}
fn me_allocate(native bool, address &u64, size u64) i32 {
	$if macos { if native { return C.mach_vm_allocate(me_task(true), address, size, 1) } }
	return darwin_vm_allocate(me_task(false), address, size, 1)
}
fn me_unmap(native bool, address u64, size u64) i32 {
	$if macos { if native { return C.mach_vm_deallocate(me_task(true), address, size) } }
	return darwin_vm_deallocate(me_task(false), address, size)
}
fn me_make(native bool, size &u64, address u64, permission i32, output &u32, parent u32) i32 {
	$if macos { if native { return C.mach_make_memory_entry_64(me_task(true), size, address, permission, output, parent) } }
	get := unsafe { MemoryEntryMake(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_mach_make_memory_entry_64') or { panic(err) })) }
	return get(me_task(false), size, address, permission, output, parent)
}
fn me_map(native bool, address &u64, size u64, flags i32, object u32, offset u64, copy i32, current i32, maximum i32) i32 {
	$if macos { if native { return C.mach_vm_map(me_task(true), address, size, 0, flags, object, offset, copy, current, maximum, 1) } }
	get := unsafe { MemoryEntryMap(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_vm_map') or { panic(err) })) }
	return get(me_task(false), address, size, 0, flags, object, offset, copy, current, maximum, 1)
}
fn me_mod(native bool, name u32, right i32, delta i32) i32 {
	$if macos { if native { return C.mach_port_mod_refs(me_task(true), name, right, delta) } }
	return darwin_mach_port_mod_refs(me_task(false), name, right, delta)
}
fn me_drop(native bool, name u32) i32 {
	$if macos { if native { return C.mach_port_deallocate(me_task(true), name) } }
	return darwin_mach_port_deallocate(me_task(false), name)
}
fn me_refs(native bool, name u32, right i32, output &u32) i32 {
	$if macos { if native { return C.mach_port_get_refs(me_task(true), name, right, output) } }
	return darwin_mach_port_get_refs(me_task(false), name, right, output)
}
fn me_type(native bool, name u32, output &u32) i32 {
	$if macos { if native { return C.mach_port_type(me_task(true), name, output) } }
	return darwin_mach_port_type(me_task(false), name, output)
}

fn me_profile(native bool) {
	page := mach_page_size()
	mut base := u64(0); assert me_allocate(native, unsafe { &base }, page * 3) == 0
	unsafe { *(&u8(base + 17)) = 0x41; *(&u8(base + page + 17)) = 0x42 }
	for delta in [u64(0), 1, page - 1, page, page * 2]! {
		for requested in [u64(0), 1, page, page + 1, page * 4]! {
			mut size := requested; mut name := u32(0xa5a5a5a5)
			assert me_make(native, unsafe { &size }, base + delta, 3, unsafe { &name }, 0) == if requested == 0 { 4 } else { 0 }
			if requested == 0 { assert size == 0 && name == 0xa5a5a5a5; continue }
			wanted := (requested + (delta & (page - 1)) + page - 1) & ~(page - 1)
			remaining := page * 3 - (delta & ~(page - 1))
			assert size == if wanted < remaining { wanted } else { remaining }
			assert me_drop(native, name) == 0
		}
	}
	mut size := page * 2; mut entry := u32(0)
	assert me_make(native, unsafe { &size }, base, 3, unsafe { &entry }, 0) == 0 && size == page * 2
	mut kind := u32(0x12345678); assert me_type(native, entry, unsafe { &kind }) == 0 && kind == 0x10000
	for right in i32(-1) .. 7 {
		mut refs := u32(777); result := me_refs(native, entry, right, unsafe { &refs })
		if right < 0 || right > 5 { assert result == 18 && refs == 777 }
		else { assert result == 0 && refs == if right == 0 { u32(1) } else { u32(0) } }
		assert me_mod(native, entry, right, 0) == if right < 0 || right > 5 { 18 } else if right == 0 { 0 } else { 17 }
	}
	assert me_mod(native, entry, 0, -2) == 18 && me_mod(native, entry, 0, 65536) == 18
	assert me_mod(native, entry, 0, 1) == 0 && me_drop(native, entry) == 0
	mut child := u32(0); size = page
	assert me_make(native, unsafe { &size }, page, 1, unsafe { &child }, entry) == 0 && size == page
	mut read_alias := u64(0); assert me_map(native, unsafe { &read_alias }, page, 1, child, 0, 0, 1, 1) == 0
	assert unsafe { *(&u8(read_alias + 17)) } == 0x42
	mut denied := u64(0xa5a5a5a5)
	assert me_map(native, unsafe { &denied }, page, 1, child, 0, 0, 3, 3) == 17 && denied == 0xa5a5a5a5
	if !native {
		mut current := i32(777); mut maximum := i32(888)
		assert darwin_vm_remap(me_task(false), unsafe { &denied }, page, 0, 1, me_task(false), read_alias, 0, unsafe { &current }, unsafe { &maximum }, 1) == 46
		assert denied == 0xa5a5a5a5 && current == 777 && maximum == 888
	}
	assert me_drop(native, child) == 0 && me_unmap(native, read_alias, page) == 0
	size = page; child = 0xa5a5a5a5
	assert me_make(native, unsafe { &size }, page * 2, 1, unsafe { &child }, entry) == 4 && size == page && child == 0xa5a5a5a5
	for current in [i32(0), 1, 2, 3, 7]! {
		for maximum in [i32(1), 3, 7]! {
			mut alias := u64(0)
			assert me_map(native, unsafe { &alias }, page, 1, entry, 0, 0, current, maximum) == if maximum == 7 { 17 } else { 0 }
			if maximum != 7 { assert me_unmap(native, alias, page) == 0 }
		}
	}
	for copy in [i32(0), 1]! {
		before := unsafe { *(&u8(base + 17)) }
		mut alias := u64(0); assert me_map(native, unsafe { &alias }, page, 1, entry, 0, copy, 3, 3) == 0
		unsafe { *(&u8(base + 17)) = 0x50 + u8(copy) }
		assert unsafe { *(&u8(alias + 17)) } == if copy == 0 { u8(0x50) } else { before }
		unsafe { *(&u8(alias + 17)) = 0x60 + u8(copy) }
		assert unsafe { *(&u8(base + 17)) } == if copy == 0 { u8(0x60) } else { u8(0x51) }
		assert me_unmap(native, alias, page) == 0
	}
	// Fortnite's consumer reserves a destination, then replaces pieces with
	// read-only copy mappings and drops each entry immediately after mapping.
	mut target := u64(0); assert me_allocate(native, unsafe { &target }, page * 3) == 0
	unsafe { *(&u8(target + 17)) = 0x31; *(&u8(target + page * 2 + 17)) = 0x33 }
	mut middle := target + page
	assert me_map(native, unsafe { &middle }, page, 0x4000, entry, page, 1, 1, 1) == 0 && middle == target + page
	assert unsafe { *(&u8(middle + 17)) } == 0x42
	assert unsafe { *(&u8(target + 17)) } == 0x31 && unsafe { *(&u8(target + page * 2 + 17)) } == 0x33
	assert me_unmap(native, target, page * 3) == 0
	assert me_unmap(native, base, page * 3) == 0
	mut retained := u64(0); assert me_map(native, unsafe { &retained }, page, 1, entry, 0, 0, 1, 1) == 0
	assert me_mod(native, entry, 0, -1) == 0
	assert unsafe { *(&u8(retained + 17)) } == 0x51
	assert me_unmap(native, retained, page) == 0
	kind = 777; assert me_type(native, entry, unsafe { &kind }) == 15 && kind == 777
	assert me_drop(native, entry) == 15
}

fn me_worker(shared u32, id int) {
	darwin_set_errno(80 + id)
	for _ in 0 .. 20 {
		assert me_mod(false, shared, 0, 1) == 0
		me_profile(false)
		assert me_drop(false, shared) == 0
	}
	assert unsafe { *C.ios_errno_address() } == 80 + id
}

fn test_mach_memory_entries() {
	assert system_data == unsafe { nil }
	mut retired := u32(0)
	for cycle in 0 .. 2 {
		objc_start(); system_data_start()!
		page := mach_page_size()
		assert read64(runtime_symbol('/usr/lib/libSystem.B.dylib', '_vm_page_mask')!) == page - 1
		if retired != 0 { mut kind := u32(77); assert me_type(false, retired, unsafe { &kind }) == 15 && kind == 77 }
		me_profile(false)
		$if macos { me_profile(true) }
		mut base := u64(0); assert me_allocate(false, unsafe { &base }, page * 3) == 0
		// Generic BSD adapters must not leave stale ownership/protection records
		// which could later authorize replacing an unrelated reused address.
		assert darwin_munmap(unsafe { voidptr(base + page) }, usize(page)) == -1 && unsafe { *C.ios_errno_address() } == 45
		assert darwin_mprotect(unsafe { voidptr(base) }, usize(page), 1) == -1 && unsafe { *C.ios_errno_address() } == 45
		assert darwin_mmap(unsafe { voidptr(base) }, usize(page), 3, 0x1012, -1, 0) == unsafe { voidptr(-1) } && unsafe { *C.ios_errno_address() } == 45
		assert system_data.vm_mappings.len == 1
		foreign := darwin_mmap(unsafe { nil }, usize(page * 2), 3, 0x1002, -1, 0)
		assert foreign != unsafe { voidptr(-1) }
		assert darwin_mprotect(foreign, usize(page), 1) == 0
		assert darwin_mmap(foreign, usize(page), 3, 0x1012, -1, 0) == foreign
		assert darwin_munmap(foreign, usize(page * 2)) == 0
		mut size := page; mut entry := u32(0); assert me_make(false, unsafe { &size }, base, 3, unsafe { &entry }, 0) == 0
		assert darwin_semaphore_signal(entry) == 20 && darwin_semaphore_destroy(system_data.task_self, entry) == 4
		assert darwin_exception_raise(entry, system_data.task_self, system_data.task_self, 1, unsafe { nil }, 0) == 5
		assert darwin_host_statistics(entry, 2, unsafe { nil }, unsafe { nil }) == 22
		mut invalid := u64(0x12345678); mut name := u32(777)
		assert me_make(false, unsafe { &invalid }, base, -1, unsafe { &name }, 0) == 18 && invalid == 0x12345678 && name == 777
		assert me_make(false, unsafe { &invalid }, base, 0x1000, unsafe { &name }, 0) == 46 && name == 777
		invalid = 0; assert me_make(false, unsafe { &invalid }, base, 3, unsafe { &name }, 0) == 4 && name == 777
		invalid = page; assert me_make(false, unsafe { &invalid }, ~u64(0) - page + 1, 3, unsafe { &name }, 0) == 4 && name == 777
		assert me_make(false, unsafe { &invalid }, base, 7, unsafe { &name }, 0) == 2 && name == 777
		assert me_make(false, unsafe { &invalid }, base, 3, unsafe { &name }, 0x123400) == 0x1000000a && name == 777
		assert me_make(false, unsafe { &invalid }, 0, 3, unsafe { &name }, 0) == 46 && name == 777
		mut address := base
		assert darwin_vm_map(system_data.task_self, unsafe { &address }, page, 1, 1, entry, 0, 0, 3, 3, 1) == 46 && address == base
		assert me_map(false, unsafe { &address }, page, 0, entry, 0, 0, 3, 3) == 3 && address == base
		address = 0; assert me_map(false, unsafe { &address }, page, 0x4000, entry, 0, 0, 3, 3) == 46 && address == 0
		assert me_map(false, unsafe { &address }, page * 2, 1, entry, 0, 0, 3, 3) == 1 && address == 0
		mut workers := []thread{cap: 8}; for id in 0 .. 8 { workers << spawn me_worker(entry, id) }; workers.wait(); unsafe { workers.free() }
		mut refs := u32(0); assert me_refs(false, entry, 0, unsafe { &refs }) == 0 && refs == 1
		// A split deallocation must preserve the remaining backing offsets.
		assert me_unmap(false, base + page, page) == 0
		unsafe { *(&u8(base + page * 2 + 17)) = 0x73 }
		invalid = page; assert me_make(false, unsafe { &invalid }, base + page * 2, 1, unsafe { &name }, 0) == 0
		address = 0; assert me_map(false, unsafe { &address }, page, 1, name, 0, 0, 1, 1) == 0
		assert unsafe { *(&u8(address + 17)) } == 0x73
		assert me_drop(false, name) == 0 && me_unmap(false, address, page) == 0
		assert me_unmap(false, base, page) == 0 && me_unmap(false, base + page * 2, page) == 0
		assert system_data.vm_mappings.len == 0
		// Atfork pins this same namespace lock. Child rights are retired, while
		// inherited mappings keep their independent descriptors.
		image_atfork_start()!
		child := C.ios_fork(); assert child >= 0
		if child == 0 {
			mut kind := u32(77); assert me_type(false, entry, unsafe { &kind }) == 15
			assert system_data.memory_entries == unsafe { nil }; C._exit(0)
		}
		mut status := i32(-1); assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
		assert me_refs(false, entry, 0, unsafe { &refs }) == 0 && refs == 1
		address = 0
		assert me_map(false, unsafe { &address }, page, 1, entry, 0, 0, 3, 3) == 0
		mut remapped := u64(0); mut current := i32(777); mut maximum := i32(888)
		assert darwin_vm_remap(me_task(false), unsafe { &remapped }, page, 0, 1, me_task(false), address, 0, unsafe { &current }, unsafe { &maximum }, 1) == 0
		assert current == 3 && maximum == 3
		unsafe { *(&u8(remapped + 17)) = 0x74 }; assert unsafe { *(&u8(address + 17)) } == 0x74
		assert me_unmap(false, address, page) == 0 && me_unmap(false, remapped, page) == 0
		image_atfork_stop()
		retired = entry
		// Leave a live entry deliberately: image retirement owns its cleanup.
		fd := mach_memory_find(entry).fd
		if cycle == 1 { assert me_mod(false, entry, 0, 65535) == 0 && me_mod(false, entry, 0, -65535) == 20 }
		system_data_stop(); objc_stop()
		assert C.fcntl(fd, C.F_GETFD) == -1 && system_data == unsafe { nil }
	}
	for symbol in ['_mach_make_memory_entry_64', '_vm_map', '_vm_page_mask']! {
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
			mut rejected := false; runtime_symbol(library, symbol) or { rejected = true }; assert rejected
		}
	}
	println('IOS-MEMORY-ENTRY: native region negotiation, parent slices, send rights, shared aliases, eager copy snapshots, protected overwrite, split deallocation, BSD mutation guards, errno, eight callers, fork and two image lifetimes passed')
}
