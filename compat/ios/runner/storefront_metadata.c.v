// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native Storefront has two Strings at 0/16 and Locale's implementation/table
// at 32/40. Explicit witnesses replace Apple's compact value-layout interpreter.
fn storefront_value_copy(destination u64, source u64, _metadata u64) u64 {
	swift_string_copy(destination, source, 0)
	swift_string_copy(destination + 16, source + 16, 0)
	swift_url_copy(destination + 32, source + 32, 0)
	return destination
}

fn storefront_value_destroy(value u64, _metadata u64) {
	swift_string_destroy(value, 0)
	swift_string_destroy(value + 16, 0)
	swift_url_destroy(value + 32, 0)
}

fn storefront_value_assign_copy(destination u64, source u64, _metadata u64) u64 {
	// Native publishes each String before its old owner is released. Locale
	// publishes only its owner, releases the old one, then retains and sets its
	// table. Reentrant deallocators can observe these intermediate field states.
	swift_string_assign_copy(destination, source, 0)
	swift_string_assign_copy(destination + 16, source + 16, 0)
	swift_url_assign_copy(destination + 32, source + 32, 0)
	return destination
}

fn storefront_value_take(destination u64, source u64, _metadata u64) u64 {
	C.memmove(voidptr(destination), voidptr(source), 48)
	return destination
}

fn storefront_value_assign_take(destination u64, source u64, metadata u64) u64 {
	// Native destroys all three old fields before publishing any moved words.
	storefront_value_destroy(destination, metadata)
	return storefront_value_take(destination, source, metadata)
}

fn storefront_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	if empty_cases > 0x7fffffff && unsafe { *(&u8(value + 48)) } != 0 {
		mut index := u32(0)
		C.memcpy(unsafe { &index }, voidptr(value), 4)
		return index + u32(0x80000000)
	}
	mut owner := u64(0)
	C.memcpy(unsafe { &owner }, voidptr(value + 8), 8)
	return if owner >> 32 == 0 { u32(owner) + u32(1) } else { u32(0) }
}

fn storefront_enum_store(value u64, which_case u32, empty_cases u32, _metadata u64) {
	if empty_cases > 0x7fffffff {
		unsafe { *(&u8(value + 48)) = if which_case > 0x7fffffff { u8(1) } else { u8(0) } }
	}
	if which_case == 0 { return }
	if which_case <= 0x7fffffff {
		owner := u64(which_case - 1)
		C.memcpy(voidptr(value + 8), unsafe { &owner }, 8)
	} else {
		// Large enums store the remaining index at zero and clear the entire
		// payload, unlike the eight-byte extra-inhabitant write used for nil.
		index := which_case - u32(0x80000000)
		C.memset(voidptr(value), 0, 48)
		C.memcpy(voidptr(value), unsafe { &index }, 4)
	}
}

fn storefront_metadata() u64 {
	entry := storefront_symbol('_$s8StoreKit10StorefrontVMa') or { panic('iOS: Storefront metadata outside runtime lifetime') }
	return entry - 64 + u64(C.getpagesize()) + 32
}

fn storefront_box_allocate() u64 {
	return swift_heap_allocate(storefront_metadata() + 288, 64, 7)
}

fn storefront_box_destroy(owner u64) {
	storefront_value_destroy(owner + 16, 0)
	swift_heap_deallocate(owner, 64, 7)
}

fn storefront_buffer_copy_checked(destination u64, source u64, metadata u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.storefront_retired || destination == 0 || source == 0
		|| destination & 7 != 0 || source & 7 != 0 || metadata != storefront_metadata() { return swift_any_failure() }
	owner := read64(source)
	swift_any_box_checked(owner, metadata, 48)!
	swift_retain(owner)
	unsafe { *(&u64(destination)) = owner }
	return owner + 16
}

fn storefront_buffer_copy(destination u64, source u64, metadata u64) u64 {
	return storefront_buffer_copy_checked(destination, source, metadata) or { panic(err) }
}

fn storefront_metadata_emit(code u64, data u64) {
	entry := code + 64
	metadata := data + 32
	witness := data + 80
	descriptor := data + 192
	module_descriptor := data + 224
	write32(entry, 0x58000080) // Complete metadata response in x0/x1.
	write32(entry + 4, 0xd2800001)
	write32(entry + 8, 0xd65f03c0)
	unsafe {
		*(&u64(entry + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	for i, offset in [u32(0), 16, 32]! { write32(metadata + 16 + u64(i * 4), offset) }
	// Nongeneric private nominal descriptor; no field-reflection/layout flags.
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 240)
	swift_protocol_relative(descriptor + 12, entry)
	write32(descriptor + 20, 3)
	write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, data + 256)
	C.memcpy(voidptr(data + 240), c'Storefront', 11)
	C.memcpy(voidptr(data + 256), c'StoreKit', 9)
	for i, target in [u64(unsafe { voidptr(storefront_buffer_copy) }),
		u64(unsafe { voidptr(storefront_value_destroy) }), u64(unsafe { voidptr(storefront_value_copy) }),
		u64(unsafe { voidptr(storefront_value_assign_copy) }), u64(unsafe { voidptr(storefront_value_take) }),
		u64(unsafe { voidptr(storefront_value_assign_take) }), u64(unsafe { voidptr(storefront_enum_get) }),
		u64(unsafe { voidptr(storefront_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = target }
	}
	unsafe { *(&u64(witness + 64)) = 48; *(&u64(witness + 72)) = 48 }
	write32(witness + 80, 0x30007)
	write32(witness + 84, 0x7fffffff)
	// Registered non-inline box: Self arrives in x20 at the deallocator.
	unsafe {
		*(&u64(data + 304)) = code + 96
		*(&u64(data + 320)) = 0x400
		*(&u64(data + 328)) = metadata
		*(&u64(code + 112)) = u64(voidptr(storefront_box_destroy))
	}
	write32(code + 96, 0xaa1403e0)
	write32(code + 100, 0x58000070)
	write32(code + 104, 0xd61f0200)
}
