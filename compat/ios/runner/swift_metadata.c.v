// SPDX-License-Identifier: GPL-2.0-or-later
module main

// String's frozen 64-bit value witnesses. Copies acquire the bridge object
// before publishing the destination; assignments publish before retiring its
// previous owner (whose ObjC deallocator may reenter the runtime). Takes move
// the reference without acquiring it. Destroyed/moved storage is uninitialized
// and need not be cleared. Native String witnesses leave its words unchanged.
fn swift_string_copy(destination u64, source u64, metadata u64) u64 {
	words := unsafe { *(&SwiftStringWords(source)) }
	swift_bridge_retain(words.second)
	unsafe { *(&SwiftStringWords(destination)) = words }
	return destination
}

fn swift_string_destroy(value u64, metadata u64) {
	swift_bridge_release(read64(value + 8))
}

fn swift_string_assign_copy(destination u64, source u64, metadata u64) u64 {
	words := unsafe { *(&SwiftStringWords(source)) }
	swift_bridge_retain(words.second)
	previous := read64(destination + 8)
	unsafe { *(&SwiftStringWords(destination)) = words }
	swift_bridge_release(previous)
	return destination
}

fn swift_string_take(destination u64, source u64, metadata u64) u64 {
	unsafe { *(&SwiftStringWords(destination)) = *(&SwiftStringWords(source)) }
	return destination
}

fn swift_string_assign_take(destination u64, source u64, metadata u64) u64 {
	words := unsafe { *(&SwiftStringWords(source)) }
	previous := read64(destination + 8)
	unsafe { *(&SwiftStringWords(destination)) = words }
	swift_bridge_release(previous)
	return destination
}

const swift_string_extra_inhabitants = u32(0x7fffffff)

// A null/low bridge-object word encodes String's extra inhabitants. Enums
// with more than INT32_MAX empty cases need one tag byte beyond the payload;
// the remaining case index occupies its first four bytes, little endian.
// Counts/tags are C unsigned int (32 bits), not this V compiler's 64-bit int.
fn swift_string_enum_get(value u64, empty_cases u32, metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	if empty_cases > swift_string_extra_inhabitants && unsafe { *(&u8(value + 16)) } != 0 {
		return unsafe { *(&u32(value)) } + swift_string_extra_inhabitants + 1
	}
	object := read64(value + 8)
	// Native ARM64 tests the upper 32 bits of the pointer. The advertised
	// extra-inhabitant count is capped at INT32_MAX; valid enum case indices
	// stay within that limit even though the raw witness recognizes more bits.
	return if object >> 32 == 0 { u32(object) + 1 } else { u32(0) }
}

fn swift_string_enum_store(value u64, which_case u32, empty_cases u32, metadata u64) {
	if empty_cases > swift_string_extra_inhabitants {
		unsafe { *(&u8(value + 16)) = if which_case > swift_string_extra_inhabitants { u8(1) } else { u8(0) } }
	}
	if which_case == 0 { return } // Preserve an already initialized payload.
	if which_case <= swift_string_extra_inhabitants {
		unsafe { *(&u64(value + 8)) = u64(which_case - 1) }
	} else {
		unsafe {
			*(&u64(value)) = u64(which_case - swift_string_extra_inhabitants - 1)
			*(&u64(value + 8)) = 0
		}
	}
}

// _StringGuts is a distinct frozen nominal with one _object field at zero.
// Native witnesses match String's representation/ARC, so share that table,
// while preserving nominal identity and an independent complete accessor.
fn swift_string_guts_emit(code u64, data u64, witness u64, module_descriptor u64) {
	metadata := data + 648
	descriptor := data + 672
	entry := code + 192
	unsafe {
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	write32(descriptor,0x51)
	swift_protocol_relative(descriptor + 4,module_descriptor)
	swift_protocol_relative(descriptor + 8,data + 704)
	swift_protocol_relative(descriptor + 12,entry)
	// No field reflection record, like the existing String descriptor.
	write32(descriptor + 20,1)
	write32(descriptor + 24,2)
	C.memcpy(voidptr(data + 704),c'_StringGuts',12)
	write32(entry,0x58000080)
	write32(entry + 4,0xd2800001)
	write32(entry + 8,0xd65f03c0)
	write32(entry + 12,0xd503201f)
	unsafe { *(&u64(entry + 16)) = metadata }
}

// One allocation keeps relative descriptor pointers within signed 32-bit
// range even when host text and heap addresses are far apart. Its first page
// contains a V-emitted ARM64 metadata accessor; its second contains read-only
// metadata, witnesses and descriptors. Publication happens only after sealing.
// This nonreflectable nominal descriptor deliberately has no Fields record.
// Bounded nominal lookup uses its accessor; field reflection is unsupported.
fn swift_string_metadata() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	page := u64(C.getpagesize())
	if ios_runtime.swift_metadata_arena == 0 {
		$if !arm64 { panic('iOS: Swift metadata accessor requires ARM64') }
		arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift String metadata') }
		base := u64(arena)
		data := base + page
		metadata := data + 16
		witness := data + 64
		descriptor := data + 160
		module_descriptor := data + 192
		// MetadataResponse { metadata, state = Complete(0) } in x0/x1.
		write32(base, 0x58000080) // ldr x0,literal at +16
		write32(base + 4, 0xd2800001) // mov x1,#0
		write32(base + 8, 0xd65f03c0) // ret
		write32(base + 12, 0xd503201f)
		unsafe {
			*(&u64(base + 16)) = metadata
			*(&u64(data + 8)) = witness // Required metadata header at address point - 1.
			*(&u64(metadata)) = 0x200 // Struct kind, not an ObjC/Swift class.
			*(&u64(metadata + 8)) = descriptor
			// The sole field (_guts) has offset zero at metadata word 2.
		}
		for i, function in [u64(unsafe { voidptr(swift_string_copy) }),
			u64(unsafe { voidptr(swift_string_destroy) }), u64(unsafe { voidptr(swift_string_copy) }),
			u64(unsafe { voidptr(swift_string_assign_copy) }), u64(unsafe { voidptr(swift_string_take) }),
			u64(unsafe { voidptr(swift_string_assign_take) }), u64(unsafe { voidptr(swift_string_enum_get) }),
			u64(unsafe { voidptr(swift_string_enum_store) })]! {
			unsafe { *(&u64(witness + u64(i * 8))) = function }
		}
		unsafe { *(&u64(witness + 64)) = 16; *(&u64(witness + 72)) = 16 }
		write32(witness + 80, 0x02010007) // 8-byte alignment, non-POD, inline, bitwise-takable.
		write32(witness + 84, swift_string_extra_inhabitants)
		write32(descriptor, 0x51) // Unique, nongeneric struct context.
		write32(descriptor + 4, u32(i32(i64(module_descriptor) - i64(descriptor + 4))))
		write32(descriptor + 8, u32(i32(i64(data + 216) - i64(descriptor + 8))))
		write32(descriptor + 12, u32(i32(i64(base) - i64(descriptor + 12))))
		write32(descriptor + 20, 1) // NumFields.
		write32(descriptor + 24, 2) // Field offset vector at metadata word 2.
		// Module context flags/parent are zero; its name is relative at byte 8.
		write32(module_descriptor + 8, u32(i32(i64(data + 208) - i64(module_descriptor + 8))))
		C.memcpy(unsafe { voidptr(data + 208) }, c'Swift', 6)
		C.memcpy(unsafe { voidptr(data + 216) }, c'String', 7)
		swift_string_protocols_emit(base, data)
		swift_raw_protocol_emit(data)
		swift_string_guts_emit(base,data,witness,module_descriptor)
		C.__builtin___clear_cache(arena, unsafe { voidptr(base + 216) })
		if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
			|| C.mprotect(unsafe { voidptr(data) }, usize(page), C.PROT_READ) != 0 {
			C.munmap(arena, usize(page * 2))
			panic('iOS: cannot seal Swift String metadata')
		}
		ios_runtime.swift_metadata_arena = base
	}
	return ios_runtime.swift_metadata_arena + page + 16
}

fn swift_string_guts_metadata() u64 { return swift_string_metadata() - 16 + 648 }

fn swift_metadata_stop() {
	swift_objc_bool_metadata_stop()
	swift_dispatch_flags_stop()
	swift_foreign_metadata_stop()
	// Like ARC thunks, metadata is retired only after all workers/callbacks and
	// owned buffers have drained.
	swift_array_stop()
	swiftui_vstack_stop()
	swiftui_vstack_nominal_stop()
	swiftui_tree_stop()
	swiftui_zstack_stop()
	swiftui_zstack_nominal_stop()
	swiftui_tuple_nominal_stop()
	swiftui_tuple_init_stop()
	swiftui_opacity_stop()
	swiftui_state_value_stop()
	swiftui_state_set_stop()
	swiftui_state_nominal_stop()
	swiftui_button_nominal_stop()
	swiftui_modified_stop()
	swiftui_environment_transform_stop()
	swiftui_text_view_stop()
	swift_nsobject_hashable_stop()
	swift_integer_stop()
	swift_void_stop()
	swift_unknown_value_stop()
	swift_interpolation_stop()
	swift_error_metadata_stop()
	if ios_runtime.swift_metadata_arena != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_metadata_arena) }, usize(C.getpagesize()) * 2) != 0 {
			panic('iOS: cannot retire Swift String metadata')
		}
		ios_runtime.swift_metadata_arena = 0
	}
}
