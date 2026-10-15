// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDataWords {
	first  u64
	second u64
}

fn swift_data_storage_free(bytes u64, _count u64) {
	C.free(voidptr(bytes))
}

fn swift_data_storage_destroy(owner u64) {
	swift_data_storage_free(read64(owner + 16), read64(owner + 24))
	swift_heap_deallocate(owner, 65, 7)
}

fn swift_data_emit(code u64, data u64) {
	// The private storage descriptor uses the ordinary Swift heap lifetime.
	// Its deallocating destructor receives Self in x20, rather than C's x0.
	write32(code + 960, 0xaa1403e0)
	write32(code + 964, 0x58000070)
	write32(code + 968, 0xd61f0200)
	unsafe {
		*(&u64(code + 976)) = u64(voidptr(swift_data_storage_destroy))
		*(&u64(data + 384)) = code + 960
		*(&u64(data + 400)) = 0x400
	}
}

fn swift_data_reference_checked(object u64) !SwiftDataWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift Data reference outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Validate the registry before reading isa or a borrowed byte span. Arbitrary
	// NSData subclasses may override native _bridgingCopy:length: semantics.
	if object !in ios_runtime.objects {
		return error('iOS: Swift Data reference requires live registered NSData')
	}
	if read64(object) !in [ios_runtime.names['NSData'], ios_runtime.names['NSMutableData'],
		ios_runtime.names['_NSZeroData'], ios_runtime.names['_NSInlineData'],
		ios_runtime.names['Foundation.__NSSwiftData']]! {
		return error('iOS: Swift Data reference requires built-in NSData or NSMutableData')
	}
	count := data_length(object)
	if count > 16777216 {
		return error('iOS: Swift Data reference exceeds supported NSData length')
	}
	if count == 0 { return SwiftDataWords{ second: u64(0xc000000000000000) } }
	bytes := data_pointer(object)
	if bytes == 0 { return error('iOS: Swift Data reference requires readable NSData bytes') }
	if count <= 14 {
		inline_value := u64(C.__builtin_alloca(16))
		C.memset(voidptr(inline_value), 0, 16)
		C.memcpy(voidptr(inline_value), voidptr(bytes), usize(count))
		return SwiftDataWords{ first: read64(inline_value), second: read64(inline_value + 8) | (count << 48) }
	}
	// Built-in native NSData/NSMutableData both snapshot into independently
	// owned storage. Neither the borrowed source nor its buffer is retained.
	copy_bytes := u64(C.malloc(usize(count)))
	if copy_bytes == 0 { return error('iOS: cannot allocate Swift Data bytes') }
	C.memcpy(voidptr(copy_bytes), voidptr(bytes), usize(count))
	metadata := swift_foundation_arena() + u64(C.getpagesize()) + 400
	owner := swift_heap_allocate(metadata, 65, 7)
	C.memset(voidptr(owner + 16), 0, 49)
	unsafe {
		*(&u64(owner + 16)) = copy_bytes
		*(&u64(owner + 24)) = count
		*(&u64(owner + 48)) = u64(voidptr(swift_data_storage_free))
	}
	return SwiftDataWords{ first: count << 32, second: owner | u64(0x4000000000000000) }
}

fn swift_data_reference(object u64) SwiftDataWords {
	return swift_data_reference_checked(object) or { panic(err) }
}

// Internal destruction for values produced by referencing built-in NSData.
// Data metadata, general value witnesses and large-range values are separate
// profiles; publishing this constructor does not expose those unsupported APIs.
fn swift_data_reference_destroy(value u64, _metadata u64) {
	second := read64(value + 8)
	match second >> 62 {
		0, 3 {}
		1 { swift_release(second & u64(0x3fffffffffffffff)) }
		else { panic('iOS: large-range Swift Data destruction is not implemented') }
	}
}
