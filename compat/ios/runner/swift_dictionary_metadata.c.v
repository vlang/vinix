// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDictionaryType {
	key      u64
	value    u64
	hashable u64
}

struct SwiftDictionaryMetadataFailure {}

fn (_ &SwiftDictionaryMetadataFailure) msg() string {
	return 'iOS: invalid or retired Swift Dictionary metadata request'
}

fn (_ &SwiftDictionaryMetadataFailure) code() int { return 1 }

__global swift_dictionary_metadata_failure_value = SwiftDictionaryMetadataFailure{}

fn swift_dictionary_metadata_failure() IError {
	return unsafe { &swift_dictionary_metadata_failure_value }
}

// The frozen payload is a single storage word. Completing its layout does
// not inspect or complete Key/Value, or invoke the borrowed Hashable witness.
// Those three identities remain borrowed until quiescent runtime shutdown.
fn swift_dictionary_metadata_checked(_request u64, key u64, value u64, hashable u64) !SwiftAssociatedMetadata {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_dictionary_metadata_retired
		|| ios_runtime.swift_concurrency_retired || key == 0 || value == 0 || hashable == 0
		|| (key | value | hashable) & 7 != 0 {
		return swift_dictionary_metadata_failure()
	}
	code := swift_dictionary_metadata_arena()
	page := usize(C.getpagesize())
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for base, arguments in ios_runtime.swift_dictionary_metadata {
		if arguments.key == key && arguments.value == value && arguments.hashable == hashable {
			return SwiftAssociatedMetadata{ metadata: base + 8 }
		}
	}
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_dictionary_metadata_failure() }
	base := u64(allocation)
	unsafe {
		*(&u64(voidptr(base))) = read64(code + u64(page) + 96)
		*(&u64(voidptr(base + 8))) = 0x200
		*(&u64(voidptr(base + 16))) = code + u64(page) + 160
		*(&u64(voidptr(base + 24))) = key
		*(&u64(voidptr(base + 32))) = value
		*(&u64(voidptr(base + 40))) = hashable
		// The _variant field offset at metadata word five is zero.
	}
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page)
		return swift_dictionary_metadata_failure()
	}
	ios_runtime.swift_dictionary_metadata[base] = SwiftDictionaryType{key, value, hashable}
	return SwiftAssociatedMetadata{ metadata: base + 8 }
}

fn swift_dictionary_metadata_access(request u64, key u64, value u64, hashable u64) SwiftAssociatedMetadata {
	return swift_dictionary_metadata_checked(request, key, value, hashable) or { panic(err) }
}

fn swift_dictionary_metadata_instantiate(descriptor u64, arguments u64, pattern u64) u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_dictionary_metadata_retired
		|| ios_runtime.swift_dictionary_metadata_arena == 0 || arguments == 0 || arguments & 7 != 0
		|| arguments > ~u64(0) - 23 {
		panic('iOS: invalid Swift Dictionary metadata instantiation')
	}
	data := ios_runtime.swift_dictionary_metadata_arena + u64(C.getpagesize())
	if descriptor != data + 160 || pattern != data + 272 {
		panic('iOS: invalid Swift Dictionary metadata instantiation')
	}
	return swift_dictionary_metadata_access(0, read64(arguments), read64(arguments + 8), read64(arguments + 16)).metadata
}

fn swift_dictionary_metadata_arena() u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_dictionary_metadata_retired
		|| ios_runtime.swift_concurrency_retired {
		panic('iOS: Dictionary metadata outside runtime lifetime')
	}
	$if !arm64 {
		panic('iOS: Swift Dictionary metadata accessor requires ARM64')
	}
	witness := swift_bridge_value_witnesses()
	hashable_protocol := swift_integer_metadata() - 16 + 352
	encoding_protocol := swift_foundation_arena() + u64(C.getpagesize()) + 640
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_dictionary_metadata_arena != 0 {
		return ios_runtime.swift_dictionary_metadata_arena
	}
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } {
		panic('iOS: cannot allocate Swift Dictionary descriptor')
	}
	base := u64(allocation)
	data := base + u64(page)
	for i, target in [u64(unsafe { voidptr(swift_dictionary_metadata_access) }),
		u64(unsafe { voidptr(swift_dictionary_metadata_instantiate) })]! {
		entry := base + u64(i * 32)
		write32(entry, 0x58000050)
		write32(entry + 4, 0xd61f0200)
		unsafe { *(&u64(voidptr(entry + 8))) = target }
	}
	unsafe { *(&u64(voidptr(data + 96))) = witness }
	descriptor := data + 160
	write32(descriptor, 0xd1) // Unique generic struct; no native prespecialization records.
	swift_protocol_relative(descriptor + 4, data + 224)
	swift_protocol_relative(descriptor + 8, data + 248)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 1)
	write32(descriptor + 24, 5)
	swift_protocol_relative(descriptor + 28, base + u64(page * 2))
	swift_protocol_relative(descriptor + 32, data + 272)
	write32(descriptor + 36, 0x10002) // Two type parameters, Key: Hashable requirement.
	write32(descriptor + 40, 3) // Key, Value and Key: Hashable are key arguments.
	write32(descriptor + 44, 0x8080)
	write32(descriptor + 48, 0x80)
	swift_protocol_relative(descriptor + 52, data + 264)
	swift_protocol_relative(descriptor + 56, hashable_protocol)
	swift_protocol_relative(data + 232, data + 240)
	C.memcpy(voidptr(data + 240), c'Swift', 6)
	C.memcpy(voidptr(data + 248), c'Dictionary', 11)
	C.memcpy(voidptr(data + 264), c'x', 2)
	swift_protocol_relative(data + 272, base + 32)
	write32(data + 280, 0x40000000)
	swift_protocol_relative(data + 284, witness)
	swift_dictionary_encoding_emit(base, data, encoding_protocol)
	swift_dictionary_decoding_emit(base, data, encoding_protocol + 112)
	// Swift class static method: original in x0, metatype self in x20.
	write32(base + 128, 0xaa1403e1)
	write32(base + 132, 0x58000070)
	write32(base + 136, 0xd61f0200)
	write32(base + 140, 0xd503201f)
	unsafe { *(&u64(base + 144)) = u64(voidptr(swift_dictionary_storage_copy)) }
	C.__builtin___clear_cache(allocation, voidptr(base + 152))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), page, C.PROT_READ) != 0 {
		C.munmap(allocation, page * 3)
		panic('iOS: cannot seal Swift Dictionary descriptor')
	}
	ios_runtime.swift_dictionary_metadata_arena = base
	ios_runtime.swift_dictionary_encoding_descriptor = data + 320
	ios_runtime.swift_dictionary_decoding_descriptor = data + 448
	return base
}

fn swift_dictionary_metadata_stop() {
	ios_runtime.swift_dictionary_metadata_retired = true
	swift_dictionary_decoding_stop()
	swift_dictionary_encoding_stop()
	page := usize(C.getpagesize())
	for base, _ in ios_runtime.swift_dictionary_metadata {
		if C.munmap(voidptr(base), page) != 0 {
			panic('iOS: cannot retire Swift Dictionary metadata')
		}
	}
	unsafe { ios_runtime.swift_dictionary_metadata.free() }
	if ios_runtime.swift_dictionary_metadata_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_dictionary_metadata_arena), page * 3) != 0 {
			panic('iOS: cannot retire Swift Dictionary descriptor')
		}
		ios_runtime.swift_dictionary_metadata_arena = 0
	}
}
