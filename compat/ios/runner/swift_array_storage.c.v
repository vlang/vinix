// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftArrayAllocation {
	owner u64
	bytes u64
}

type SwiftElementDestroy = fn (u64, u64)

struct SwiftArrayStorage {
	element u64
	stride u64
	tail u64
	capacity u64
	destroy u64 // Zero for POD; otherwise Element's actual destroy witness.
}

struct SwiftArrayLayout {
	storage SwiftArrayStorage
	alignment u64
	total u64
}

// Owned storage uses the measured HeapObject + ArrayBody + aligned tail
// layout. This private descriptor is not Swift class metadata. Reflection,
// class casts, ObjC bridging and native storage-class accessors are unsupported.
struct SwiftArrayStorageDescriptor {
	name &char = c'Vinix typed Swift Array storage'
	header_size u64 = 32
}
__global swift_array_storage_descriptor = SwiftArrayStorageDescriptor{}

fn swift_array_layout(count i64, element u64) !SwiftArrayLayout {
	if count < 0 || element < 8 { return error('iOS: invalid Swift Array allocation') }
	kind := read64(element)
	// Class and class-constrained existential storage needs a different class
	// and the verbatim ObjC bridging flag. Reject it before allocating.
	if kind !in [u64(0x200), 0x201, 0x202, 0x300, 0x301, 0x302, 0x303, 0x304, 0x306]! {
		return error('iOS: Swift reference-type Array storage is not implemented')
	}
	if kind == 0x303 && unsafe { *(&u32(element + 8)) } & 0x80000000 == 0 {
		return error('iOS: Swift class-constrained Array storage is not implemented')
	}
	witness := read64(element - 8)
	if witness == 0 { return error('iOS: Swift Array requires complete Element witnesses') }
	size := read64(witness + 64)
	stride := read64(witness + 72)
	flags := unsafe { *(&u32(witness + 80)) }
	alignment := u64(flags & 0xff) + 1
	if flags & 0x00400000 != 0 || alignment & (alignment - 1) != 0
		|| stride == 0 || size > stride || stride & (alignment - 1) != 0 {
		return error('iOS: invalid Swift Array Element layout')
	}
	tail := (u64(32) + alignment - 1) & ~(alignment - 1)
	if u64(count) > (u64(0x7fffffffffffffff) - tail) / stride {
		return error('iOS: Swift Array allocation size overflow')
	}
	destroy := if flags & 0x10000 != 0 { read64(witness + 8) } else { u64(0) }
	if flags & 0x10000 != 0 && destroy == 0 { return error('iOS: Swift Array requires an Element destroy witness') }
	return SwiftArrayLayout{
		storage: SwiftArrayStorage{ element: element, stride: stride, tail: tail,
			capacity: u64(count), destroy: destroy }
		alignment: if alignment < 16 { u64(16) } else { alignment }
		total: tail + u64(count) * stride
	}
}

fn swift_array_empty() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_empty_array != 0 { return ios_runtime.swift_empty_array }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { panic('iOS: cannot allocate empty Swift Array') }
	// Native empty storage is only eight-byte aligned. Its element pointer is
	// owner + aligned header size, even for over-aligned, zero-length tails.
	owner := u64(allocation) + 8
	unsafe {
		*(&u64(owner)) = u64(&swift_array_storage_descriptor)
		*(&u64(owner + 8)) = 0x80000004ffffffff // Immortal, never unique.
		*(&u64(owner + 16)) = 0
		*(&u64(owner + 24)) = 1
	}
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page)
		panic('iOS: cannot seal empty Swift Array')
	}
	ios_runtime.swift_empty_array = owner
	return owner
}

fn swift_array_allocate(count i64, element u64) SwiftArrayAllocation {
	layout := swift_array_layout(count, element) or { panic(err) }
	if count == 0 {
		owner := swift_array_empty()
		return SwiftArrayAllocation{ owner: owner, bytes: owner + layout.storage.tail }
	}
	// Keep the out parameter on the stack: V otherwise promotes its address.
	pointer := unsafe { &u64(C.__builtin_alloca(8)) }
	unsafe { *pointer = 0 }
	if C.posix_memalign(unsafe { voidptr(pointer) }, usize(layout.alignment), usize(layout.total)) != 0 {
		panic('iOS: cannot allocate Swift Array storage')
	}
	owner := unsafe { *pointer }
	unsafe {
		*(&u64(owner)) = u64(&swift_array_storage_descriptor)
		*(&u64(owner + 8)) = 3
		*(&u64(owner + 16)) = u64(count)
		*(&u64(owner + 24)) = u64(count) << 1
	}
	C.ios_objc_initialize_lock()
	ios_runtime.swift_arrays[owner] = layout.storage
	C.ios_objc_initialize_unlock()
	// The caller must initialize every live element before releasing storage.
	// No zeroing substitutes for constructing arbitrary values.
	return SwiftArrayAllocation{ owner: owner, bytes: owner + layout.storage.tail }
}

fn swift_array_dispose(owner u64, storage SwiftArrayStorage) {
	count := read64(owner + 16)
	if count > storage.capacity { panic('iOS: corrupt Swift Array count during destruction') }
	if storage.destroy != 0 {
		destroy := unsafe { SwiftElementDestroy(voidptr(storage.destroy)) }
		for i in u64(0) .. count { destroy(owner + storage.tail + i * storage.stride, storage.element) }
	}
	C.free(unsafe { voidptr(owner) })
}

fn swift_array_storage_stop() {
	if ios_runtime.swift_arrays.len != 0 { panic('iOS: Swift Arrays still owned at shutdown') }
	unsafe { ios_runtime.swift_arrays.free() }
	if ios_runtime.swift_empty_array != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_empty_array - 8) }, usize(C.getpagesize())) != 0 {
			panic('iOS: cannot retire empty Swift Array')
		}
		ios_runtime.swift_empty_array = 0
	}
}
