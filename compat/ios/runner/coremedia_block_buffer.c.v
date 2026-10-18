// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A contiguous memory block, or a retained slice of one. Fragmented assembly
// uses different APIs and is not advertised by this implementation.
struct CMBlockState {
mut:
	base u64
	block_length u64
	offset u64
	length u64
	owner u64 // A slice's root buffer, retained by ObjHeader.fields[0].
	allocate_proc u64
	free_proc u64
	context u64
	owned bool
	allocating bool
}
type CMBlockAllocate = fn (u64, u64) u64
type CMBlockFree = fn (u64, u64, u64)
fn cm_block_id() u64 { return ios_runtime.names['VinixCMBlockBuffer'] }
fn cm_block_state(object u64) &CMBlockState {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { panic('iOS: expected a live CMBlockBuffer') }
	if header.cls != cm_block_id() || header.cm_block == unsafe { nil } { panic('iOS: expected a live CMBlockBuffer') }
	return header.cm_block
}
fn cm_block_storage(state &CMBlockState) &CMBlockState {
	return if state.owner == 0 { state } else { cm_block_state(state.owner) }
}
fn cm_block_dispose(mut header ObjHeader) {
	mut state := header.cm_block
	if state == unsafe { nil } { return }
	callback := state.free_proc
	state.free_proc = 0
	if state.base != 0 {
		if callback != 0 { unsafe { CMBlockFree(voidptr(callback))(state.context, state.base, state.block_length) } }
		else if state.owned { darwin_free(unsafe { voidptr(state.base) }) }
	}
	header.cm_block = unsafe { nil }
	C.free(state)
}
fn cm_block_wire_word(address u64, size int) u64 {
	// CMBlockBufferCustomBlockSource is packed to four bytes: its pointers
	// start at offsets 4, 12 and 20, even on 64-bit systems. Avoid unaligned loads.
	mut word := u64(0)
	for i in 0 .. size { word |= u64(unsafe { *(&u8(address + u64(i))) }) << u64(i * 8) }
	return word
}
fn cm_block_assure(object u64) i32 {
	if object == 0 { return -12705 }
	mut state := cm_block_storage(cm_block_state(object))
	C.ios_objc_initialize_lock()
	if state.base != 0 { C.ios_objc_initialize_unlock(); return 0 }
	if state.allocating { C.ios_objc_initialize_unlock(); return -12707 }
	state.allocating = true
	C.ios_objc_initialize_unlock()
	// Client code runs outside the runtime lock. Reentrant allocation fails
	// explicitly, while metadata queries remain available to the callback.
	memory := if state.allocate_proc != 0 {
		unsafe { CMBlockAllocate(voidptr(state.allocate_proc))(state.context, state.block_length) }
	} else { u64(C.malloc(usize(state.block_length))) }
	C.ios_objc_initialize_lock()
	state.base = memory
	state.allocating = false
	C.ios_objc_initialize_unlock()
	return if memory == 0 { i32(-12701) } else { i32(0) }
}
fn cm_block_create(allocator u64, memory u64, block_length u64, block_allocator u64, custom u64, offset u64, length u64, flags u32, output &u64) i32 {
	if output == unsafe { nil } { return -12705 }
	unsafe { *output = 0 }
	if block_length == 0 || block_length > 0x7fffffff || length == 0 || offset >= block_length || length > block_length - offset { return -12704 }
	cf_allocator_check(allocator)
	mut allocate_proc := u64(0)
	mut free_proc := u64(0)
	mut context := u64(0)
	mut owned := true
	if custom != 0 {
		if cm_block_wire_word(custom, 4) != 0 { return -12702 }
		allocate_proc = cm_block_wire_word(custom + 4, 8)
		free_proc = cm_block_wire_word(custom + 12, 8)
		context = cm_block_wire_word(custom + 20, 8)
		if free_proc == 0 || (memory == 0 && allocate_proc == 0) { return -12702 }
		owned = false
	} else if block_allocator != 0 && block_allocator != cf_allocator_default() {
		if block_allocator != framework_object('_kCFAllocatorNull') { return -12701 }
		if memory == 0 { return -12701 }
		owned = false
	}
	mut state := unsafe { &CMBlockState(C.calloc(1, sizeof(CMBlockState))) }
	if state == unsafe { nil } { return -12700 }
	state.base = memory; state.block_length = block_length
	state.offset = offset; state.length = length
	state.allocate_proc = allocate_proc; state.free_proc = free_proc
	state.context = context; state.owned = owned
	object := objc_allocate(cm_block_id())
	obj_header(object).cm_block = state
	if flags & 1 != 0 {
		status := cm_block_assure(object)
		if status != 0 { objc_release(object); return status }
	}
	unsafe { *output = object }
	return 0
}
fn cm_block_reference(allocator u64, source u64, offset u64, length u64, flags u32, output &u64) i32 {
	_ = flags // Optimization flags do not change a contiguous slice's bytes.
	if output == unsafe { nil } { return -12705 }
	unsafe { *output = 0 }
	if source == 0 { return -12705 }
	cf_allocator_check(allocator)
	parent := cm_block_state(source)
	if offset >= parent.length { return -12703 }
	size := if length == 0 { parent.length - offset } else { length }
	if size > parent.length - offset { return -12704 }
	mut state := unsafe { &CMBlockState(C.calloc(1, sizeof(CMBlockState))) }
	if state == unsafe { nil } { return -12700 }
	state.owner = if parent.owner == 0 { source } else { parent.owner }
	state.offset = parent.offset + offset; state.length = size
	object := objc_allocate(cm_block_id())
	mut header := obj_header(object)
	header.cm_block = state
	header.fields[0] = objc_retain(state.owner)
	unsafe { *output = object }
	return 0
}
fn cm_block_length(object u64) u64 { return if object == 0 { u64(0) } else { cm_block_state(object).length } }
fn cm_block_pointer(object u64, offset u64, available &u64, total &u64, output &u64) i32 {
	if object == 0 { return -12705 }
	state := cm_block_state(object)
	unsafe { if available != nil { *available = 0 }; if total != nil { *total = state.length }; if output != nil { *output = 0 } }
	if offset >= state.length { return -12703 }
	storage := cm_block_storage(state)
	if storage.base == 0 { return -12707 }
	unsafe { if available != nil { *available = state.length - offset }; if output != nil { *output = storage.base + state.offset + offset } }
	return 0
}
fn cm_block_range(state &CMBlockState, offset u64, length u64) i32 {
	if length == 0 { return -12704 }
	if offset >= state.length { return -12703 }
	if length > state.length - offset { return -12704 }
	return 0
}
fn cm_block_copy(object u64, offset u64, length u64, destination u64) i32 {
	if object == 0 || destination == 0 { return -12705 }
	state := cm_block_state(object)
	status := cm_block_range(state, offset, length)
	if status != 0 { return status }
	storage := cm_block_storage(state)
	if storage.base == 0 { return -12707 }
	C.memmove(unsafe { voidptr(destination) }, unsafe { voidptr(storage.base + state.offset + offset) }, usize(length))
	return 0
}
fn cm_block_replace(source u64, object u64, offset u64, length u64) i32 {
	if object == 0 || source == 0 { return -12705 }
	state := cm_block_state(object)
	status := cm_block_range(state, offset, length)
	if status != 0 { return status }
	allocated := cm_block_assure(object)
	if allocated != 0 { return allocated }
	C.memmove(unsafe { voidptr(cm_block_storage(state).base + state.offset + offset) }, unsafe { voidptr(source) }, usize(length))
	return 0
}
fn cm_block_fill(value u8, object u64, offset u64, length u64) i32 {
	if object == 0 { return -12705 }
	state := cm_block_state(object)
	if offset >= state.length { return -12703 }
	size := if length == 0 { state.length - offset } else { length }
	if size > state.length - offset { return -12704 }
	status := cm_block_assure(object)
	if status != 0 { return status }
	C.memset(unsafe { voidptr(cm_block_storage(state).base + state.offset + offset) }, int(value), usize(size))
	return 0
}
fn cm_block_contiguous(object u64, offset u64, length u64) u8 {
	if object == 0 { return 0 }
	state := cm_block_state(object)
	return u8(offset < state.length && (length == 0 || length <= state.length - offset))
}
fn cm_block_empty(object u64) u8 { if object != 0 { cm_block_state(object) }; return 0 }
fn coremedia_block_symbol(symbol string) ?u64 {
	return match symbol {
		'_CMBlockBufferCreateWithMemoryBlock' { u64(unsafe { voidptr(cm_block_create) }) }
		'_CMBlockBufferCreateWithBufferReference' { u64(unsafe { voidptr(cm_block_reference) }) }
		'_CMBlockBufferGetTypeID' { u64(unsafe { voidptr(cm_block_id) }) }
		'_CMBlockBufferAssureBlockMemory' { u64(unsafe { voidptr(cm_block_assure) }) }
		'_CMBlockBufferGetDataLength' { u64(unsafe { voidptr(cm_block_length) }) }
		'_CMBlockBufferGetDataPointer' { u64(unsafe { voidptr(cm_block_pointer) }) }
		'_CMBlockBufferCopyDataBytes' { u64(unsafe { voidptr(cm_block_copy) }) }
		'_CMBlockBufferReplaceDataBytes' { u64(unsafe { voidptr(cm_block_replace) }) }
		'_CMBlockBufferFillDataBytes' { u64(unsafe { voidptr(cm_block_fill) }) }
		'_CMBlockBufferIsRangeContiguous' { u64(unsafe { voidptr(cm_block_contiguous) }) }
		'_CMBlockBufferIsEmpty' { u64(unsafe { voidptr(cm_block_empty) }) }
		else { none }
	}
}
