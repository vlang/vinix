// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftStringHashableFailure {}

fn (_ &SwiftStringHashableFailure) msg() string {
	return 'iOS: invalid or unsupported Swift String Hashable input'
}

fn (_ &SwiftStringHashableFailure) code() int { return 1 }

__global swift_string_hashable_failure_value = SwiftStringHashableFailure{}

fn swift_string_hashable_failure() IError { return unsafe { &swift_string_hashable_failure_value } }

fn swift_string_hashable_active() ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_string_hashable_failure()
	}
}

// Indirect Self addresses and immortal literal bytes are borrowed readable
// caller spans. Registered mortal owners remain protected by the registry lock.
fn swift_string_hashable_receiver(receiver u64) !SwiftStringWords {
	if receiver == 0 || receiver & 7 != 0 || receiver > ~u64(0) - 15 {
		return swift_string_hashable_failure()
	}
	return unsafe { *(&SwiftStringWords(receiver)) }
}

fn swift_string_hashable_bytes(value u64, scratch u64) !SwiftStringBytes {
	words := swift_string_hashable_receiver(value)!
	bytes := swift_replace_bytes(value, scratch)!
	marked_ascii := if words.second & (u64(1) << 61) != 0 {
		words.second & (u64(1) << 62) != 0
	} else {
		words.first & (u64(1) << 63) != 0
	}
	if marked_ascii && !swift_replace_ascii(bytes) { return swift_string_hashable_failure() }
	return bytes
}

fn swift_string_hashable_raw_checked(seed i64, receiver u64) !i64 {
	swift_string_hashable_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	words := swift_string_hashable_receiver(receiver)!
	swift_hasher_initialize()
	mut state := unsafe { &SwiftHasher(C.__builtin_alloca(72)) }
	unsafe { *state = swift_hasher_seed(seed) }
	swift_string_hash_into_checked(u64(state), words.first, words.second)!
	return swift_hasher_finalize(mut state)
}

// Concrete witnesses ignore generic metadata/table arguments, like native
// String. Instance requirements borrow indirect Self in x20, adapted by thunks.
fn swift_string_hashable_value(_metadata u64, _table u64, receiver u64) i64 {
	return swift_string_hashable_raw_checked(0, receiver) or { panic(err) }
}

fn swift_string_hashable_raw(seed i64, _metadata u64, _table u64, receiver u64) i64 {
	return swift_string_hashable_raw_checked(seed, receiver) or { panic(err) }
}

fn swift_string_hashable_into_checked(state u64, receiver u64) ! {
	swift_string_hashable_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	words := swift_string_hashable_receiver(receiver)!
	swift_string_hash_into_checked(state, words.first, words.second)!
}

fn swift_string_hashable_into(state u64, _metadata u64, _table u64, receiver u64) {
	swift_string_hashable_into_checked(state, receiver) or { panic(err) }
}

fn swift_string_hashable_equal_checked(left u64, right u64) !bool {
	swift_string_hashable_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	scratch := u64(C.__builtin_alloca(32))
	lhs := swift_string_hashable_bytes(left, scratch)!
	rhs := swift_string_hashable_bytes(right, scratch + 16)!
	if lhs.count == rhs.count && (lhs.count == 0 || C.memcmp(voidptr(lhs.address), voidptr(rhs.address), usize(lhs.count)) == 0) {
		return true
	}
	if swift_replace_ascii(lhs) && swift_replace_ascii(rhs) { return false }
	// Equality observes canonical equivalence, including across different byte
	// counts/storage forms. Compatibility equivalence and case folding do not apply.
	left_nfc := swift_nfc_normalize(unsafe { tos(&u8(lhs.address), int(lhs.count)) })
	defer { unsafe { left_nfc.free() } }
	right_nfc := swift_nfc_normalize(unsafe { tos(&u8(rhs.address), int(rhs.count)) })
	defer { unsafe { right_nfc.free() } }
	return left_nfc == right_nfc
}

fn swift_string_hashable_equal(left u64, right u64, _metadata u64, _table u64) bool {
	return swift_string_hashable_equal_checked(left, right) or { panic(err) }
}

// Extend String's existing two-page arena before it is sealed. The table and
// descriptors share its lifetime; no additional allocation or cache is needed.
fn swift_string_hashable_emit(code u64, data u64) {
	swift_integer_metadata() // Canonical core Hashable and Equatable descriptors.
	integer := ios_runtime.swift_integer_arena + u64(C.getpagesize())
	for i, target in [u64(unsafe { voidptr(swift_string_hashable_value) }),
		u64(unsafe { voidptr(swift_string_hashable_into) }),
		u64(unsafe { voidptr(swift_string_hashable_raw) })]! {
		entry := code + 224 + u64(i * 32)
		write32(entry, if i == 0 { u32(0xaa1403e2) } else { u32(0xaa1403e3) }) // mov x2/x3,x20
		write32(entry + 4, 0x58000070)
		write32(entry + 8, 0xd61f0200)
		write32(entry + 12, 0xd503201f)
		unsafe { *(&u64(entry + 16)) = target }
	}
	hash := data + 736
	equal := data + 776
	for i, protocol in [integer + 352, integer + 432]! {
		conformance := data + 792 + u64(i * 16)
		table := if i == 0 { hash } else { equal }
		cell := data + 824 + u64(i * 8)
		unsafe {
			*(&u64(table)) = conformance
			*(&u64(cell)) = protocol
		}
		// RelativeIndirectablePointer via a nearby cell avoids any dependency
		// on the distance between independently mapped metadata arenas.
		swift_protocol_relative(conformance, cell + 1)
		swift_protocol_relative(conformance + 4, data + 160)
		swift_protocol_relative(conformance + 8, table)
	}
	unsafe {
		*(&u64(hash + 8)) = equal
		*(&u64(hash + 16)) = code + 224
		*(&u64(hash + 24)) = code + 256
		*(&u64(hash + 32)) = code + 288
		*(&u64(equal + 8)) = u64(voidptr(swift_string_hashable_equal))
	}
}

fn swift_string_hashable_table_checked() !u64 {
	swift_string_hashable_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return swift_string_metadata() - 16 + 736
}
