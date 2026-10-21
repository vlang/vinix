// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftErrorAllocationFailure {}
fn (_ &SwiftErrorAllocationFailure) msg() string { return 'iOS: unsupported Swift error allocation or lifetime' }
fn (_ &SwiftErrorAllocationFailure) code() int { return 1 }
__global swift_error_allocation_failure_value = SwiftErrorAllocationFailure{}
fn swift_error_allocation_failure() IError { return unsafe { &swift_error_allocation_failure_value } }

struct SwiftErrorStorage {
	metadata u64
	witness u64
	value u64
	size u64
	mask u64
	destroy u64
}

// The box is opaque to Swift clients. Its lifetime uses the existing native
// heap registry, while this record keeps borrowed value metadata/conformance.
fn swift_error_allocate_checked(metadata u64, witness u64, source u64, taking bool) !SwiftArrayAllocation {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_error_allocation_retired || witness == 0 || witness & 7 != 0 {
		return swift_error_allocation_failure()
	}
	layout := swift_dynamic_cast_value_checked(metadata)!
	payload_copy := swift_dynamic_cast_entry(layout, 2)!
	payload_take := swift_dynamic_cast_entry(layout, 4)!
	destroy := swift_dynamic_cast_entry(layout, 1)!
	if source != 0 { swift_dynamic_cast_span(source, layout)! }
	base := swift_error_allocation_arena_checked()!
	mask := if layout.alignment < 16 { u64(15) } else { layout.alignment - 1 }
	tail := (72 + layout.alignment - 1) & ~(layout.alignment - 1)
	size := tail + layout.size
	owner := swift_heap_allocate(base + u64(C.getpagesize()) + 16, size, mask)
	value := owner + tail
	C.ios_objc_initialize_lock()
	ios_runtime.swift_errors[owner] = SwiftErrorStorage{metadata,witness,value,size,mask,destroy}
	C.ios_objc_initialize_unlock()
	// Null source leaves construction to the caller. Otherwise the value
// witness runs without a registry lock, and ownership follows copy vs take.
	if source != 0 {
		initialize := unsafe { SwiftDynamicCastCopy(voidptr(if taking { payload_take } else { payload_copy })) }
		initialize(value, source, metadata)
	}
	return SwiftArrayAllocation{owner:owner,bytes:value}
}

fn swift_error_allocate(metadata u64, witness u64, source u64, taking bool) SwiftArrayAllocation {
	return swift_error_allocate_checked(metadata,witness,source,taking) or { panic(err) }
}

fn swift_error_is_box(owner u64) bool {
	if ios_runtime == unsafe { nil } || owner == 0 { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return owner in ios_runtime.swift_errors
}

fn swift_error_retain(owner u64) u64 {
	if swift_error_is_box(owner) { return swift_retain(owner) }
	return objc_retain(owner)
}

fn swift_error_release(owner u64) {
	if swift_error_is_box(owner) { swift_release(owner); return }
	objc_release(owner)
}

fn swift_error_allocation_project_checked(owner u64, output &SwiftErrorValue) !bool {
	if ios_runtime == unsafe { nil } { return swift_error_allocation_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	storage := ios_runtime.swift_errors[owner] or { return false }
	heap := ios_runtime.swift_heap[owner] or { return swift_error_allocation_failure() }
	if heap.deiniting || read64(owner) != heap.metadata { return swift_error_allocation_failure() }
	unsafe { *output = SwiftErrorValue{value:storage.value,metadata:storage.metadata,witness:storage.witness} }
	return true
}

fn swift_error_allocation_dispose(owner u64) {
	C.ios_objc_initialize_lock()
	storage := ios_runtime.swift_errors[owner] or { panic('iOS: unregistered Swift error destructor') }
	heap := ios_runtime.swift_heap[owner] or { panic('iOS: Swift error has no heap owner') }
	if !heap.deiniting { panic('iOS: live Swift error passed to destructor') }
	C.ios_objc_initialize_unlock()
	destroy := unsafe { SwiftDynamicCastDestroy(voidptr(storage.destroy)) }
	destroy(storage.value,storage.metadata)
	C.ios_objc_initialize_lock()
	ios_runtime.swift_errors.delete(owner)
	swift_heap_deallocate(owner,storage.size,storage.mask)
	C.ios_objc_initialize_unlock()
}

fn swift_error_allocation_arena_checked() !u64 {
	$if !arm64 { return swift_error_allocation_failure() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_error_allocation_retired { return swift_error_allocation_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_error_allocation_arena != 0 { return ios_runtime.swift_error_allocation_arena }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil },page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
	if allocation == unsafe { voidptr(-1) } { return swift_error_allocation_failure() }
	base := u64(allocation);data := base+u64(page)
	// Native heap deallocating destructor: Swift Self x20 -> ordinary C x0.
	for i,op in [u32(0xaa1403e0),0x58000070,0xd61f0200,0xd503201f]! { write32(base+u64(i*4),op) }
	unsafe { *(&u64(base+16))=u64(voidptr(swift_error_allocation_dispose));*(&u64(data))=base;*(&u64(data+16))=0x400 }
	C.__builtin___clear_cache(allocation,voidptr(base+24))
	if C.mprotect(allocation,page,C.PROT_READ|C.PROT_EXEC)!=0 || C.mprotect(voidptr(data),page,C.PROT_READ)!=0 {
		C.munmap(allocation,page*2);return swift_error_allocation_failure()
	}
	ios_runtime.swift_error_allocation_arena=base
	return base
}

fn swift_error_allocation_stop() {
	if ios_runtime.swift_errors.len != 0 { panic('iOS: Swift errors still owned at shutdown') }
	ios_runtime.swift_error_allocation_retired=true
	unsafe { ios_runtime.swift_errors.free() }
	if ios_runtime.swift_error_allocation_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_error_allocation_arena),usize(C.getpagesize())*2)!=0 { panic('iOS: cannot retire Swift error allocation metadata') }
		ios_runtime.swift_error_allocation_arena=0
	}
}
