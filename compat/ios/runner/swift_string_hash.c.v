// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftStringHashFailure {}

fn (_ &SwiftStringHashFailure) msg() string {
	return 'iOS: invalid or unsupported Swift String hashing input'
}

fn (_ &SwiftStringHashFailure) code() int { return 1 }

__global swift_string_hash_failure_value = SwiftStringHashFailure{}

fn swift_string_hash_failure() IError { return unsafe { &swift_string_hash_failure_value } }

fn swift_string_hash_scalar(mut state SwiftHasher, scalar u32) {
	if scalar < 0x80 {
		swift_hasher_byte(mut state, scalar)
		return
	}
	mut word := u64(0)
	mut length := i64(0)
	if scalar < 0x800 {
		word = u64(0xc0 | (scalar >> 6)) | (u64(0x80 | (scalar & 63)) << 8)
		length = 2
	} else if scalar < 0x10000 {
		word = u64(0xe0 | (scalar >> 12)) | (u64(0x80 | ((scalar >> 6) & 63)) << 8) | (u64(0x80 | (scalar & 63)) << 16)
		length = 3
	} else {
		word = u64(0xf0 | (scalar >> 18)) | (u64(0x80 | ((scalar >> 12) & 63)) << 8) | (u64(0x80 | ((scalar >> 6) & 63)) << 16) | (u64(0x80 | (scalar & 63)) << 24)
		length = 4
	}
	swift_hasher_partial(mut state, word, length)
}

// Native ARM64: borrowed inout Hasher x0, borrowed String x1/x2. The
// existing checked reader supports inline, immutable literals, registered
// native tails and registered foreign NSString/decoded constants up to 1 MiB.
// Keep owners borrowed throughout; shared/custom storage is a separate profile.
fn swift_string_hash_into_checked(state u64, first u64, second u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| state == 0 || state & 7 != 0 || state > ~u64(0) - 71 {
		return swift_string_hash_failure()
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	words := u64(C.__builtin_alloca(16))
	scratch := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(words)) = SwiftStringWords{first, second} }
	bytes := swift_replace_bytes(words, scratch)!
	ascii := swift_replace_ascii(bytes)
	marked_ascii := if second & (u64(1) << 61) != 0 {
		second & (u64(1) << 62) != 0
	} else {
		first & (u64(1) << 63) != 0
	}
	if marked_ascii && !ascii { return swift_string_hash_failure() }
	mut hasher := unsafe { &SwiftHasher(voidptr(state)) }
	if ascii {
		swift_hasher_bytes(mut hasher, bytes.address, bytes.address + bytes.count)
	} else {
		normalized := swift_nfc_normalize(unsafe { tos(&u8(bytes.address), int(bytes.count)) })
		for scalar in normalized { swift_string_hash_scalar(mut hasher, scalar) }
		unsafe { normalized.free() }
	}
	// Separate strings remain distinguishable when combined in sequence.
	swift_hasher_byte(mut hasher, 0xff)
}

fn swift_string_hash_into(state u64, first u64, second u64) {
	swift_string_hash_into_checked(state, first, second) or { panic(err) }
}
