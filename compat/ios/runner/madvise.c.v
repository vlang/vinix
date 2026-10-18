// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.madvise(voidptr, usize, i32) i32
fn C.sscanf(&char, &char, ...voidptr) i32

// Read only the fixed prefix of each maps line. No mapping registry, guest
// pointer dereference or retained allocation is needed. The caller holds the
// same namespace lock as BSD unmap/protect/fixed-map and Mach mapping changes.
// Check the entire extent before discarding anything, including mixed regions.
fn darwin_advice_range(start u64, end u64, advice i32) i32 {
	file := C.fopen(c'/proc/self/maps', c'r')
	if file == unsafe { nil } { return 45 }
	defer { C.fclose(file) }
	return darwin_advice_maps(file, start, end, advice)
}

fn darwin_advice_maps(file voidptr, start u64, end u64, advice i32) i32 {
	mut line := [512]char{}
	mut cursor := start
	mut continuation := false
	mut denied := false
	mut unsupported := false
	for C.fgets(unsafe { &line[0] }, 512, file) != unsafe { nil } {
		mut length := 0
		for length < 511 && line[length] != 0 { length++ }
		previous := continuation
		continuation = length == 511 && line[length - 1] != char(`\n`)
		if previous { continue }
		mut low := u64(0); mut high := u64(0); mut offset := u64(0); mut inode := u64(0)
		mut major := u32(0); mut minor := u32(0); mut permissions := [5]char{}
		fields := C.sscanf(unsafe { &line[0] }, c'%16llx-%16llx %4s %16llx %x:%x %llu',
			unsafe { voidptr(&low) }, unsafe { voidptr(&high) }, unsafe { voidptr(&permissions[0]) },
			unsafe { voidptr(&offset) }, unsafe { voidptr(&major) }, unsafe { voidptr(&minor) }, unsafe { voidptr(&inode) })
		if fields != 7 || low >= high { return 45 }
		if high <= cursor { continue }
		if low > cursor { return 22 } // Darwin reports a hole in the requested extent as EINVAL.
		if advice == 3 && permissions[0] != char(`r`) { denied = true }
		if advice == 7 && permissions[1] != char(`w`) { denied = true }
		if advice == 5 || advice == 7 {
			// Linux DONTNEED on a private file map discards dirty data back to
			// its file; on a shared map it cannot release the backing object.
			if permissions[3] != char(`p`) || inode != 0 || major != 0 || minor != 0 { unsupported = true }
		}
		cursor = if high < end { high } else { end }
		if cursor == end { break }
	}
	if cursor != end { return if C.ferror(file) != 0 { 45 } else { 22 } }
	if denied { return 1 }
	if unsupported { return 45 }
	return 0
}

fn darwin_madvise(address voidptr, size usize, advice i32) i32 {
	$if macos { return C.madvise(address, size, advice) }
	$if linux {
		saved_errno := unsafe { *C.ios_errno_address() }
		start := u64(address)
		page := mach_page_size()
		// Darwin rounds both ends outwards, accepts unaligned addresses and
		// accepts empty ranges even at invalid addresses. Overflow precedes
		// advice validation. None of these checks reads the guest's memory.
		if u64(size) > ~u64(0) - start || (size != 0 && start + u64(size) > ~u64(0) - (page - 1)) {
			darwin_set_errno(22); return -1
		}
		if advice < 0 || advice > 11 { darwin_set_errno(22); return -1 }
		if advice in [i32(6), 9, 10, 11] { darwin_set_errno(45); return -1 }
		if size == 0 { darwin_set_errno(saved_errno); return 0 }
		low := start & ~(page - 1)
		end := (start + u64(size) + page - 1) & ~(page - 1)
		C.ios_mach_threads_lock()
		defer { C.ios_mach_threads_unlock() }
		if (advice == 5 || advice == 7) && mach_mapping_overlaps(low, end - low) { darwin_set_errno(45); return -1 }
		validation := darwin_advice_range(low, end, advice)
		if validation != 0 { darwin_set_errno(validation); return -1 }
		// Darwin DONTNEED is a non-destructive hint, unlike Linux advice 4.
		// FREE/REUSABLE permit loss of contents: eagerly discard so REUSE
		// never leaves a Linux lazy-free page eligible for later reclamation.
		// REUSE needs no state reversal after that eager release.
		native := match advice { 4 { i32(20) } 5, 7 { i32(4) } 8 { i32(0) } else { advice } }
		result := C.madvise(voidptr(low), usize(end - low), native)
		if result != 0 { darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() })); return -1 }
		darwin_set_errno(saved_errno)
		return 0
	}
	darwin_set_errno(45)
	return -1
}
