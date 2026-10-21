// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftMangledAccessor = fn (u64) SwiftAssociatedMetadata

// Type names are borrowed byte spans, not C strings: symbolic references
// contain zero bytes. Parse the entire supported expression before invoking
// any accessor. Only the existing metadata caches own the resulting pointers.
struct SwiftMangledType {
	kind u8
	arrays u64
	value u64
	name_length u64
}

fn swift_mangled_byte(name u64, length u64, offset u64) u8 {
	return if offset < length { unsafe { *(&u8(name + offset)) } } else { u8(0) }
}

fn swift_mangled_parse(name u64, length u64) !SwiftMangledType {
	if length == 0 { return SwiftMangledType{} }
	if name == 0 || length > 1048576 || name > ~u64(0) - length {
		return error('iOS: invalid bounded Swift type name')
	}
	mut offset := u64(0)
	mut arrays := u64(0)
	for swift_mangled_byte(name, length, offset) == `S`
		&& swift_mangled_byte(name, length, offset + 1) == `a`
		&& swift_mangled_byte(name, length, offset + 2) == `y` {
		arrays++
		if arrays > 64 { return error('iOS: Swift type nesting exceeds limit') }
		offset += 3
	}
	mut kind := u8(0)
	mut value := u64(0)
	mut name_length := u64(0)
	first := swift_mangled_byte(name, length, offset)
	second := swift_mangled_byte(name, length, offset + 1)
	if first == 0 { return SwiftMangledType{} }
	if first == `s` && length - offset >= 9
		&& C.memcmp(unsafe { voidptr(name + offset) }, c's5Error_p', 9) == 0 {
		kind = 8; offset += 9
	} else if first == `S` && (second == `S` || second == 0) {
		kind = 1; offset += if second == 0 { u64(1) } else { u64(2) }
	} else if first == `S` && second == `i` {
		kind = 2; offset += 2
	} else if first == `S` && second == `c` && swift_mangled_byte(name, length, offset + 2) == `P` {
		kind = 7; offset += 3
	} else if first == `y` && second == `t` {
		kind = 3; offset += 2
	} else if first == `x` {
		kind = 4; offset++
	} else if first == `q` && second == `_` {
		kind = 10; offset += 2 // Second type parameter at depth zero.
	} else if first == 1 || first == 2 {
		if length - offset < 5 { return SwiftMangledType{} }
		// Byte loads accept the unaligned signed relative offset after the tag
		// and need no address-escaped V local or temporary heap allocation.
		mut bits := u32(0)
		for i in u64(0) .. 4 { bits |= u32(swift_mangled_byte(name, length, offset + 1 + i)) << (i * 8) }
		delta := i32(bits)
		base := name + offset + 1
		if (delta < 0 && base < u64(-i64(delta)))
			|| (delta > 0 && base > ~u64(0) - u64(delta)) {
			return error('iOS: invalid Swift symbolic type reference')
		}
		value = u64(i64(base) + i64(delta))
		if first == 2 {
			if value % 8 != 0 { return error('iOS: unaligned indirect Swift symbolic type reference') }
			value = read64(value)
		}
		if value == 0 { return error('iOS: null Swift symbolic type descriptor') }
		if value % 4 != 0 { return error('iOS: unaligned Swift symbolic type descriptor') }
		kind = 5; offset += 5
		if swift_mangled_byte(name, length, offset) == `_`
			&& swift_mangled_byte(name, length, offset + 1) == `p` {
			kind = 9; offset += 2 // Symbolic protocol existential, not a nominal accessor.
		}
	} else if first == `S` && second == `o` {
		offset += 2
		for {
			byte := swift_mangled_byte(name, length, offset)
			if byte < `0` || byte > `9` { break }
			name_length = name_length * 10 + byte - `0`
			if name_length > length { return SwiftMangledType{} }
			offset++
		}
		if name_length == 0 || name_length > length - offset { return SwiftMangledType{} }
		value = name + offset
		for i in u64(0) .. name_length {
			if swift_mangled_byte(name, length, offset + i) == 0 { return SwiftMangledType{} }
		}
		offset += name_length
		if swift_mangled_byte(name, length, offset) != `C` { return SwiftMangledType{} }
		offset++; kind = 6
	} else {
		return error('iOS: unsupported Swift mangled type expression')
	}
	for _ in u64(0) .. arrays {
		if swift_mangled_byte(name, length, offset) != `G` { return SwiftMangledType{} }
		offset++
	}
	if swift_mangled_byte(name, length, offset) != 0 {
		return error('iOS: unsupported Swift mangled type suffix')
	}
	return SwiftMangledType{kind: kind, arrays: arrays, value: value, name_length: name_length}
}

fn swift_mangled_nominal_request(descriptor u64, request u64) !u64 {
	// Descriptors/accessors belong to the caller or its loaded Mach-O image.
	// Generic nominals need argument/witness substitution and are not invoked
	// through this nongeneric ABI. No lock crosses a borrowed accessor call.
	flags := read32(descriptor)
	if flags & 31 !in [u32(16), 17, 18]! || flags & 0xff80 != 0 {
		return error('iOS: unsupported Swift symbolic context descriptor')
	}
	delta := i32(read32(descriptor + 12))
	if delta == 0 { return error('iOS: Swift nominal type has no metadata accessor') }
	address := u64(i64(descriptor + 12) + i64(delta))
	if address % 4 != 0 { return error('iOS: unaligned Swift metadata accessor') }
	access := unsafe { SwiftMangledAccessor(voidptr(address)) }
	response := access(request) // MetadataResponse in x0/x1; this subset requires Complete.
	if response.metadata == 0 || response.state != 0 {
		return error('iOS: Swift nominal accessor did not return complete metadata')
	}
	return response.metadata
}

// Compare known declarations before touching context/argument bytes. Only the
// selected type word is borrowed: Key/Element at zero, Dictionary storage Value
// at eight. Hashable and the other type's metadata are never read or invoked.
// Child identities must remain live and complete, as for existing Element
// substitution; this subset does not perform deferred child completion.
fn swift_mangled_generic_type_checked(context u64, generic_args u64, value_parameter bool) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_dictionary_metadata_failure()
	}
	if context == 0 || generic_args == 0 { return 0 }
	if context == read64(swift_string_metadata() + 8) { return 0 }
	array_context := swift_array_arena() + u64(C.getpagesize()) + 160
	if context == array_context || context == array_context + 160 {
		if value_parameter { return swift_dictionary_metadata_failure() }
	} else {
		if ios_runtime.swift_dictionary_metadata_retired
			|| ios_runtime.swift_dictionary_metadata_arena == 0
			|| context != ios_runtime.swift_dictionary_metadata_arena + u64(C.getpagesize()) + 640 {
			return swift_dictionary_metadata_failure()
		}
	}
	offset := if value_parameter { u64(8) } else { u64(0) }
	if generic_args & 7 != 0 || generic_args > ~u64(0) - offset - 7 {
		return swift_dictionary_metadata_failure()
	}
	return read64(generic_args + offset)
}

fn swift_mangled_lookup_request_checked(request u64, name u64, length u64, context u64, generic_args u64) !u64 {
	parsed := swift_mangled_parse(name, length)!
	mut metadata := u64(0)
	match parsed.kind {
		0 { return 0 }
		1 { metadata = swift_string_metadata() }
		2 { metadata = swift_integer_metadata() }
		3 { metadata = swift_void_full_metadata() + 8 }
		4, 10 {
			metadata = swift_mangled_generic_type_checked(context, generic_args, parsed.kind == 10)!
			if metadata == 0 { return 0 }
		}
		5 { metadata = swift_mangled_nominal_request(parsed.value, request)! }
		6 {
			// A borrowed bounded key avoids allocating a temporary C string.
			key := unsafe { (&u8(parsed.value)).vstring_with_len(int(parsed.name_length)) }
			C.ios_objc_initialize_lock()
			cls := ios_runtime.names[key] or { u64(0) }
			C.ios_objc_initialize_unlock()
			if cls == 0 { return 0 }
			metadata = swift_objc_metadata_checked(cls)!
		}
		7 { metadata = swift_task_priority_metadata() }
		8 { metadata = swift_error_existential_metadata() }
		9 {
			// The image's indirect protocol reference has already been bound.
			// Match the canonical Error descriptor before reading any foreign
			// protocol or calling an accessor. Other existentials need support.
			C.ios_objc_initialize_lock()
			protocol := if ios_runtime.swift_error_arena == 0 { u64(0) } else {
				ios_runtime.swift_error_arena + u64(C.getpagesize()) + 240
			}
			C.ios_objc_initialize_unlock()
			if parsed.value != protocol || protocol == 0 { return swift_describing_failure() }
			metadata = swift_error_existential_metadata()
		}
		else { return error('iOS: invalid Swift type expression') }
	}
	for _ in u64(0) .. parsed.arrays { metadata = swift_array_access(request, metadata).metadata }
	return metadata
}

fn swift_mangled_nominal(descriptor u64) !u64 {
	return swift_mangled_nominal_request(descriptor, 0)
}

fn swift_mangled_lookup_checked(name u64, length u64, context u64, generic_args u64) !u64 {
	return swift_mangled_lookup_request_checked(0, name, length, context, generic_args)
}

fn swift_mangled_lookup(name u64, length u64, context u64, generic_args u64) u64 {
	return swift_mangled_lookup_checked(name, length, context, generic_args) or { panic(err) }
}

fn swift_mangled_symbol(symbol string) ?u64 {
	return match symbol {
		'_swift_getTypeByMangledNameInContext2' { u64(unsafe { voidptr(swift_context2_lookup) }) }
		'_swift_getTypeByMangledNameInContextInMetadataState' { u64(unsafe { voidptr(swift_mangled_state_lookup) }) }
		'_swift_getForeignTypeMetadata' { u64(unsafe { voidptr(swift_foreign_metadata) }) }
		'_swift_getTypeByMangledNameInContext' { u64(unsafe { voidptr(swift_mangled_lookup) }) }
		else { none }
	}
}
