// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A nominal class declaration is separate from Dictionary value metadata and
// from a heap owner's metadata/header. Reuse the sealed Dictionary arena for
// the measured bounds and two-parameter, three-key-argument generic signature.
// Accessor, reflection, cache/pattern and native override/vtable records remain
// absent: storage-class instantiation and ObjC ancestry need further support.
fn swift_dictionary_storage_class_emit(data u64, hashable u64) {
	descriptor := data + 640
	write32(descriptor, 0xd0)
	swift_protocol_relative(descriptor + 4, data + 224)
	swift_protocol_relative(descriptor + 8, data + 736)
	swift_protocol_relative(descriptor + 20, data + 768)
	write32(descriptor + 24, 3)
	write32(descriptor + 28, 26)
	write32(descriptor + 32, 4) // Key, Value, Hashable at metadata words 22..24.
	write32(descriptor + 40, 25) // Empty field offset vector.
	write32(descriptor + 52, 0x10002)
	write32(descriptor + 56, 3)
	write32(descriptor + 60, 0x8080)
	write32(descriptor + 64, 0x80) // Key conforms to Hashable.
	swift_protocol_relative(descriptor + 68, data + 264) // x
	swift_protocol_relative(descriptor + 72, hashable)
	C.memcpy(voidptr(data + 736), c'_DictionaryStorage', 19)
	C.memcpy(voidptr(data + 768), c's22__RawDictionaryStorageC', 27)
}

fn swift_dictionary_storage_class_symbol(symbol string) ?u64 {
	if symbol != '_$ss18_DictionaryStorageCMn' || ios_runtime == unsafe { nil }
		|| ios_runtime.swift_dictionary_metadata_retired || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_dictionary_metadata_arena() + u64(C.getpagesize()) + 640
}
