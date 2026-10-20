// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftHeapStorage {
	metadata u64
	size u64
	mask u64
	generation u64
mut:
	deiniting bool
	dictionary_tail bool // Native class deallocation reports its fixed 64-byte header.
}

type SwiftHeapDestroyCall = fn (u64, u64)

fn swift_heap_layout(metadata u64, size u64, mask u64) ! {
	if metadata < 24 || metadata & 7 != 0 || size < 16 || size > 0x7fffffffffffffff
		|| mask >= 0x7fffffffffffffff || (mask + 1) & mask != 0 {
		return error('iOS: invalid Swift heap allocation layout')
	}
	$if !arm64 { return error('iOS: Swift heap destructor ABI requires ARM64') }
	kind := read64(metadata)
	if kind == 0 || kind > 0x7ff {
		// Darwin Swift class metadata, rather than a private buffer descriptor.
		// ObjC reference counting and nonzero instance prefixes need other paths.
		if read64(metadata + 32) & 2 == 0 || unsafe { *(&u32(metadata + 40)) } & 2 == 0 {
			return error('iOS: Objective-C Swift heap classes are not implemented')
		}
		if unsafe { *(&u32(metadata + 44)) } != 0 {
			return error('iOS: Swift heap instance prefixes are not implemented')
		}
	} else if kind != 0x400 && kind != 0x500 {
		return error('iOS: unsupported Swift heap metadata kind')
	}
	if read64(metadata - 16) == 0 { return error('iOS: Swift heap metadata has no destructor') }
}

fn swift_heap_allocate(metadata u64, size u64, mask u64) u64 {
	return swift_heap_allocate_record(metadata, size, mask, false)
}

fn swift_heap_allocate_record(metadata u64, size u64, mask u64, dictionary_tail bool) u64 {
	swift_heap_layout(metadata, size, mask) or { panic(err) }
	// V would promote an ordinary address-taken local to the heap.
	pointer := unsafe { &u64(C.__builtin_alloca(8)) }
	unsafe { *pointer = 0 }
	alignment := if mask < 15 { u64(16) } else { mask + 1 }
	if C.posix_memalign(unsafe { voidptr(pointer) }, usize(alignment), usize(size)) != 0 {
		panic('iOS: cannot allocate Swift heap object')
	}
	owner := unsafe { *pointer }
	unsafe {
		*(&u64(owner)) = metadata
		*(&u64(owner + 8)) = 3
	}
	C.ios_objc_initialize_lock()
	if ios_runtime.swift_heap_sequence == u64(-1) {
		C.ios_objc_initialize_unlock()
		C.free(unsafe { voidptr(owner) })
		panic('iOS: Swift heap allocation generation overflow')
	}
	ios_runtime.swift_heap_sequence++
	ios_runtime.swift_heap[owner] = SwiftHeapStorage{ metadata: metadata, size: size, mask: mask,
		generation: ios_runtime.swift_heap_sequence, dictionary_tail: dictionary_tail }
	C.ios_objc_initialize_unlock()
	// Stored properties are uninitialized; their construction belongs to Swift.
	return owner
}

fn swift_heap_deallocate_checked(owner u64, size u64, mask u64, uninitialized bool) ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	storage := ios_runtime.swift_heap[owner] or { return error('iOS: unregistered Swift heap deallocation') }
	if size != storage.size || mask != storage.mask || read64(owner) != storage.metadata {
		return error('iOS: mismatched Swift heap deallocation layout')
	}
	bits := C.ios_load_pointer(unsafe { &u64(owner + 8) })
	if uninitialized {
		if storage.deiniting || bits != 3 { return error('iOS: uninitialized Swift heap object is not unique') }
	} else if !storage.deiniting || bits != 0x100000003 {
		return error('iOS: Swift heap object is not ready for deallocation')
	}
	ios_runtime.swift_heap.delete(owner)
	C.free(unsafe { voidptr(owner) })
}

fn swift_heap_deallocate(owner u64, size u64, mask u64) {
	swift_heap_deallocate_checked(owner, size, mask, false) or { panic(err) }
}

// Native Dictionary storage's deallocating destructor passes the fixed class
// header (64,7), even for over-aligned tails. Only allocations made by our
// checked copy factory carry this marker; ordinary allocObject stays exact.
fn swift_heap_deallocate_class_checked(owner u64, size u64, mask u64) ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	storage := ios_runtime.swift_heap[owner] or { return swift_dictionary_storage_failure() }
	if storage.dictionary_tail && size == 64 && mask == 7 {
		swift_heap_deallocate_checked(owner, storage.size, storage.mask, false)!
	} else {
		swift_heap_deallocate_checked(owner, size, mask, false)!
	}
}

fn swift_heap_deallocate_class(owner u64, size u64, mask u64) {
	swift_heap_deallocate_class_checked(owner, size, mask) or { panic(err) }
}
fn swift_heap_deallocate_uninitialized(owner u64, size u64, mask u64) {
	swift_heap_deallocate_checked(owner, size, mask, true) or { panic(err) }
}

fn swift_heap_destroy(owner u64, metadata u64, generation u64) ! {
	$if arm64 {
		// The metadata's deallocating destructor takes self in x20 and itself
		// calls deallocObject/ClassInstance. Never read freed bytes after it returns.
		entry := swift_arc_entry(false) + 128
		destroy := unsafe { SwiftHeapDestroyCall(voidptr(entry)) }
		destroy(read64(metadata - 16), owner)
	} $else { return error('iOS: Swift heap destructor ABI requires ARM64') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if storage := ios_runtime.swift_heap[owner] {
		// A reentrant allocation may reuse this address after deallocation.
		if storage.generation == generation && storage.deiniting {
			return error('iOS: Swift heap destructor did not deallocate its object')
		}
	}
}

fn swift_heap_stop() {
	if ios_runtime.swift_heap.len != 0 { panic('iOS: Swift heap objects still owned at shutdown') }
	unsafe { ios_runtime.swift_heap.free() }
}
