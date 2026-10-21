// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftBoxFailure {}
fn (_ &SwiftBoxFailure) msg() string { return 'iOS: unsupported Swift value box or lifetime' }
fn (_ &SwiftBoxFailure) code() int { return 1 }
__global swift_box_failure_value = SwiftBoxFailure{}
fn swift_box_failure() IError { return unsafe { &swift_box_failure_value } }

struct SwiftBoxMetadata {
	arena u64
	metadata u64
	type_metadata u64
	size u64
	mask u64
	offset u64
	copy u64
	destroy u64
}

// Value metadata and witnesses are borrowed immutable records. Generic box
// metadata is canonical per value type, and stays mapped until heap teardown.
fn swift_box_metadata_checked(value SwiftDynamicCastValue, copy u64, destroy u64) !SwiftBoxMetadata {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if cached := ios_runtime.swift_box_metadata[value.metadata] { return cached }
	page := usize(C.getpagesize())
	if ios_runtime.swift_box_code == 0 {
		code := C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
		if code == unsafe { voidptr(-1) } { return swift_box_failure() }
		base := u64(code)
		// Heap deallocating destructor: Swift self in x20 -> C x0.
		for i, op in [u32(0xaa1403e0),0x58000070,0xd61f0200,0xd503201f]! { write32(base+u64(i*4),op) }
		unsafe { *(&u64(base+16))=u64(voidptr(swift_box_dispose)) }
		C.__builtin___clear_cache(code,voidptr(base+24))
		if C.mprotect(code,page,C.PROT_READ|C.PROT_EXEC)!=0 { C.munmap(code,page);return swift_box_failure() }
		ios_runtime.swift_box_code=base
	}
	allocation := C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
	if allocation == unsafe { voidptr(-1) } { return swift_box_failure() }
	arena := u64(allocation); metadata := arena+24
	offset := (16+value.alignment-1)&~(value.alignment-1)
	box := SwiftBoxMetadata{arena,metadata,value.metadata,offset+value.size,(value.alignment-1)|7,offset,copy,destroy}
	unsafe {
		*(&u64(metadata-16))=ios_runtime.swift_box_code
		*(&u64(metadata))=0x500 // HeapGenericLocalVariableMetadata.
		*(&u64(metadata+16))=value.metadata
	}
	write32(metadata+8,u32(offset))
	if C.mprotect(allocation,page,C.PROT_READ)!=0 { C.munmap(allocation,page);return swift_box_failure() }
	ios_runtime.swift_box_metadata[value.metadata]=box
	return box
}

fn swift_box_unique_checked(buffer u64, metadata u64, mask u64) !SwiftArrayAllocation {
	$if !arm64 { return swift_box_failure() }
	if ios_runtime == unsafe { nil }  ||  ios_runtime.swift_concurrency_retired  ||  ios_runtime.swift_box_retired
		 ||  buffer == 0  ||  buffer&7!=0  ||  buffer>~u64(0)-8 { return swift_box_failure() }
	value := swift_dynamic_cast_value_checked(metadata)!
	if mask!=value.alignment-1 { return swift_box_failure() }
	copy := swift_dynamic_cast_entry(value,2)!
	destroy := swift_dynamic_cast_entry(value,1)!
	offset := (16+mask)&~mask
	owner := read64(buffer)
	C.ios_objc_initialize_lock()
	heap := ios_runtime.swift_heap[owner] or { C.ios_objc_initialize_unlock();return swift_box_failure() }
	if heap.deiniting  ||  owner&mask!=0  ||  heap.size<offset+value.size  ||  read64(owner)!=heap.metadata
		 ||  read64(heap.metadata) !in [u64(0x400),0x500]! {
		C.ios_objc_initialize_unlock();return swift_box_failure()
	}
	bits := C.ios_load_pointer(unsafe { &u64(owner+8) })
	if bits&0x80000001ffffffff!=3 { C.ios_objc_initialize_unlock();return swift_box_failure() }
	unique := swift_is_unique_native(owner)
	C.ios_objc_initialize_unlock()
	if unique { return SwiftArrayAllocation{owner:owner,bytes:owner+offset} }
	box := swift_box_metadata_checked(value,copy,destroy)!
	new_owner := swift_heap_allocate(box.metadata,box.size,box.mask)
	initialize := unsafe { SwiftDynamicCastCopy(voidptr(box.copy)) }
	// Witnesses may reenter the runtime; no registry lock spans callbacks.
	initialize(new_owner+box.offset,owner+offset,metadata)
	unsafe { *(&u64(buffer))=new_owner }
	swift_release(owner)
	return SwiftArrayAllocation{owner:new_owner,bytes:new_owner+box.offset}
}

fn swift_box_unique(buffer u64, metadata u64, mask u64) SwiftArrayAllocation {
	return swift_box_unique_checked(buffer,metadata,mask) or { panic(err) }
}

fn swift_box_dispose(owner u64) {
	C.ios_objc_initialize_lock()
	heap := ios_runtime.swift_heap[owner] or { panic('iOS: unregistered Swift value box destructor') }
	box := ios_runtime.swift_box_metadata[read64(heap.metadata+16)] or { panic('iOS: unknown Swift value box metadata') }
	if !heap.deiniting  ||  heap.metadata!=box.metadata  ||  heap.size!=box.size  ||  heap.mask!=box.mask {
		panic('iOS: mismatched Swift value box destructor')
	}
	C.ios_objc_initialize_unlock()
	destroy := unsafe { SwiftDynamicCastDestroy(voidptr(box.destroy)) }
	destroy(owner+box.offset,box.type_metadata)
	swift_heap_deallocate(owner,box.size,box.mask)
}

// Any's existing canonical factories can also receive a generic box after
// makeBoxUnique. Accept only our cached descriptor with the exact value type.
fn swift_box_matches(heap SwiftHeapStorage, metadata u64, size u64) bool {
	box := ios_runtime.swift_box_metadata[metadata] or { return false }
	return heap.metadata==box.metadata  &&  heap.size==size+16  &&  heap.size==box.size
		 &&  heap.mask==7  &&  box.offset==16
}

fn swift_box_stop() {
	ios_runtime.swift_box_retired=true
	page := usize(C.getpagesize())
	for _, box in ios_runtime.swift_box_metadata {
		if C.munmap(voidptr(box.arena),page)!=0 { panic('iOS: cannot retire Swift value box metadata') }
	}
	unsafe { ios_runtime.swift_box_metadata.free() }
	if ios_runtime.swift_box_code!=0 {
		if C.munmap(voidptr(ios_runtime.swift_box_code),page)!=0 { panic('iOS: cannot retire Swift value box destructor') }
		ios_runtime.swift_box_code=0
	}
}
