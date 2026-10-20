// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDictionaryStorageFailure {}

fn (_ &SwiftDictionaryStorageFailure) msg() string {
	return 'iOS: unsupported or retired Dictionary storage copy layout'
}

fn (_ &SwiftDictionaryStorageFailure) code() int { return 1 }

__global swift_dictionary_storage_failure_value = SwiftDictionaryStorageFailure{}

fn swift_dictionary_storage_failure() IError {
	return unsafe { &swift_dictionary_storage_failure_value }
}

// The caller borrows complete native class/type metadata, just as allocObject
// does. Validate its fixed Dictionary storage shape before reading its generic
// arguments. Hashable and the source's element records are never invoked/read.
fn swift_dictionary_storage_type_checked(metadata u64) !SwiftDictionaryType {
	if metadata < 24 || metadata & 7 != 0 || metadata > ~u64(0) - 1024 {
		return swift_dictionary_storage_failure()
	}
	if read64(metadata) <= 0x7ff { return swift_dictionary_storage_failure() }
	swift_heap_layout(metadata, 64, 7)!
	if read32(metadata + 48) != 64 || read32(metadata + 52) & 0xffff != 7 {
		return swift_dictionary_storage_failure()
	}
	descriptor := read64(metadata + 64)
	if descriptor == 0 || descriptor & 3 != 0 || read32(descriptor) & 0x9f != 0x90 {
		return swift_dictionary_storage_failure()
	}
	name := swift_foreign_relative(descriptor + 8)!
	parent := swift_foreign_relative(descriptor + 4)!
	module_name := swift_foreign_relative(parent + 8)!
	if C.memcmp(voidptr(name), c'_DictionaryStorage', 19) != 0 || read32(parent) & 31 != 0
		|| C.memcmp(voidptr(module_name), c'Swift', 6) != 0 {
		return swift_dictionary_storage_failure()
	}
	positive := u64(read32(descriptor + 28))
	if read32(descriptor + 32) != 4 || positive < 14 || positive > 128
		|| u64(read32(metadata + 56)) < positive * 8 + u64(read32(metadata + 60)) {
		return swift_dictionary_storage_failure()
	}
	arguments := metadata + (positive - 4) * 8
	return SwiftDictionaryType{ key: read64(arguments), value: read64(arguments + 8), hashable: read64(arguments + 16) }
}

// This is the allocation half of NativeDictionary.copy/mapValues. The caller
// copies occupancy and initializes elements after return. Preserve only scale,
// age and seed; neither count, capacity, reserve hint, pointers nor entries are
// copied. Source remains borrowed and no element/Hashable callback is made.
fn swift_dictionary_storage_copy_checked(original u64, metadata u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_dictionary_metadata_retired || original == 0 || original & 7 != 0 {
		return swift_dictionary_storage_failure()
	}
	C.ios_objc_initialize_lock()
	if !swift_dictionary_empty_locked(original) && !swift_json_decoder_empty_locked(original)
		&& !swift_json_encoder_empty_locked(original) {
		storage := ios_runtime.swift_heap[original] or {
			C.ios_objc_initialize_unlock()
			return swift_dictionary_storage_failure()
		}
		if storage.deiniting || storage.size < 48 || read64(original) != storage.metadata {
			C.ios_objc_initialize_unlock()
			return swift_dictionary_storage_failure()
		}
		// Source metadata is kept alive by its registered, borrowed owner. Only
		// its class identity is needed; source Key/Value layouts may be opaque.
		if _ := swift_dictionary_storage_type_checked(storage.metadata) {
		} else {
			C.ios_objc_initialize_unlock()
			return swift_dictionary_storage_failure()
		}
	}
	scale := unsafe { *(&u8(original + 32)) }
	age := read32(original + 36)
	seed := read64(original + 40)
	C.ios_objc_initialize_unlock()
	if scale > 14 { return swift_dictionary_storage_failure() }
	types := swift_dictionary_storage_type_checked(metadata)!
	key := swift_sequence_value_checked(types.key)!
	value := swift_sequence_value_checked(types.value)!
	key_stride := read64(read64(types.key - 8) + 72)
	value_stride := read64(read64(types.value - 8) + 72)
	buckets := u64(1) << scale
	words := (buckets + 63) / 64
	// Checked bounds keep all aligned sums and products below 16 MiB.
	if key_stride > 16777216 / buckets || value_stride > 16777216 / buckets {
		return swift_dictionary_storage_failure()
	}
	keys := (64 + words * 8 + key.alignment - 1) & ~(key.alignment - 1)
	values := (keys + buckets * key_stride + value.alignment - 1) & ~(value.alignment - 1)
	size := values + buckets * value_stride
	if size > 16777216 { return swift_dictionary_storage_failure() }
	mask := u64(7) | (key.alignment - 1) | (value.alignment - 1)
	owner := swift_heap_allocate_record(metadata, size, mask, true)
	unsafe {
		*(&u64(owner + 16)) = 0
		*(&u64(owner + 24)) = if scale == 0 {
			u64(0)
		} else {
			buckets - buckets / 4 - u64(scale == 1)
		}
		*(&u64(owner + 32)) = u64(scale) | (u64(age) << 32)
		*(&u64(owner + 40)) = seed
		*(&u64(owner + 48)) = owner + keys
		*(&u64(owner + 56)) = owner + values
	}
	C.memset(voidptr(owner + 64), 0, usize(words * 8))
	if buckets < 64 { unsafe { *(&u64(owner + 64)) = ~((u64(1) << u32(buckets)) - 1) } }
	return owner
}

fn swift_dictionary_storage_copy(original u64, metadata u64) u64 {
	return swift_dictionary_storage_copy_checked(original, metadata) or { panic(err) }
}

fn swift_dictionary_storage_copy_symbol(symbol string) ?u64 {
	if symbol != '_$ss18_DictionaryStorageC4copy8originalAByxq_Gs05__RawaB0C_tFZ'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_dictionary_metadata_retired {
		return none
	}
	return swift_dictionary_metadata_arena() + 128
}
