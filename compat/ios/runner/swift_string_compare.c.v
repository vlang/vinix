// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftStringCompareFailure {}
fn (_ &SwiftStringCompareFailure) msg() string { return 'iOS: invalid or unsupported Swift String comparison' }
fn (_ &SwiftStringCompareFailure) code() int { return 1 }
__global swift_string_compare_failure_value = SwiftStringCompareFailure{}
fn swift_string_compare_failure() IError { return unsafe { &swift_string_compare_failure_value } }

// Both spans have passed the checked reader and ASCII validation. Keep the
// prefix/count tie-break after memcmp so embedded NULs remain ordinary bytes.
fn swift_string_compare_bytes(left SwiftStringBytes, right SwiftStringBytes) int {
	length := if left.count < right.count { left.count } else { right.count }
	raw := if length == 0 { 0 } else { C.memcmp(voidptr(left.address), voidptr(right.address), usize(length)) }
	if raw == 0 && left.count == right.count { return 0 }
	if raw != 0 { return if raw < 0 { -1 } else { 1 } }
	return if left.count < right.count { -1 } else { 1 }
}

// ARM64: borrowed String guts in x0/x1 and x2/x3, expectation's low byte in
// x4 (0 equality, 1 less-than), Bool in x0. Preserve opaque contexts; ignore
// the indirect-result address in x8.
fn swift_string_compare_checked(first u64, second u64, other_first u64, other_second u64, expectation u64) !bool {
	swift_string_hashable_active()!
	if expectation & 255 > 1 { return swift_string_compare_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	values := u64(C.__builtin_alloca(32))
	scratch := u64(C.__builtin_alloca(32))
	unsafe {
		*(&SwiftStringWords(values)) = SwiftStringWords{first, second}
		*(&SwiftStringWords(values + 16)) = SwiftStringWords{other_first, other_second}
	}
	// Reuse the complete canonical-equality profile, including its deferred
	// NFC temporary frees, for the equality callers and dictionary lookups.
	if expectation & 255 == 0 { return swift_string_hashable_equal_checked(values, values + 16) }
	left := swift_string_hashable_bytes(values, scratch)!
	right := swift_string_hashable_bytes(values + 16, scratch + 16)!
	// Unicode ordering needs a separately verified runtime profile. In
	// particular, native mixed-normalization prefix ordering is not safely
	// approximated by comparing complete NFC scalar arrays.
	if !swift_replace_ascii(left) || !swift_replace_ascii(right) { return swift_string_compare_failure() }
	return swift_string_compare_bytes(left, right) < 0
}

fn swift_string_compare(first u64, second u64, other_first u64, other_second u64, expectation u64) bool {
	return swift_string_compare_checked(first, second, other_first, other_second, expectation) or { panic(err) }
}

fn swift_string_compare_symbol(symbol string) ?u64 {
	if symbol != '_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF' { return none }
	swift_string_hashable_active() or { return none }
	return u64(unsafe { voidptr(swift_string_compare) })
}
