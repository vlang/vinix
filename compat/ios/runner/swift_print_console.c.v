// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Borrow a registered Array<Any> tail. Registration precedes every owner read;
// native storage classes additionally need file-backed metadata and the exact
// imported declaration/Any argument. Generic class instantiation is separate.
// Caller holds the recursive registry lock and a live immutable Array borrow.
fn swift_print_console_array(owner u64) !SwiftStringBytes {
	if owner != 0 && owner == ios_runtime.swift_empty_array {
		return SwiftStringBytes{address: owner + 32}
	}
	if owner == 0 || owner & 7 != 0 { return swift_print_failure() }
	mut capacity := u64(0)
	any := if ios_runtime.swift_error_arena == 0 { u64(0) } else {
		ios_runtime.swift_error_arena + u64(C.getpagesize()) + 456
	}
	if storage := ios_runtime.swift_arrays[owner] {
		if any == 0 || storage.element != any || storage.stride != 32 || storage.tail != 32
			|| storage.verbatim || read64(owner) != u64(&swift_array_storage_descriptor) {
			return swift_print_failure()
		}
		capacity = storage.capacity
	} else if storage := ios_runtime.swift_heap[owner] {
		metadata := storage.metadata
		if storage.deiniting || storage.size < 32 || any == 0 || ios_runtime.swift_array_arena == 0
			|| !swift_print_image_range(metadata, 152) || read64(owner) != metadata
			|| read64(metadata + 32) & 2 == 0 || read32(metadata + 40) & 2 == 0
			|| read32(metadata + 48) != 32
			|| read64(metadata + 64) != ios_runtime.swift_array_arena + u64(C.getpagesize()) + 320
			|| read64(metadata + 144) != any { return swift_print_failure() }
		capacity = (storage.size - 32) / 32
	} else { return swift_print_failure() }
	count := read64(owner + 16)
	flags := read64(owner + 24)
	if flags & 1 != 0 || flags >> 1 > capacity || count > flags >> 1 || count > 512 {
		return swift_print_failure()
	}
	return SwiftStringBytes{owner + 32, count}
}

// Prepare one owned byte message before stdout locking. The stack holds owned
// formatted Strings and their spans; every partial failure releases them.
// No stream operation or user printing witness runs under the registry lock.
fn swift_print_console_render(owner u64, separator SwiftStringWords, terminator SwiftStringWords) !SwiftStringBytes {
	swift_print_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_print_active()!
	items := swift_print_console_array(owner)!
	arguments := u64(C.__builtin_alloca(32))
	scratch := u64(C.__builtin_alloca(32))
	unsafe {
		*(&SwiftStringWords(arguments)) = separator
		*(&SwiftStringWords(arguments + 16)) = terminator
	}
	// An unused separator is never opened, matching native zero/one-item print.
	sep := if items.count > 1 { swift_replace_bytes(arguments, scratch)! } else { SwiftStringBytes{} }
	end := swift_replace_bytes(arguments + 16, scratch + 16)!
	mut length := end.count
	if items.count > 1 {
		if sep.count > (1048576 - length) / (items.count - 1) { return swift_print_failure() }
		length += sep.count * (items.count - 1)
	}
	words := u64(C.__builtin_alloca(512 * 16))
	spans := u64(C.__builtin_alloca(512 * 16))
	mut held := u64(0)
	defer { for i in u64(0) .. held { swift_bridge_release(read64(words + i * 16 + 8)) } }
	for i in u64(0) .. items.count {
		value := items.address + i * 32
		text := swift_print_value_checked(value, read64(value + 24))!
		slot := words + i * 16
		unsafe { *(&SwiftStringWords(slot)) = text }
		held++
		bytes := swift_string_bytes(text, slot)!
		if bytes.count > 1048576 - length { return swift_print_failure() }
		length += bytes.count
		unsafe { *(&SwiftStringBytes(spans + i * 16)) = bytes }
	}
	output := u64(C.malloc(usize(length + 1)))
	if output == 0 { return swift_print_failure() }
	mut offset := u64(0)
	for i in u64(0) .. items.count {
		if i != 0 && sep.count != 0 {
			C.memcpy(voidptr(output + offset), voidptr(sep.address), usize(sep.count))
			offset += sep.count
		}
		bytes := unsafe { *(&SwiftStringBytes(spans + i * 16)) }
		if bytes.count != 0 { C.memcpy(voidptr(output + offset), voidptr(bytes.address), usize(bytes.count)) }
		offset += bytes.count
	}
	if end.count != 0 { C.memcpy(voidptr(output + offset), voidptr(end.address), usize(end.count)) }
	unsafe { *(&u8(output + length)) = 0 }
	return SwiftStringBytes{output, length}
}

// Swift's public variadic print passes Array<Any> and two String pairs in
// x0...x4. All inputs are borrowed, with no indirect result or generic context.
fn swift_print_console_checked(owner u64, first u64, second u64, last u64, tail u64) ! {
	message := swift_print_console_render(owner, SwiftStringWords{first, second}, SwiftStringWords{last, tail})!
	defer { C.free(voidptr(message.address)) }
	sink := C.ios_host_stdio(1)
	C.flockfile(sink)
	defer { C.funlockfile(sink) }
	// Native print has no error result for a failed stdio write.
	C.fwrite(voidptr(message.address), 1, usize(message.count), sink)
}
fn swift_print_console(owner u64, first u64, second u64, last u64, tail u64) {
	swift_print_console_checked(owner, first, second, last, tail) or { panic(err) }
}
fn swift_print_console_symbol(symbol string) ?u64 {
	if symbol != '_$ss5print_9separator10terminatoryypd_S2StF' { return none }
	swift_print_active() or { return none }
	swift_any_full_metadata()
	return u64(unsafe { voidptr(swift_print_console) })
}
