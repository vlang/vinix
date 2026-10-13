// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift's frozen 64-bit String representation and Int8 array body, measured
// against the installed libswiftCore from V. See Swift.swiftinterface and
// shims/{HeapObject,RefCount}.h in the Mac SDK. Swift.Int is pointer-sized.
struct SwiftStringWords {
mut:
	first u64
	second u64
}

// Installed ARM64 String.init(): x0=0, x1=0xe000000000000000. The
// canonical empty ASCII value has no heap owner or metadata argument.
fn swift_string_empty() SwiftStringWords {
	return SwiftStringWords{ second: u64(0xe000000000000000) }
}

// A private descriptor for buffers owned by this implementation. It is NOT
// Swift class/type metadata: generic array storage reflection and casts
// remain unsupported exports. The measured array body and ARC
// entry points below are the supported operations on these buffers.
struct SwiftUTF8BufferDescriptor {
	name &char = c'Vinix Swift UTF-8 buffer'
	header_size u64 = 32
	element_size u64 = 1
}
__global swift_utf8_buffer_descriptor = SwiftUTF8BufferDescriptor{}

const swift_address_mask = u64(0x0fffffffffffffff)
const swift_count_mask = u64(0x0000ffffffffffff)
const swift_strong_step = u64(1) << 33
const swift_strong_limit = u64(1) << 30

// DefaultStringInterpolation is frozen with one String _storage field. The
// consuming String initializer transfers that field without retaining it.
fn swift_string_interpolation(first u64, second u64) SwiftStringWords {
	return SwiftStringWords{ first: first, second: second }
}

fn swift_string_literal(bytes &u8, count i64, is_ascii bool) SwiftStringWords {
	if count < 0 || u64(count) > swift_count_mask || (count != 0 && bytes == unsafe { nil }) {
		panic('iOS: invalid Swift string literal')
	}
	if count <= 15 {
		mut result := SwiftStringWords{
			second: (if is_ascii { u64(0xe000000000000000) } else { u64(0xa000000000000000) }) | (u64(count) << 56)
		}
		for i in 0 .. int(count) {
			byte := u64(unsafe { bytes[i] })
			if i < 8 { result.first |= byte << u32(i * 8) }
			else { result.second |= byte << u32((i - 8) * 8) }
		}
		return result
	}
	// Literal storage is immortal and borrowed. Swift encodes its address with
	// the native-storage bias even though there is no heap header before it.
	address := u64(bytes)
	if address < 32 || address > swift_address_mask { panic('iOS: invalid Swift literal address') }
	return SwiftStringWords{
		first: u64(count) | u64(0x1000000000000000) | if is_ascii { u64(0xc000000000000000) } else { u64(0) }
		second: (address - 32) | u64(0x8000000000000000)
	}
}

fn swift_string_utf8(first u64, second u64) !u64 {
	small := second & (u64(1) << 61) != 0
	mut count := first & swift_count_mask
	mut source := u64(0)
	if small {
		// Foreign small strings are not a valid frozen String representation.
		if second & (u64(1) << 63) == 0 || second & (u64(1) << 60) != 0 {
			return error('iOS: unsupported Swift small string representation')
		}
		count = (second >> 56) & 15
	} else {
		// Reject shared/non-tail and foreign forms before reading their object.
		if second & (u64(1) << 60) != 0 || first & (u64(1) << 60) == 0 {
			return error('iOS: Swift shared/foreign string storage is not implemented')
		}
		source = (second & swift_address_mask) + 32
		if source == 32 { return error('iOS: invalid Swift string storage') }
	}
	// Count is bounded to 48 bits, leaving room for header, terminator and the
	// capacity's low flag bit. calloc failures never install a registry entry.
	array := u64(C.calloc(1, usize(32 + count + 1)))
	if array == 0 { return error('iOS: cannot allocate Swift UTF-8 array') }
	unsafe {
		*(&u64(array)) = u64(&swift_utf8_buffer_descriptor)
		*(&u64(array + 8)) = 3 // Pure Swift deallocation, one unowned and one strong reference.
		*(&u64(array + 16)) = count + 1 // utf8CString includes its trailing NUL.
		*(&u64(array + 24)) = (count + 1) << 1 // Int8 is not bridged verbatim.
	}
	if small {
		for i in 0 .. int(count) {
			word := if i < 8 { first } else { second }
			unsafe { *(&u8(array + 32 + u64(i))) = u8(word >> u32((i % 8) * 8)) }
		}
	} else if count != 0 {
		C.memcpy(unsafe { voidptr(array + 32) }, unsafe { voidptr(source) }, usize(count))
	}
	C.ios_objc_initialize_lock()
	ios_runtime.swift_buffers[array] = count + 1
	C.ios_objc_initialize_unlock()
	return array
}

fn swift_string_utf8_cstring(first u64, second u64) u64 {
	return swift_string_utf8(first, second) or { panic(err) }
}

fn swift_buffer_refs(object u64, delta i64) !u64 {
	if object == 0 { return 0 }
	if swift_task_registered(object) { return swift_task_refs(object, delta) }
	C.ios_objc_initialize_lock()
	if object == ios_runtime.swift_empty_array || object == ios_runtime.swift_empty_set {
		C.ios_objc_initialize_unlock()
		return swift_strong_limit // Immortal storage never reports unique.
	}
	if object !in ios_runtime.swift_buffers && object !in ios_runtime.swift_strings
		&& object !in ios_runtime.swift_arrays && object !in ios_runtime.swift_heap {
		C.ios_objc_initialize_unlock()
		return error('iOS: Swift ARC for application heap objects is not implemented')
	}
	location := unsafe { &u64(object + 8) }
	bits := C.ios_load_pointer(location)
	if bits & 0x80000001ffffffff != 3 {
		C.ios_objc_initialize_unlock()
		return error('iOS: unsupported Swift deinitializing/unowned/side-table ARC state')
	}
	refs := (bits >> 33) + 1
	if delta > 0 && u64(delta) > swift_strong_limit - refs {
		C.ios_objc_initialize_unlock()
		return error('iOS: Swift reference count overflow')
	}
	if delta < 0 && u64(-(delta + 1)) + 1 > refs {
		C.ios_objc_initialize_unlock()
		return error('iOS: Swift reference count underflow')
	}
	updated := u64(i64(refs) + delta)
	if updated == 0 {
		// Retire before callbacks. Keep the bytes alive until all Element
		// witnesses return; callbacks may resolve symbols or release other owners.
		C.ios_store_pointer(location, 3 | (u64(1) << 32))
		if mut storage := ios_runtime.swift_heap[object] {
			storage.deiniting = true
			ios_runtime.swift_heap[object] = storage
			C.ios_objc_initialize_unlock()
			swift_heap_destroy(object, storage.metadata, storage.generation)!
			return 0
		}
		if storage := ios_runtime.swift_arrays[object] {
			ios_runtime.swift_arrays.delete(object)
			C.ios_objc_initialize_unlock()
			swift_array_dispose(object, storage)
			return 0
		}
		ios_runtime.swift_buffers.delete(object)
		ios_runtime.swift_strings.delete(object)
		C.free(unsafe { voidptr(object) })
	} else {
		C.ios_store_pointer(location, 3 | ((updated - 1) * swift_strong_step))
	}
	C.ios_objc_initialize_unlock()
	return updated
}

fn swift_retain(object u64) u64 {
	swift_buffer_refs(object, 1) or { panic(err) }
	return object
}
fn swift_release(object u64) { swift_buffer_refs(object, -1) or { panic(err) } }
fn swift_release_n(object u64, count u32) { swift_buffer_refs(object, -i64(count)) or { panic(err) } }
fn swift_is_unique_native(object u64) bool {
	return (swift_buffer_refs(object, 0) or { panic(err) }) == 1
}

fn swift_bridge_retain(object u64) u64 {
	if object == 0 || object & (u64(1) << 63) != 0 { return object }
	address := object & swift_address_mask
	if object & (u64(1) << 62) != 0 { objc_retain(address) }
	else { swift_retain(address) }
	return object
}
fn swift_bridge_release_n(object u64, count i32) {
	if object == 0 || object & (u64(1) << 63) != 0 || count == 0 { return }
	if count < 0 { panic('iOS: negative Swift bridge release count') }
	address := object & swift_address_mask
	if object & (u64(1) << 62) != 0 { for _ in 0 .. count { objc_release(address) } }
	else { swift_release_n(address, u32(count)) }
}
fn swift_bridge_release(object u64) { swift_bridge_release_n(object, 1) }

fn swift_unknown_is_native(object u64) bool {
	if os_log_is_handle(object) { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if swift_task_find_locked(object) != 0 { return true }
	if object == ios_runtime.swift_empty_array || object == ios_runtime.swift_empty_set || object in ios_runtime.swift_buffers
		|| object in ios_runtime.swift_strings || object in ios_runtime.swift_arrays
		|| object in ios_runtime.swift_heap { return true }
	if object in ios_runtime.objects || object in ios_runtime.classes || object in ios_runtime.constants
		|| object in ios_runtime.block_refs { return false }
	panic('iOS: Swift unknown-object ARC for unregistered objects is not implemented')
}
fn swift_unknown_retain(object u64) u64 {
	if object == 0 || object & (u64(1) << 63) != 0 { return object }
	return if swift_unknown_is_native(object) { swift_retain(object) } else { objc_retain(object) }
}
fn swift_unknown_release(object u64) {
	if object == 0 || object & (u64(1) << 63) != 0 { return }
	if swift_unknown_is_native(object) { swift_release(object) } else { objc_release(object) }
}

fn swift_buffers_stop() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_tasks_drain_checked() or { panic(err) }
	if ios_runtime.swift_buffers.len != 0 { panic('iOS: Swift UTF-8 arrays still owned at shutdown') }
	if ios_runtime.swift_strings.len != 0 { panic('iOS: Swift Strings still owned at shutdown') }
	unsafe { ios_runtime.swift_buffers.free() }
	unsafe { ios_runtime.swift_strings.free() }
	swift_array_storage_stop()
	swift_heap_stop()
	swift_arc_stop()
	swift_cstring_stop()
	swift_sequence_stop()
	swift_foundation_stop()
	swift_metadata_stop()
	swift_hash_stop()
	swift_fatal_stop()
	swift_concurrency_stop()
}

fn swift_core_symbol(symbol string) ?u64 {
	if address := swift_once_symbol(symbol) { return address }
	if address := swift_witness_symbol(symbol) { return address }
	if address := swift_mangled_symbol(symbol) { return address }
	if address := swift_object_type_symbol(symbol) { return address }
	if address := swift_error_value_symbol(symbol) { return address }
	if address := swift_interpolation_symbol(symbol) { return address }
	if address := swift_fatal_symbol(symbol) { return address }
	if address := swift_array_symbol(symbol) { return address }
	if address := swift_integer_symbol(symbol) { return address }
	if address := swift_hash_symbol(symbol) { return address }
	if address := swift_string_protocol_symbol(symbol) { return address }
	return match symbol {
		'_$sSTsE5first5where7ElementQzSgSbADKXE_tKF' { swift_sequence_arena() + 256 }
		'_$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF' { swift_sequence_arena() }
		'_$sSS9UTF16ViewV5index_8offsetBySS5IndexVAF_SitF' { u64(unsafe { voidptr(swift_utf16_offset) }) }
		'_$sSS8UTF8ViewV17_foreignSubscript8positions5UInt8VSS5IndexV_tF' { u64(unsafe { voidptr(swift_foreign_subscript) }) }
		'_$sSS8UTF8ViewV13_foreignIndex_8offsetBySS0D0VAF_SitF' { u64(unsafe { voidptr(swift_foreign_offset) }) }
		'_$sSS8UTF8ViewV13_foreignIndex5afterSS0D0VAF_tF' { u64(unsafe { voidptr(swift_foreign_index_after) }) }
		'_$sSS8UTF8ViewV13_foreignCountSiyF' { u64(unsafe { voidptr(swift_foreign_count) }) }
		'_$sSS11withCStringyxxSPys4Int8VGKXEKlF' { swift_cstring_entry() }
		'_$sSS10describingSSx_tclufC' { u64(unsafe { voidptr(swift_string_describing) }) }
		'_$sS2SycfC' { u64(unsafe { voidptr(swift_string_empty) }) }
		'_$sBOWV' { swift_unknown_value_witnesses() }
		// Darwin SwiftError owners use Cocoa ARC, including boxed Swift errors
		// and toll-free NSError/CFError objects. These entries use ordinary C
		// calls, rather than Swift's strong-word or bridge-object encoding.
		'_swift_errorRetain' { u64(unsafe { voidptr(objc_retain) }) }
		'_swift_errorRelease' { u64(unsafe { voidptr(objc_release) }) }
		'_swift_allocObject' { u64(unsafe { voidptr(swift_heap_allocate) }) }
		'_swift_deallocObject', '_swift_deallocClassInstance' { u64(unsafe { voidptr(swift_heap_deallocate) }) }
		'_swift_deallocUninitializedObject' { u64(unsafe { voidptr(swift_heap_deallocate_uninitialized) }) }
		'__swift_stdlib_reportUnimplementedInitializerInFile' { u64(unsafe { voidptr(swift_initializer_report_in_file) }) }
		'__swift_stdlib_reportUnimplementedInitializer' { u64(unsafe { voidptr(swift_initializer_report) }) }
		'__swift_stdlib_operatingSystemVersion' { u64(unsafe { voidptr(ios_operating_system_version) }) }
		'_$sytN' { swift_void_full_metadata() }
		'_$sSSN' { swift_string_metadata() }
		'_$sSSMn' { read64(swift_string_metadata() + 8) }
		'_$sSSMa' { swift_string_metadata(); ios_runtime.swift_metadata_arena }
		'_$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC' { u64(unsafe { voidptr(swift_string_interpolation) }) }
		'_$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC' { u64(unsafe { voidptr(swift_string_literal) }) }
		'_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg' { u64(unsafe { voidptr(swift_string_utf8_cstring) }) }
		'_swift_retain' { swift_arc_entry(false) }
		'_swift_release' { swift_arc_entry(true) }
		'_swift_release_n' { u64(unsafe { voidptr(swift_release_n) }) }
		'_swift_bridgeObjectRetain' { u64(unsafe { voidptr(swift_bridge_retain) }) }
		'_swift_bridgeObjectRelease' { u64(unsafe { voidptr(swift_bridge_release) }) }
		'_swift_bridgeObjectRelease_n' { u64(unsafe { voidptr(swift_bridge_release_n) }) }
		'_swift_unknownObjectRetain' { u64(unsafe { voidptr(swift_unknown_retain) }) }
		'_swift_unknownObjectRelease' { u64(unsafe { voidptr(swift_unknown_release) }) }
		'_swift_isUniquelyReferenced_nonNull_native' { u64(unsafe { voidptr(swift_is_unique_native) }) }
		else { none }
	}
}
