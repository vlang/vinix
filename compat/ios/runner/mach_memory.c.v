// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Mach's current-task, no-copy remaps must alias the same bytes. A private
// backing descriptor and shared mappings provide that relationship on Vinix.
// This subset does not provide cross-task mappings or copy-on-write remaps.
fn C.fcntl(i32, i32, ...i32) i32
$if linux { fn C.memfd_create(&char, u32) i32 }

struct MachMapping {
mut:
	address u64
	size u64
	offset u64
	fd i32
}

fn mach_page_size() u64 { return u64(C.getpagesize()) }

fn mach_size(size u64) ?u64 {
	page := mach_page_size()
	if size == 0 || size > 0x100000000 { return none }
	return (size + page - 1) & ~(page - 1)
}

fn mach_backing(size u64) i32 {
	mut fd := i32(-1)
	$if linux {
		fd = C.memfd_create(c'vinix-ios-vm', 1) // MFD_CLOEXEC
	} $else {
		// Also exercise the adapters under the ARM64 host sanitizers.
		mut name := [64]char{}
		system_data.vm_sequence++
		C.snprintf(unsafe { &name[0] }, 64, c'/vios-%d-%llu', i32(C.getpid()), system_data.vm_sequence)
		fd = C.shm_open(unsafe { &name[0] }, C.O_CREAT | C.O_EXCL | C.O_RDWR, 384)
		if fd >= 0 { C.shm_unlink(unsafe { &name[0] }) }
	}
	if fd >= 0 && C.ftruncate(fd, size) != 0 { C.close(fd); return -1 }
	return fd
}

fn mach_map(fd i32, offset u64, size u64, address u64, anywhere bool) ?u64 {
	mut flags := i32(C.MAP_SHARED)
	$if linux {
		if !anywhere { flags |= 0x100000 } // MAP_FIXED_NOREPLACE preserves occupied mappings.
	}
	mapped := C.mmap(unsafe { voidptr(if anywhere { u64(0) } else { address }) }, usize(size),
		C.PROT_READ | C.PROT_WRITE, flags, fd, i64(offset))
	if mapped == unsafe { voidptr(-1) } { return none }
	if !anywhere && u64(mapped) != address {
		C.munmap(mapped, usize(size))
		return none
	}
	return u64(mapped)
}

fn darwin_vm_allocate(task u32, address &u64, size u64, flags i32) i32 {
	if task != system_data.task_self || address == unsafe { nil } || flags !in [i32(0), 1] { return 4 }
	rounded := mach_size(size) or { return 4 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	fd := mach_backing(rounded)
	if fd < 0 { return 3 } // KERN_NO_SPACE
	requested := unsafe { *address } & ~(mach_page_size() - 1)
	mapped := mach_map(fd, 0, rounded, requested, flags == 1) or { C.close(fd); return 3 }
	system_data.vm_mappings << MachMapping{address: mapped, size: rounded, fd: fd}
	unsafe { *address = mapped }
	return 0
}

fn darwin_vm_remap(task u32, address &u64, size u64, mask u64, flags i32,
	source_task u32, source u64, copy i32, current &i32, maximum &i32, inheritance i32) i32 {
	if task != system_data.task_self || source_task != system_data.task_self ||
		address == unsafe { nil } || current == unsafe { nil } || maximum == unsafe { nil } ||
		flags !in [i32(0), 1] { return 4 }
	if copy != 0 || mask != 0 || inheritance != 1 { return 46 } // KERN_NOT_SUPPORTED
	page := mach_page_size()
	if source & (page - 1) != 0 { return 4 }
	rounded := mach_size(size) or { return 4 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for mapping in system_data.vm_mappings {
		if source < mapping.address || source - mapping.address >= mapping.size { continue }
		delta := source - mapping.address
		if rounded > mapping.size - delta { return 1 } // KERN_INVALID_ADDRESS
		fd := C.fcntl(mapping.fd, C.F_DUPFD_CLOEXEC, 0)
		if fd < 0 { return 3 }
		requested := unsafe { *address } & ~(page - 1)
		mapped := mach_map(fd, mapping.offset + delta, rounded, requested, flags == 1) or { C.close(fd); return 3 }
		system_data.vm_mappings << MachMapping{address: mapped, size: rounded, offset: mapping.offset + delta, fd: fd}
		unsafe { *address = mapped; *current = 3; *maximum = 7 }
		return 0
	}
	return 1
}

fn darwin_vm_deallocate(task u32, address u64, size u64) i32 {
	if task != system_data.task_self || address & (mach_page_size() - 1) != 0 { return 4 }
	rounded := mach_size(size) or { return 4 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for index, mapping in system_data.vm_mappings {
		if mapping.address != address || mapping.size != rounded { continue }
		if C.munmap(unsafe { voidptr(address) }, usize(rounded)) != 0 { return 1 }
		C.close(mapping.fd)
		system_data.vm_mappings.delete(index)
		return 0
	}
	return 1
}

fn mach_memory_stop() {
	for mapping in system_data.vm_mappings {
		C.munmap(unsafe { voidptr(mapping.address) }, usize(mapping.size))
		C.close(mapping.fd)
	}
	unsafe { system_data.vm_mappings.free() }
}

fn mach_memory_symbol(symbol string) ?u64 {
	return match symbol {
		'_vm_allocate' { u64(unsafe { voidptr(darwin_vm_allocate) }) }
		'_vm_remap' { u64(unsafe { voidptr(darwin_vm_remap) }) }
		'_vm_deallocate' { u64(unsafe { voidptr(darwin_vm_deallocate) }) }
		else { return none }
	}
}
