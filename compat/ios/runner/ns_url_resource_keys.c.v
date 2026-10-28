// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The capacity cells use padding after the creation-date text. Keep the
// existing cells and CFSTR records in place as the resource-key table grows.
fn ns_url_resource_key_cell_offset(index int) u64 {
	cells := [u64(0), 8, 16, 24, 96, 104, 112]!
	return cells[index]
}

// Native NSURL and CFURL share an NSString pointer cell for each resource key.
// Filesystem metadata reads and backup-exclusion writes are implemented in
// ns_url_resource.c.v. Other writable resource keys remain outside the profile.
fn ns_url_resource_key_symbol(symbol string) ?u64 {
	index := match symbol {
		'_NSURLCreationDateKey', '_kCFURLCreationDateKey' { 0 }
		'_NSURLFileSizeKey', '_kCFURLFileSizeKey' { 1 }
		'_NSURLIsExcludedFromBackupKey', '_kCFURLIsExcludedFromBackupKey' { 2 }
		'_NSURLIsRegularFileKey', '_kCFURLIsRegularFileKey' { 3 }
		'_NSURLVolumeAvailableCapacityForImportantUsageKey', '_kCFURLVolumeAvailableCapacityForImportantUsageKey' { 4 }
		'_NSURLVolumeAvailableCapacityKey', '_kCFURLVolumeAvailableCapacityKey' { 5 }
		'_NSURLVolumeTotalCapacityKey', '_kCFURLVolumeTotalCapacityKey' { 6 }
		else { return none }
	}
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.url_resource_keys_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate URL resource keys') }
		base := u64(arena)
		objects := [u64(32), 128, 192, 256, 320, 416, 480]!
		bytes := [u64(64), 160, 224, 288, 352, 448, 512]!
		texts := ['NSURLCreationDateKey', 'NSURLFileSizeKey', 'NSURLIsExcludedFromBackupKey', 'NSURLIsRegularFileKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey', 'NSURLVolumeAvailableCapacityKey', 'NSURLVolumeTotalCapacityKey']!
		for i in 0 .. 7 {
			object := base + objects[i]
			data := base + bytes[i]
			text := texts[i]
			unsafe {
				*(&u64(base + ns_url_resource_key_cell_offset(i))) = object
				*(&u64(object)) = ios_runtime.names['NSString']
				*(&u64(object + 8)) = 0x7c8
				*(&u64(object + 16)) = data
				*(&u64(object + 24)) = u64(text.len)
				C.memcpy(voidptr(data), text.str, usize(text.len))
			}
			ios_runtime.constants[object] = true
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal URL resource keys') }
		ios_runtime.url_resource_keys_arena = base
	}
	return ios_runtime.url_resource_keys_arena + ns_url_resource_key_cell_offset(index)
}

// Pool callbacks, collections and Swift contexts can still borrow these keys.
// Retire their registrations and page only after those users have drained.
fn ns_url_resource_keys_stop() {
	arena := ios_runtime.url_resource_keys_arena
	if arena == 0 { return }
	for i in 0 .. 7 { ios_runtime.constants.delete(read64(arena + ns_url_resource_key_cell_offset(i))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire URL resource keys') }
	ios_runtime.url_resource_keys_arena = 0
}
