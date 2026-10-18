// SPDX-License-Identifier: GPL-2.0-or-later
module main

// An entry is a send right to a slice of a backing object, not a pointer into
// the source mapping. Closing either mapping or right leaves the other alive.
struct MachMemoryEntry {
mut:
	next &MachMemoryEntry = unsafe { nil }
	name u32
	refs u32
	fd i32
	offset u64
	size u64
	protection i32
}

// Separate from thread, semaphore and host names; never reused across images.
__global mach_memory_next_name = u64(0x7000010f)

fn mach_memory_known(name u32) bool {
	return name >= 0x7000010f && u64(name) < C.ios_load_pointer(unsafe { &mach_memory_next_name }) && name & 0xff == 15
}

// Entry pointers are borrowed only while the shared namespace lock is held.
fn mach_memory_find(name u32) &MachMemoryEntry {
	mut entry := system_data.memory_entries
	for entry != unsafe { nil } {
		if entry.name == name { return entry }
		entry = entry.next
	}
	return unsafe { nil }
}

fn mach_memory_entries_clear() {
	mut entry := system_data.memory_entries
	system_data.memory_entries = unsafe { nil }
	for entry != unsafe { nil } {
		next := entry.next
		C.close(entry.fd)
		unsafe { free(entry) }
		entry = next
	}
}

fn mach_memory_port_type(name u32, output &u32) ?i32 {
	if !mach_memory_known(name) { return none }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	if mach_memory_find(name) == unsafe { nil } { return i32(15) }
	unsafe { *output = 0x10000 }
	return i32(0)
}

fn mach_memory_port_refs(name u32, right i32, output &u32) ?i32 {
	if !mach_memory_known(name) { return none }
	if right < 0 || right > 5 { return i32(18) }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	entry := mach_memory_find(name)
	if entry == unsafe { nil } { return i32(15) }
	unsafe { *output = if right == 0 { entry.refs } else { u32(0) } }
	return i32(0)
}

fn mach_memory_port_mod_refs(name u32, right i32, delta i32) ?i32 {
	if !mach_memory_known(name) { return none }
	if right < 0 || right > 5 { return i32(18) }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut entry := mach_memory_find(name)
	if entry == unsafe { nil } { return i32(15) }
	if right != 0 { return i32(17) }
	if delta < -65535 || delta > 65535 { return i32(18) }
	if entry.refs == 65535 { return if delta == -65535 { i32(20) } else { i32(0) } }
	refs := i64(entry.refs) + i64(delta)
	if refs < 0 { return i32(18) }
	entry.refs = u32(if refs > 65535 { i64(65535) } else { refs })
	if entry.refs == 0 {
		mut link := unsafe { &system_data.memory_entries }
		for unsafe { *link } != entry { link = unsafe { &(*link).next } }
		unsafe { *link = entry.next }
		C.close(entry.fd)
		unsafe { free(entry) }
	}
	return i32(0)
}

fn darwin_mach_make_memory_entry_64(task u32, size &u64, offset u64, permission i32, output &u32, parent u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if system_data == unsafe { nil } || task != system_data.task_self || size == unsafe { nil } || output == unsafe { nil } { return 4 }
	if permission < 0 { return 18 }
	if permission & ~i32(7) != 0 { return 46 } // Memory-entry flags are not implemented.
	requested := unsafe { *size }
	page := mach_page_size()
	delta := offset & (page - 1)
	if requested == 0 || requested > 0x100000000 || offset > ~u64(0) - requested { return 4 }
	rounded := mach_size(requested + delta) or { return 4 }
	start := offset - delta
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut source_fd := i32(-1)
	mut source_offset := u64(0)
	mut length := rounded
	mut allowed := i32(0)
	if parent != 0 && parent != 0xffffffff {
		entry := mach_memory_find(parent)
		if entry == unsafe { nil } {
			return if mach_exception_right(parent) == .send { i32(4) } else { i32(0x1000000a) }
		}
		if start >= entry.size || rounded > entry.size - start { return 4 }
		source_fd = entry.fd; source_offset = entry.offset + start; allowed = entry.protection
	} else {
		for mapping in system_data.vm_mappings {
			if start < mapping.address || start - mapping.address >= mapping.size { continue }
			within := start - mapping.address
			length = if rounded < mapping.size - within { rounded } else { mapping.size - within }
			source_fd = mapping.fd; source_offset = mapping.offset + within; allowed = mapping.protection
			break
		}
		// Only mappings owned by the compatibility VM may be exported. Foreign
		// malloc/mmap memory cannot be made into a shared alias by copying it.
		if source_fd < 0 { return 46 }
	}
	if permission & ~allowed != 0 { return 2 }
	next := C.ios_load_pointer(unsafe { &mach_memory_next_name })
	if next >= 0xffffffff { return 6 }
	fd := C.fcntl(source_fd, C.F_DUPFD_CLOEXEC, 0)
	if fd < 0 { return 6 }
	mut entry := unsafe { &MachMemoryEntry(C.calloc(1, sizeof(MachMemoryEntry))) }
	if entry == unsafe { nil } { C.close(fd); return 6 }
	unsafe { *entry = MachMemoryEntry{next: system_data.memory_entries, name: u32(next), refs: 1, fd: fd, offset: source_offset, size: length, protection: permission} }
	system_data.memory_entries = entry
	C.ios_store_pointer(unsafe { &mach_memory_next_name }, next + 0x100)
	unsafe { *size = length; *output = entry.name }
	return 0
}

// Current-task copy mappings get an eager backing snapshot. MAP_PRIVATE alone
// would still observe later source writes until the alias first faults on Linux.
fn mach_memory_snapshot(source i32, offset u64, size u64) i32 {
	fd := mach_backing(size)
	if fd < 0 { return -1 }
	// POSIX shm descriptors on the Mac reject pread/pwrite. Temporary shared
	// views work there and with Vinix memfds, without changing source rights.
	input := C.mmap(unsafe { nil }, usize(size), C.PROT_READ, C.MAP_SHARED, int(source), i64(offset))
	if input == unsafe { voidptr(-1) } { C.close(fd); return -1 }
	output := C.mmap(unsafe { nil }, usize(size), C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, int(fd), 0)
	if output == unsafe { voidptr(-1) } { C.munmap(input, usize(size)); C.close(fd); return -1 }
	C.memcpy(output, input, usize(size))
	C.munmap(input, usize(size)); C.munmap(output, usize(size))
	return fd
}

// The region can span adjacent owned mappings, including earlier replacements.
fn mach_mapping_covers(address u64, size u64) bool {
	if address > ~u64(0) - size { return false }
	mut cursor := address
	for cursor < address + size {
		mut end := cursor
		for mapping in system_data.vm_mappings {
			if cursor >= mapping.address && cursor - mapping.address < mapping.size { end = mapping.address + mapping.size; break }
		}
		if end == cursor { return false }
		cursor = end
	}
	return true
}

// BSD fixed mappings, unmaps and protection changes cannot bypass the owned
// region ledger. Interoperation is unsupported until those paths can split and
// update its protections atomically; reject overlap before any native mutation.
fn mach_mapping_overlaps(address u64, size u64) bool {
	if system_data == unsafe { nil } || size == 0 { return false }
	page := mach_page_size()
	if size > ~u64(0) - (page - 1) { return true }
	rounded := (size + page - 1) & ~(page - 1)
	if address > ~u64(0) - rounded { return true }
	for mapping in system_data.vm_mappings {
		if address < mapping.address + mapping.size && mapping.address < address + rounded { return true }
	}
	return false
}

// At most one original region can be split into two by a contiguous removal.
fn mach_mapping_split_fd(address u64, size u64) ?i32 {
	for mapping in system_data.vm_mappings {
		if address > mapping.address && address < mapping.address + mapping.size && address + size < mapping.address + mapping.size {
			fd := C.fcntl(mapping.fd, C.F_DUPFD_CLOEXEC, 0)
			if fd < 0 { return none }
			return fd
		}
	}
	return i32(-1)
}

// Called only after munmap or a successful MAP_FIXED over a fully owned range.
fn mach_mapping_remove(address u64, size u64, split_fd i32) {
	end := address + size
	mut index := 0
	for index < system_data.vm_mappings.len {
		mapping := system_data.vm_mappings[index]
		stop := mapping.address + mapping.size
		if stop <= address || mapping.address >= end { index++; continue }
		if address <= mapping.address && end >= stop {
			C.close(mapping.fd); system_data.vm_mappings.delete(index); continue
		}
		if address > mapping.address {
			system_data.vm_mappings[index].size = address - mapping.address
			if end < stop {
				assert split_fd >= 0
				system_data.vm_mappings << MachMapping{address: end, size: stop - end, fd: split_fd, offset: mapping.offset + end - mapping.address, protection: mapping.protection, maximum: mapping.maximum}
			}
		} else {
			system_data.vm_mappings[index].address = end
			system_data.vm_mappings[index].offset += end - mapping.address
			system_data.vm_mappings[index].size = stop - end
		}
		index++
	}
}

fn darwin_vm_map(task u32, address &u64, size u64, mask u64, flags i32, object u32, offset u64, copy i32, current i32, maximum i32, inheritance i32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if system_data == unsafe { nil } || task != system_data.task_self || address == unsafe { nil } { return 4 }
	if current < 0 || maximum < 0 || current & ~i32(7) != 0 || maximum & ~i32(7) != 0 { return 4 }
	if mask != 0 || flags !in [i32(0), 1, 0x4000] || inheritance != 1 { return 46 }
	page := mach_page_size()
	if offset & (page - 1) != 0 { return 4 }
	rounded := mach_size(size) or { return 4 }
	requested := unsafe { *address } & ~(page - 1)
	if requested > ~u64(0) - rounded { return 4 }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut fd := i32(-1)
	mut backing_offset := offset
	if object == 0 || object == 0xffffffff {
		if offset != 0 { return 46 }
		if maximum & 4 != 0 { return 46 } // Executable anonymous mappings are unsupported.
		fd = mach_backing(rounded)
	} else {
		entry := mach_memory_find(object)
		if entry == unsafe { nil } { return if mach_exception_right(object) == .send { i32(4) } else { i32(0x1000000a) } }
		if offset >= entry.size || rounded > entry.size - offset { return 1 }
		if maximum & ~entry.protection != 0 { return 17 }
		backing_offset += entry.offset
		if copy != 0 { fd = mach_memory_snapshot(entry.fd, backing_offset, rounded); backing_offset = 0 }
		else { fd = C.fcntl(entry.fd, C.F_DUPFD_CLOEXEC, 0) }
	}
	if fd < 0 { return 3 }
	mut map_flags := int(C.MAP_SHARED)
	mut split_fd := i32(-1)
	if flags == 0x4000 {
		if !mach_mapping_covers(requested, rounded) { C.close(fd); return 46 }
		split_fd = mach_mapping_split_fd(requested, rounded) or { C.close(fd); return 3 }
		map_flags |= int(C.MAP_FIXED)
	} else {
		$if linux { if flags == 0 { map_flags |= 0x100000 } }
	}
	mapped := C.mmap(unsafe { voidptr(if flags == 1 { u64(0) } else { requested }) }, usize(rounded), int(current & maximum), map_flags, int(fd), i64(backing_offset))
	if mapped == unsafe { voidptr(-1) } || (flags != 1 && u64(mapped) != requested) {
		if mapped != unsafe { voidptr(-1) } { C.munmap(mapped, usize(rounded)) }
		if split_fd >= 0 { C.close(split_fd) }; C.close(fd); return 3
	}
	if flags == 0x4000 { mach_mapping_remove(requested, rounded, split_fd) }
	system_data.vm_mappings << MachMapping{address: u64(mapped), size: rounded, fd: fd, offset: backing_offset, protection: current & maximum, maximum: maximum}
	unsafe { *address = u64(mapped) }
	return 0
}

fn mach_memory_entry_symbol(symbol string) ?u64 {
	return match symbol {
		'_mach_make_memory_entry_64' { u64(unsafe { voidptr(darwin_mach_make_memory_entry_64) }) }
		'_vm_map' { u64(unsafe { voidptr(darwin_vm_map) }) }
		else { return none }
	}
}
