// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftSingletonMetadataFailure {}
fn (_ &SwiftSingletonMetadataFailure) msg() string { return 'iOS: unsupported Swift singleton value metadata, completion dependency, recursion or lifetime' }
fn (_ &SwiftSingletonMetadataFailure) code() int { return 1 }
__global swift_singleton_metadata_failure_value = SwiftSingletonMetadataFailure{}
fn swift_singleton_metadata_failure() IError { return unsafe { &swift_singleton_metadata_failure_value } }
type SwiftSingletonMetadataComplete = fn (u64,u64,u64) SwiftAssociatedMetadata
struct SwiftSingletonMetadata { metadata u64 cache u64 complete u64 }

fn swift_singleton_metadata_descriptor(descriptor u64) !SwiftSingletonMetadata {
	if descriptor == 0 || descriptor & 3 != 0 || descriptor > ~u64(0) - 40 { return swift_singleton_metadata_failure() }
	flags := read32(descriptor)
	// Ordinary version-zero nongeneric structs/enums, in-place initialization.
	// Class relocation, generic contexts and extra trailing records need their
	// own allocation and transitive-completeness implementations.
	if flags !in [u32(0x10011),0x10051,0x10012,0x10052]! { return swift_singleton_metadata_failure() }
	if flags & 31 == 17 {
		count := read32(descriptor + 20); offset := read32(descriptor + 24)
		if count > 64 || (offset != 0 && (offset < 2 || offset > 128)) || (count != 0 && offset == 0) { return swift_singleton_metadata_failure() }
	}
	cache := swift_generic_metadata_relative(descriptor + 28,8) or { return swift_singleton_metadata_failure() }
	metadata := swift_generic_metadata_relative(descriptor + 32,8) or { return swift_singleton_metadata_failure() }
	complete := swift_generic_metadata_relative(descriptor + 36,4) or { return swift_singleton_metadata_failure() }
	return SwiftSingletonMetadata{metadata,cache,complete}
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
		state := swift_singleton_metadata_layout(value.metadata,descriptor) or { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
		cache := swift_generic_metadata_cache_locked() or { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
		entry = unsafe { &cache.entries[int(ios_runtime.swift_generic_metadata_count)] }
		if C.ios_sizeof_mutex() > 64 || C.ios_mutex_create(unsafe { &entry.mutex[0] },0) != 0 { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
		C.pthread_mutex_lock(unsafe { voidptr(&entry.mutex[0]) })
		entry.descriptor = descriptor; entry.metadata = value.metadata; entry.singleton_cache = value.cache; entry.singleton_state = state
		entry.owner = u64(C.pthread_self()); entry.phase = 1; ios_runtime.swift_generic_metadata_count++
		C.ios_objc_initialize_unlock()
		mut context := [4]u64{}
		call := unsafe { SwiftSingletonMetadataComplete(voidptr(value.complete)) }
		dependency := call(value.metadata,u64(unsafe { &context[0] }),0)
		mut valid := dependency.metadata == 0
		if valid {
			completed := swift_singleton_metadata_layout(value.metadata,descriptor) or { u64(0xff) }
			valid = completed == 0x3f
		}
		C.ios_objc_initialize_lock()
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
