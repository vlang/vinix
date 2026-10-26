// SPDX-License-Identifier: GPL-2.0-or-later
// Apple block ABI: stack promotion and compiler-generated capture lifetimes.
module main

type BlockCopyHelper = fn (u64, u64)
type BlockDisposeHelper = fn (u64)
type BlockVoid = fn (u64)
type BlockBool = fn (u64, bool)

fn block_isa(index int) u64 { return u64(unsafe { &ios_runtime.block_isa[index] }) }

fn is_block(object u64) bool {
	if object == 0 { return false }
	isa := read64(object)
	return isa == block_isa(0) || isa == block_isa(1) || isa == block_isa(2)
}

fn block_copy(block u64) u64 {
	if block == 0 { return 0 }
	flags := read32(block + 8)
	if flags & (u32(1) << 28) != 0 { return block }
	C.ios_objc_initialize_lock()
	if refs := ios_runtime.block_refs[block] {
		ios_runtime.block_refs[block] = refs + 1
		C.ios_objc_initialize_unlock()
		return block
	}
	C.ios_objc_initialize_unlock()
	descriptor := read64(block + 24)
	size := read64(descriptor + 8)
	if size < 32 || size > 1024 * 1024 { panic('iOS: invalid block size') }
	copied := u64(C.malloc(usize(size)))
	if copied == 0 { panic('iOS: cannot copied block') }
	unsafe {
		C.memcpy(voidptr(copied), voidptr(block), usize(size))
		*(&u64(copied)) = block_isa(2)
	}
	C.ios_objc_initialize_lock()
	ios_runtime.block_refs[copied] = 1
	C.ios_objc_initialize_unlock()
	if flags & (u32(1) << 25) != 0 {
		helper := unsafe { BlockCopyHelper(voidptr(read64(descriptor + 16))) }
		helper(copied, block)
	}
	return copied
}

fn block_retain(block u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if refs := ios_runtime.block_refs[block] { ios_runtime.block_refs[block] = refs + 1 }
	return block
}

fn block_release(block u64) {
	C.ios_objc_initialize_lock()
	refs := ios_runtime.block_refs[block] or { C.ios_objc_initialize_unlock(); return } // Stack/global are immortal.
	if refs > 1 {
		ios_runtime.block_refs[block] = refs - 1
		C.ios_objc_initialize_unlock()
		return
	}
	ios_runtime.block_refs.delete(block)
	C.ios_objc_initialize_unlock()
	if read32(block + 8) & (u32(1) << 25) != 0 {
		descriptor := read64(block + 24)
		helper := unsafe { BlockDisposeHelper(voidptr(read64(descriptor + 24))) }
		helper(block)
	}
	objc_remove_associated(block)
	C.free(unsafe { voidptr(block) })
}

fn block_invoke_void(block u64) {
	if block == 0 { return }
	method := unsafe { BlockVoid(voidptr(read64(block + 16))) }
	method(block)
}

fn block_invoke_bool(block u64, value bool) {
	if block == 0 { return }
	method := unsafe { BlockBool(voidptr(read64(block + 16))) }
	method(block, value)
}

fn block_byref_copy(source u64) u64 {
	C.ios_objc_initialize_lock()
	forwarded := read64(source + 8)
	flags := read32(forwarded + 16)
	if flags & 0xfffe != 0 {
		if flags & (u32(1) << 24) != 0 && flags & 0xfffe != 0xfffe {
			write32(forwarded + 16, flags + 2)
		}
		C.ios_objc_initialize_unlock()
		return forwarded
	}
	source_flags := read32(source + 16)
	size := read32(source + 20)
	has_helpers := source_flags & (u32(1) << 25) != 0
	extended := source_flags & 0xf0000000 == u32(1) << 28
	minimum := u32(24) + if has_helpers { u32(16) } else { u32(0) }
	if size < minimum + if extended { u32(8) } else { u32(0) } || size > 1024 * 1024 {
		panic('iOS: invalid by-reference block capture size')
	}
	copied := u64(C.malloc(usize(size)))
	if copied == 0 { panic('iOS: cannot copy by-reference block capture') }
	write64(copied, 0)
	write64(copied + 8, copied)
	// One owner for the stack scope and one for the first copied block.
	write32(copied + 16, source_flags | (u32(1) << 24) | 4)
	write32(copied + 20, size)
	if has_helpers {
		write64(copied + 24, read64(source + 24))
		write64(copied + 32, read64(source + 32))
		if extended { write64(copied + 40, read64(source + 40)) }
	} else {
		unsafe { C.memcpy(voidptr(copied + 24), voidptr(source + 24), usize(size - 24)) }
	}
	write64(source + 8, copied)
	C.ios_objc_initialize_unlock()
	// Compiler helpers can reenter the runtime. They initialize the payload;
	// copying it ourselves would break ARC move/weak and C++ constructors.
	if has_helpers {
		helper := unsafe { BlockCopyHelper(voidptr(read64(source + 24))) }
		helper(copied, source)
	}
	return copied
}

fn write64(address u64, value u64) {
	unsafe { *(&u64(address)) = value }
}

fn block_byref_release(source u64) {
	C.ios_objc_initialize_lock()
	forwarded := read64(source + 8)
	flags := read32(forwarded + 16)
	count := flags & 0xfffe
	if flags & (u32(1) << 24) == 0 || count == 0 || count == 0xfffe {
		C.ios_objc_initialize_unlock()
		return
	}
	last := flags & 0xffff == 2
	write32(forwarded + 16, flags - if last { u32(1) } else { u32(2) })
	C.ios_objc_initialize_unlock()
	if !last { return }
	if flags & (u32(1) << 25) != 0 {
		helper := unsafe { BlockDisposeHelper(voidptr(read64(forwarded + 32))) }
		helper(forwarded)
	}
	C.free(unsafe { voidptr(forwarded) })
}

fn block_object_assign(destination &u64, object u64, flags int) {
	value := match flags & 0x9f {
		3 { objc_retain(object) }
		7 { block_copy(object) }
		8, 24 { block_byref_copy(object) }
		131, 135, 147, 151 { object } // MRC byref helpers do not retain their payload.
		else { panic('iOS: unsupported block capture flags 0x${flags.hex()}') }
	}
	unsafe { *destination = value }
}

fn block_object_dispose(object u64, flags int) {
	match flags & 0x9f {
		3 { objc_release(object) }
		7 { block_release(object) }
		8, 24 { block_byref_release(object) }
		131, 135, 147, 151 {}
		else { panic('iOS: unsupported block capture disposal flags 0x${flags.hex()}') }
	}
}

fn block_symbol(symbol string) ?u64 {
	return match symbol {
		'__NSConcreteStackBlock' { block_isa(0) }
		'__NSConcreteGlobalBlock' { block_isa(1) }
		'__Block_copy' { u64(unsafe { voidptr(block_copy) }) }
		'__Block_release' { u64(unsafe { voidptr(block_release) }) }
		'__Block_object_assign' { u64(unsafe { voidptr(block_object_assign) }) }
		'__Block_object_dispose' { u64(unsafe { voidptr(block_object_dispose) }) }
		else { return none }
	}
}

fn objc_class(object u64) u64 {
	cls := if object == 0 || object in ios_runtime.classes { object } else { read64(object) }
	objc_initialize(cls)
	return cls
}

fn objc_retain_autorelease(object u64) u64 { return objc_autorelease(objc_retain(object)) }
// This runtime always records autoreleased returns in the calling thread's
// pool; it does not elide their release through Apple's caller handshake.
fn objc_unsafe_claim(object u64) u64 { return object }

fn objc_property_strong(object u64, selector u64, value u64, offset i64) {
	objc_property_set(object, selector, offset, value, false, 0)
}

fn objc_property_copy(object u64, selector u64, value u64, offset i64) {
	objc_property_set(object, selector, offset, value, false, 1)
}

fn objc_store_weak(location &u64, object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut value := object
	if value != 0 && value !in ios_runtime.classes && value !in ios_runtime.constants && !is_block(value) {
		header := obj_header(value)
		if C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 { value = 0 }
	}
	ios_runtime.weak[u64(location)] = value
	unsafe { *location = value }
	return value
}

fn objc_destroy_weak(location &u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	ios_runtime.weak.delete(u64(location))
	unsafe { *location = 0 }
}

fn objc_load_weak(location &u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	object := unsafe { *location }
	ns_pool_reject_ownership(object)
	if object == 0 || swift_data_bridge_is_zero(object) || object in ios_runtime.classes || object in ios_runtime.constants || is_block(object) { return objc_retain(object) }
	header := obj_header(object)
	return if C.ios_ref_try_retain(unsafe { &header.refs }) != 0 { object } else { u64(0) }
}

fn objc_copy_weak(destination &u64, source &u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	objc_store_weak(destination, unsafe { *source })
}

fn objc_enumeration_mutation(object u64) {
	_ = object
	panic('iOS: collection mutated during enumeration')
}
