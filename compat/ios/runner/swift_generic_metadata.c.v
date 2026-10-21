// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftGenericMetadataFailure {}
fn (_ &SwiftGenericMetadataFailure) msg() string { return 'iOS: unsupported Swift generic metadata signature, pattern, result, recursion or lifetime' }
fn (_ &SwiftGenericMetadataFailure) code() int { return 1 }
__global swift_generic_metadata_failure_value = SwiftGenericMetadataFailure{}
fn swift_generic_metadata_failure() IError { return unsafe { &swift_generic_metadata_failure_value } }
type SwiftGenericMetadataInstantiate = fn (u64, u64, u64) u64

struct SwiftGenericMetadataEntry {
mut:
	descriptor u64
	count u64
	arguments [64]u64
	metadata u64
	owner u64
	phase u64 // 1 instantiating, 2 complete, 3 rejected result.
	singleton_cache u64 // Nonzero for borrowed in-place singleton value metadata.
	singleton_state u64 // Abstract/LayoutComplete while its completer runs.
	mutex [8]u64
}
struct SwiftGenericMetadataCache { mut: entries [64]SwiftGenericMetadataEntry }
struct SwiftGenericMetadataKey { count u64 kind u64 mut: arguments [64]u64 }

// Both generic instantiations and in-place singleton values share this bounded
// runtime-owned arena, user accounting and quiescent mutex/arena retirement.
fn swift_generic_metadata_cache_locked() !&SwiftGenericMetadataCache {
	if ios_runtime.swift_generic_metadata_arena == 0 {
		page := u64(C.getpagesize()); length := (u64(sizeof(SwiftGenericMetadataCache)) + page - 1) & ~(page - 1)
		allocation := C.mmap(unsafe { nil },usize(length),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
		if allocation == unsafe { voidptr(-1) } { return swift_generic_metadata_failure() }
		ios_runtime.swift_generic_metadata_arena = u64(allocation)
	}
	return unsafe { &SwiftGenericMetadataCache(ios_runtime.swift_generic_metadata_arena) }
}

fn swift_generic_metadata_begin() ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_generic_metadata_retired
		|| ios_runtime.swift_generic_value_retired || ios_runtime.swift_concurrency_retired { return swift_generic_metadata_failure() }
	ios_runtime.swift_generic_metadata_users++
}
fn swift_generic_metadata_end() {
	C.ios_objc_initialize_lock()
	ios_runtime.swift_generic_metadata_users--
	C.ios_objc_initialize_unlock()
}
fn swift_generic_metadata_key(descriptor u64, arguments u64) !SwiftGenericMetadataKey {
	if descriptor == 0 || descriptor & 3 != 0 || descriptor > ~u64(0) - 108 { return swift_generic_metadata_failure() }
	flags := read32(descriptor); kind := flags & 31
	// Version-zero generic value contexts with type keys only. Pack shapes,
	// requirements (including witness equivalence), old extra arguments and
	// context extensions need a separate substitution/completion implementation.
	if kind !in [u32(17),18]! || flags & 0xffffff80 != 0x80 { return swift_generic_metadata_failure() }
	count := u64(swift_generic_value_half(descriptor + 36))
	if count > 64 || swift_generic_value_half(descriptor + 38) != 0
		|| u64(swift_generic_value_half(descriptor + 40)) != count || swift_generic_value_half(descriptor + 42) != 0 {
		return swift_generic_metadata_failure()
	}
	if count != 0 && (arguments == 0 || arguments & 7 != 0 || arguments > ~u64(0) - count * 8) { return swift_generic_metadata_failure() }
	mut key := SwiftGenericMetadataKey{count:count,kind:if kind == 17 { u64(0x200) } else { u64(0x201) }}
	for i in u64(0)..count {
		if unsafe { *(&u8(descriptor + 44 + i)) } != 0x80 { return swift_generic_metadata_failure() }
		value := read64(arguments + i * 8)
		// A nil completer promises complete metadata, but its type arguments
		// must also be transitively complete before publishing state zero.
		swift_metadata_state_checked(0,value) or { return swift_generic_metadata_failure() }
		key.arguments[int(i)] = value
	}
	return key
}
fn swift_generic_metadata_relative(field u64, alignment u64) !u64 {
	delta := i64(i32(read32(field)))
	if delta == 0 || (delta < 0 && field < u64(-delta)) || (delta > 0 && field > ~u64(0) - u64(delta)) { return swift_generic_metadata_failure() }
	target := if delta < 0 { field - u64(-delta) } else { field + u64(delta) }
	if target == 0 || target & (alignment - 1) != 0 || target > ~u64(0) - 16 { return swift_generic_metadata_failure() }
	return target
}
fn swift_generic_metadata_complete_locked(metadata u64) bool {
	if ios_runtime.swift_generic_metadata_arena == 0 || ios_runtime.swift_generic_metadata_retired { return false }
	cache := unsafe { &SwiftGenericMetadataCache(ios_runtime.swift_generic_metadata_arena) }
	for i in u64(0)..ios_runtime.swift_generic_metadata_count {
		if cache.entries[int(i)].phase == 2 && cache.entries[int(i)].metadata == metadata { return true }
	}
	return false
}
fn swift_generic_metadata_result(metadata u64, descriptor u64, key &SwiftGenericMetadataKey) ! {
	if metadata < 8 || metadata & 7 != 0 || metadata > ~u64(0) - 16 - key.count * 8
		|| read64(metadata) != key.kind || read64(metadata + 8) != descriptor { return swift_generic_metadata_failure() }
	swift_enum_tag_single_layout(metadata,0) or { return swift_generic_metadata_failure() }
	for i in u64(0)..key.count {
		if read64(metadata + 16 + i * 8) != key.arguments[int(i)] { return swift_generic_metadata_failure() }
	}
}
fn swift_generic_metadata_checked(request u64, arguments u64, descriptor u64) !SwiftAssociatedMetadata {
	state := request & ~u64(0x100)
	if request > 0x1ff || state !in [u64(0),1,0x3f,0xff]! { return swift_generic_metadata_failure() }
	swift_generic_metadata_begin()!
	defer { swift_generic_metadata_end() }
	key := swift_generic_metadata_key(descriptor,arguments)!
	for {
		C.ios_objc_initialize_lock()
		mut entry := unsafe { &SwiftGenericMetadataEntry(nil) }
		if ios_runtime.swift_generic_metadata_arena != 0 {
			cache := unsafe { &SwiftGenericMetadataCache(ios_runtime.swift_generic_metadata_arena) }
			for i in u64(0)..ios_runtime.swift_generic_metadata_count {
				candidate := unsafe { &cache.entries[int(i)] }
				if candidate.singleton_cache != 0 || candidate.descriptor != descriptor || candidate.count != key.count { continue }
				mut equal := true
				for j in u64(0)..key.count { if candidate.arguments[int(j)] != key.arguments[int(j)] { equal = false; break } }
				if equal { entry = candidate; break }
			}
		}
		if entry != unsafe { nil } {
			if entry.phase == 2 { result := entry.metadata; C.ios_objc_initialize_unlock(); return SwiftAssociatedMetadata{metadata:result} }
			if entry.phase == 3 || entry.owner == u64(C.pthread_self()) { C.ios_objc_initialize_unlock(); return swift_generic_metadata_failure() }
			mutex := unsafe { voidptr(&entry.mutex[0]) }
			C.ios_objc_initialize_unlock()
			// Allocation must finish even for nonblocking metadata requests.
			// Never wait for app code while holding the runtime registry lock.
			C.pthread_mutex_lock(mutex); C.pthread_mutex_unlock(mutex)
			continue
		}
		if ios_runtime.swift_generic_metadata_count == 64 { C.ios_objc_initialize_unlock(); return swift_generic_metadata_failure() }
		pattern := swift_generic_metadata_relative(descriptor + 32,4) or { C.ios_objc_initialize_unlock(); return swift_generic_metadata_failure() }
		if read32(pattern + 4) != 0 || read32(pattern + 8) & 0x1ffffe != 0
			|| u64(read32(pattern + 8) >> 21) != key.kind { C.ios_objc_initialize_unlock(); return swift_generic_metadata_failure() }
		instantiate := swift_generic_metadata_relative(pattern,4) or { C.ios_objc_initialize_unlock(); return swift_generic_metadata_failure() }
		cache := swift_generic_metadata_cache_locked() or { C.ios_objc_initialize_unlock(); return swift_generic_metadata_failure() }
		entry = unsafe { &cache.entries[int(ios_runtime.swift_generic_metadata_count)] }
		if C.ios_sizeof_mutex() > 64 || C.ios_mutex_create(unsafe { &entry.mutex[0] },0) != 0 { C.ios_objc_initialize_unlock(); return swift_generic_metadata_failure() }
		C.pthread_mutex_lock(unsafe { voidptr(&entry.mutex[0]) })
		entry.descriptor = descriptor; entry.count = key.count; entry.arguments = key.arguments
		entry.owner = u64(C.pthread_self()); entry.phase = 1; ios_runtime.swift_generic_metadata_count++
		C.ios_objc_initialize_unlock()
		call := unsafe { SwiftGenericMetadataInstantiate(voidptr(instantiate)) }
		metadata := call(descriptor,arguments,pattern)
		mut valid := true
		swift_generic_metadata_result(metadata,descriptor,unsafe { &key }) or { valid = false }
		C.ios_objc_initialize_lock()
		entry.metadata = metadata; entry.owner = 0; entry.phase = if valid { u64(2) } else { u64(3) }
		C.ios_objc_initialize_unlock()
		C.pthread_mutex_unlock(unsafe { voidptr(&entry.mutex[0]) })
		if !valid { return swift_generic_metadata_failure() }
		return SwiftAssociatedMetadata{metadata:metadata}
	}
	return swift_generic_metadata_failure()
}
fn swift_generic_metadata(request u64, arguments u64, descriptor u64) SwiftAssociatedMetadata {
	return swift_generic_metadata_checked(request,arguments,descriptor) or { panic(err) }
}
fn swift_generic_metadata_stop() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_generic_metadata_users != 0 { panic('iOS: generic metadata users must drain before retirement') }
	ios_runtime.swift_generic_metadata_retired = true
	base := ios_runtime.swift_generic_metadata_arena
	if base == 0 { return }
	cache := unsafe { &SwiftGenericMetadataCache(base) }
	for i in u64(0)..ios_runtime.swift_generic_metadata_count {
		if C.pthread_mutex_destroy(unsafe { voidptr(&cache.entries[int(i)].mutex[0]) }) != 0 { panic('iOS: cannot retire generic metadata mutex') }
	}
	page := u64(C.getpagesize()); length := (u64(sizeof(SwiftGenericMetadataCache)) + page - 1) & ~(page - 1)
	if C.munmap(voidptr(base),usize(length)) != 0 { panic('iOS: cannot retire generic metadata cache') }
	ios_runtime.swift_generic_metadata_arena = 0; ios_runtime.swift_generic_metadata_count = 0
}
