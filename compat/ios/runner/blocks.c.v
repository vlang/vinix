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
	if block in ios_runtime.block_refs { return block_retain(block) }
	descriptor := read64(block + 24)
	size := read64(descriptor + 8)
	if size < 32 || size > 1024 * 1024 { panic('iOS: invalid block size') }
	copied := u64(C.malloc(usize(size)))
	if copied == 0 { panic('iOS: cannot copied block') }
	unsafe {
		C.memcpy(voidptr(copied), voidptr(block), usize(size))
		*(&u64(copied)) = block_isa(2)
	}
	ios_runtime.block_refs[copied] = 1
	if flags & (u32(1) << 25) != 0 {
		helper := unsafe { BlockCopyHelper(voidptr(read64(descriptor + 16))) }
		helper(copied, block)
	}
	return copied
}

fn block_retain(block u64) u64 {
	if refs := ios_runtime.block_refs[block] { ios_runtime.block_refs[block] = refs + 1 }
	return block
}

fn block_release(block u64) {
	refs := ios_runtime.block_refs[block] or { return } // Stack/global are immortal.
	if refs > 1 {
		ios_runtime.block_refs[block] = refs - 1
		return
	}
	ios_runtime.block_refs.delete(block)
	if read32(block + 8) & (u32(1) << 25) != 0 {
		descriptor := read64(block + 24)
		helper := unsafe { BlockDisposeHelper(voidptr(read64(descriptor + 24))) }
		helper(block)
	}
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

fn block_object_assign(destination &u64, object u64, flags int) {
	value := match flags & 0xf {
		3 { objc_retain(object) }
		7 { block_copy(object) }
		else { panic('iOS: unsupported block capture flags') }
	}
	unsafe { *destination = value }
}

fn block_object_dispose(object u64, flags int) {
	match flags & 0xf {
		3 { objc_release(object) }
		7 { block_release(object) }
		else { panic('iOS: unsupported block capture disposal') }
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

fn objc_property_strong(object u64, selector u64, value u64, offset i64) {
	_ = selector
	objc_store_strong(unsafe { &u64(object + u64(offset)) }, value)
}

fn objc_property_copy(object u64, selector u64, value u64, offset i64) {
	_ = selector
	copied := if value != 0 && is_block(value) { block_copy(value) } else { objc_retain(value) }
	location := unsafe { &u64(object + u64(offset)) }
	old := unsafe { *location }
	unsafe { *location = copied }
	objc_release(old)
}

fn objc_store_weak(location &u64, object u64) u64 {
	ios_runtime.weak[u64(location)] = object
	unsafe { *location = object }
	return object
}

fn objc_destroy_weak(location &u64) {
	ios_runtime.weak.delete(u64(location))
	unsafe { *location = 0 }
}

fn objc_load_weak(location &u64) u64 { return objc_retain(unsafe { *location }) }

fn objc_copy_weak(destination &u64, source &u64) {
	objc_store_weak(destination, unsafe { *source })
}

fn objc_enumeration_mutation(object u64) {
	_ = object
	panic('iOS: collection mutated during enumeration')
}
