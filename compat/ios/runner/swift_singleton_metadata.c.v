// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftSingletonMetadataFailure {}
fn (_ &SwiftSingletonMetadataFailure) msg() string { return 'iOS: unsupported Swift singleton metadata, completion dependency, recursion or lifetime' }
fn (_ &SwiftSingletonMetadataFailure) code() int { return 1 }
__global swift_singleton_metadata_failure_value = SwiftSingletonMetadataFailure{}
fn swift_singleton_metadata_failure() IError { return unsafe { &swift_singleton_metadata_failure_value } }
type SwiftSingletonMetadataComplete = fn (u64,u64,u64) SwiftAssociatedMetadata
struct SwiftSingletonMetadata { metadata u64 cache u64 complete u64 is_class bool }

fn swift_singleton_metadata_descriptor(descriptor u64) !SwiftSingletonMetadata {
	if descriptor == 0 || descriptor & 3 != 0 || descriptor > ~u64(0) - 40 { return swift_singleton_metadata_failure() }
	flags := read32(descriptor)
	// Version-zero nongeneric in-place initialization. Formal root classes
	// have no resilient-superclass or generic-context trailing records.
	is_class := flags & ~u32(0x80000040) == 0x10010
	if !is_class && flags !in [u32(0x10011),0x10051,0x10012,0x10052]! { return swift_singleton_metadata_failure() }
	if is_class && descriptor > ~u64(0) - 56 { return swift_singleton_metadata_failure() }
	if flags & 31 == 17 {
		count := read32(descriptor + 20); offset := read32(descriptor + 24)
		if count > 64 || (offset != 0 && (offset < 2 || offset > 128)) || (count != 0 && offset == 0) { return swift_singleton_metadata_failure() }
	}
	record := descriptor + if is_class { u64(44) } else { u64(28) }
	cache := swift_generic_metadata_relative(record,8) or { return swift_singleton_metadata_failure() }
	metadata := swift_generic_metadata_relative(record + 4,8) or { return swift_singleton_metadata_failure() }
	complete := swift_generic_metadata_relative(record + 8,4) or { return swift_singleton_metadata_failure() }
	return SwiftSingletonMetadata{metadata,cache,complete,is_class}
}

// Called with the registry lock held. Only already registered SwiftObject
// roots are admitted; image registration and resilient relocation stay guarded.
// The completer must finish the instance layout through the checked initializer.
fn swift_singleton_class_layout_locked(value SwiftSingletonMetadata, descriptor u64, witness u64, completed bool) ! {
	m := value.metadata
	if m < 24 || m & 7 != 0 || m > ~u64(0) - 1048576 { return swift_singleton_metadata_failure() }
	info := ios_runtime.classes[m] or { return swift_singleton_metadata_failure() }
	if info.meta || info.dynamic || info.initializing || info.initialized || info.instances != 0 { return swift_singleton_metadata_failure() }
	meta := ios_runtime.classes[read64(m)] or { return swift_singleton_metadata_failure() }
	parent := ios_runtime.classes[info.parent] or { return swift_singleton_metadata_failure() }
	bits := read64(m + 32) & 7
	ro := read64(m + 32) & ~u64(7)
	count := u64(read32(descriptor + 36)); address_point := u64(read32(m + 60))
	if !meta.meta || parent.meta || parent.parent != 0 || parent.size != 16 || parent.name != '_TtCs12_SwiftObject'
		|| read64(m + 64) != descriptor || read32(descriptor) & ~u32(0x80000040) != 0x10010
		|| read32(descriptor + 20) != 0 || count > 64 || (count != 0 && read32(descriptor + 40) != 10)
		|| address_point !in [u64(16),24]! || u64(read32(descriptor + 24)) * 8 != address_point
		|| read32(m + 56) < address_point + 80 + count * 8 || read32(m + 56) > 1048576
		|| u64(read32(descriptor + 28)) * 8 + address_point != read32(m + 56)
		|| read32(descriptor + 32) < count || read32(descriptor + 32) > read32(descriptor + 28)
		|| read32(m + 40) != 2 || read32(m + 44) != 0 || bits !in [u64(1),2]!
		|| (read64(m + 8) != info.parent && read64(m + 8) != 0)
		|| ro == 0 || ro > ~u64(0) - 72 || read32(ro) & ~u32(0x40) != 0x80
		|| read32(ro + 4) < 16 || read32(ro + 4) > 1048576 || info.ivars.len != int(count) { return swift_singleton_metadata_failure() }
	if !completed { return }
	if !info.swift_layout_complete || bits != 2 || read64(m + 8) != info.parent || read64(m - 8) != witness
		|| read32(m + 48) != info.size || read32(ro + 8) != info.size
		|| read32(m + 52) < 7 || read32(m + 52) > 255 || (read32(m + 52) + 1) & read32(m + 52) != 0 { return swift_singleton_metadata_failure() }
	list := read64(ro + 48)
	if (count != 0 && list == 0) || (info.swift_ivar_list != 0 && list != info.swift_ivar_list)
		|| (list != 0 && (list & 7 != 0 || list > ~u64(0) - 8 - count * 32
		|| read32(list) != 32 || read32(list + 4) != count)) { return swift_singleton_metadata_failure() }
	for i in u64(0)..count {
		e := list + 8 + i * 32; cell := read64(e); name := read64(e + 8)
		if name == 0 || (cell != 0 && (cell & 7 != 0 || cell > ~u64(0) - 8)) { return swift_singleton_metadata_failure() }
		mut found := false
		for _, ivar in info.ivars {
			if C.strcmp(ivar.name.str,&char(name)) != 0 { continue }
			if read64(m + 80 + i * 8) != ivar.offset || read32(e + 28) != ivar.size
				|| (cell != 0 && read64(cell) != ivar.offset) { return swift_singleton_metadata_failure() }
			found = true; break
		}
		if !found { return swift_singleton_metadata_failure() }
	}
}
fn swift_singleton_metadata_layout(metadata u64, descriptor u64) !u64 {
	if metadata < 8 || metadata & 7 != 0 || metadata > ~u64(0) - 16 { return swift_singleton_metadata_failure() }
	kind := read64(metadata)
	if (read32(descriptor) & 31 == 17 && kind != 0x200)
		|| (read32(descriptor) & 31 == 18 && kind !in [u64(0x201),0x202]!)
		|| read64(metadata + 8) != descriptor { return swift_singleton_metadata_failure() }
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 88 { return swift_singleton_metadata_failure() }
	if read32(witness + 80) & 0x400000 != 0 { return u64(0xff) }
	swift_enum_tag_single_layout(metadata,0) or { return swift_singleton_metadata_failure() }
	return u64(0x3f)
}
fn swift_singleton_metadata_checked(request u64, descriptor u64) !SwiftAssociatedMetadata {
	required := request & ~u64(0x100)
	if request > 0x1ff || required !in [u64(0),1,0x3f,0xff]! { return swift_singleton_metadata_failure() }
	swift_generic_metadata_begin() or { return swift_singleton_metadata_failure() }
	defer { swift_generic_metadata_end() }
	value := swift_singleton_metadata_descriptor(descriptor)!
	// This witness factory takes the registry lock itself. Admission keeps its
	// arena alive while callbacks run outside the lock.
	witness := if value.is_class { swift_native_value_witnesses() } else { u64(0) }
	for {
		C.ios_objc_initialize_lock()
		mut entry := unsafe { &SwiftGenericMetadataEntry(nil) }
		if ios_runtime.swift_generic_metadata_arena != 0 {
			cache := unsafe { &SwiftGenericMetadataCache(ios_runtime.swift_generic_metadata_arena) }
			for i in u64(0)..ios_runtime.swift_generic_metadata_count {
				candidate := unsafe { &cache.entries[int(i)] }
				if (candidate.singleton_cache == value.cache && candidate.descriptor != descriptor)
					|| (candidate.descriptor == descriptor && candidate.singleton_cache != value.cache) { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
				if candidate.descriptor == descriptor && candidate.singleton_cache == value.cache { entry = candidate; break }
			}
		}
		if entry != unsafe { nil } {
			if entry.phase == 2 { metadata := entry.metadata; C.ios_objc_initialize_unlock(); return SwiftAssociatedMetadata{metadata:metadata} }
			if entry.phase == 3 { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
			// Allocation is already published to cache readers, even while a
			// completer is running. Nonblocking or satisfied requests never wait.
			if request & 0x100 != 0 || entry.singleton_state <= required {
				result := SwiftAssociatedMetadata{entry.metadata,entry.singleton_state}; C.ios_objc_initialize_unlock(); return result
			}
			if entry.owner == u64(C.pthread_self()) { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
			mutex := unsafe { voidptr(&entry.mutex[0]) }; C.ios_objc_initialize_unlock()
			C.pthread_mutex_lock(mutex); C.pthread_mutex_unlock(mutex); continue
		}
		if ios_runtime.swift_generic_metadata_count == 64
			|| C.ios_load_pointer(unsafe { &u64(value.cache) }) != 0 || read64(value.cache + 8) != 0 { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
		mut state := u64(0x3f)
		if value.is_class {
			swift_singleton_class_layout_locked(value,descriptor,witness,false) or { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
		} else {
			state = swift_singleton_metadata_layout(value.metadata,descriptor) or { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
		}
		cache := swift_generic_metadata_cache_locked() or { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
		entry = unsafe { &cache.entries[int(ios_runtime.swift_generic_metadata_count)] }
		if C.ios_sizeof_mutex() > 64 || C.ios_mutex_create(unsafe { &entry.mutex[0] },0) != 0 { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
		C.pthread_mutex_lock(unsafe { voidptr(&entry.mutex[0]) })
		if value.is_class {
			// Swift's singleton allocator installs reference witnesses and the
			// normalized Swift bit before exposing LayoutComplete metadata.
			swift_class_assign64(value.metadata - 8,witness)
			swift_class_assign64(value.metadata + 32,(read64(value.metadata + 32) & ~u64(7)) | 2)
		}
		entry.descriptor = descriptor; entry.metadata = value.metadata; entry.singleton_cache = value.cache; entry.singleton_state = state
		entry.owner = u64(C.pthread_self()); entry.phase = 1; ios_runtime.swift_generic_metadata_count++
		C.ios_objc_initialize_unlock()
		mut context := [4]u64{}
		call := unsafe { SwiftSingletonMetadataComplete(voidptr(value.complete)) }
		dependency := call(value.metadata,u64(unsafe { &context[0] }),0)
		mut valid := dependency.metadata == 0
		if valid && !value.is_class {
			completed := swift_singleton_metadata_layout(value.metadata,descriptor) or { u64(0xff) }
			valid = completed == 0x3f
		}
		C.ios_objc_initialize_lock()
		if valid && value.is_class {
			swift_singleton_class_layout_locked(value,descriptor,witness,true) or { valid = false }
		}
		entry.owner = 0; entry.phase = if valid { u64(2) } else { u64(3) }
		if valid { C.ios_store_pointer(unsafe { &u64(value.cache) },value.metadata) }
		C.ios_objc_initialize_unlock(); C.pthread_mutex_unlock(unsafe { voidptr(&entry.mutex[0]) })
		if !valid { return swift_singleton_metadata_failure() }
		return SwiftAssociatedMetadata{metadata:value.metadata}
	}
	return swift_singleton_metadata_failure()
}
fn swift_singleton_metadata(request u64, descriptor u64) SwiftAssociatedMetadata {
	return swift_singleton_metadata_checked(request,descriptor) or { panic(err) }
}
