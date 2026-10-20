// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftGraphemeState {
mut:
	started             bool
	previous            u32
	regional_odd        bool
	pictographic_extend bool
	pictographic_zwj    bool
	indic               u32
}

fn swift_grapheme_property(scalar u32) u32 {
	if scalar < 128 {
		if scalar == 13 { return 1 }
		if scalar == 10 { return 2 }
		return if scalar < 32 || scalar == 127 { u32(3) } else { u32(0) }
	}
	mut low := 0
	mut high := swift_grapheme_ranges.len
	for low < high {
		middle := low + (high - low) / 2
		word := swift_grapheme_ranges[middle]
		if scalar < u32(word & 0x1fffff) {
			high = middle
		} else if scalar > u32((word >> 21) & 0x1fffff) {
			low = middle + 1
		} else {
			return u32(word >> 42)
		}
	}
	return 0
}

// Unicode 17 UAX #29 extended grapheme rules, in rule order. Context is
// constant-sized: consecutive RI parity, EP Extend* ZWJ, and Indic linker state.
// Return whether there is a boundary immediately before this scalar (GB1).
fn swift_grapheme_break(mut state SwiftGraphemeState, scalar u32) bool {
	property := swift_grapheme_property(scalar)
	current := property & 15
	previous := state.previous
	indic := property >> 5
	pictographic := property & 16 != 0
	boundary := if !state.started {
		true
	} else if previous == 1 && current == 2 {
		false
	} // GB3
	else if previous in [u32(1), 2, 3]! || current in [u32(1), 2, 3]! {
		true
	} // GB4/5
	else if previous == 9 && current in [u32(9), 10, 12, 13]! {
		false
	} // GB6
	else if previous in [u32(12), 10]! && current in [u32(10), 11]! {
		false
	} // GB7
	else if previous in [u32(13), 11]! && current == 11 {
		false
	} // GB8
	else if current in [u32(4), 5, 8]! || previous == 7 {
		false
	} // GB9/9a/9b
	else if indic == 1 && state.indic == 2 {
		false
	} // GB9c
	else if pictographic && state.pictographic_zwj {
		false
	} // GB11
	else if current == 6 && state.regional_odd {
		false
	} // GB12/13
	else {
		true
	} // GB999
	state.pictographic_zwj = current == 5 && state.pictographic_extend
	state.pictographic_extend = pictographic || (current == 4 && state.pictographic_extend)
	state.indic = if indic == 1 {
		u32(1)
	} else if indic == 3 && state.indic != 0 {
		u32(2)
	} else if indic == 2 {
		state.indic
	} else {
		u32(0)
	}
	state.regional_odd = current == 6 && !state.regional_odd
	state.previous = current
	state.started = true
	return boundary
}

// The shared String reader has already validated this entire UTF-8 span.
// No normalization, temporary arrays, owner ARC or grapheme cache is needed.
fn swift_grapheme_count(bytes SwiftStringBytes) i64 {
	mut state := SwiftGraphemeState{}
	mut offset := u64(0)
	mut count := i64(0)
	for offset < bytes.count {
		first := unsafe { *(&u8(bytes.address + offset)) }
		offset++
		mut scalar := u32(first)
		if first >= 128 {
			width := if first < 224 {
				2
			} else if first < 240 {
				3
			} else {
				4
			}
			scalar = u32(first & u8(0x7f >> width))
			for _ in 1 .. width {
				scalar = (scalar << 6) | u32(unsafe { *(&u8(bytes.address + offset)) } & 63)
				offset++
			}
		}
		if swift_grapheme_break(mut state, scalar) { count++ }
	}
	return count
}

struct SwiftStringCountFailure {}

fn (_ &SwiftStringCountFailure) msg() string {
	return 'iOS: invalid or unsupported Swift String count input'
}

fn (_ &SwiftStringCountFailure) code() int { return 1 }

__global swift_string_count_failure_value = SwiftStringCountFailure{}

fn swift_string_count_failure() IError { return unsafe { &swift_string_count_failure_value } }

// ARM64: borrowed String x0/x1, signed Int in x0. Keep registered owners
// borrowed under the recursive lock for the entire validated scan (1 MiB cap).
fn swift_string_count_checked(first u64, second u64) !i64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_string_count_failure()
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	words := u64(C.__builtin_alloca(16))
	scratch := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(words)) = SwiftStringWords{first, second} }
	bytes := swift_replace_bytes(words, scratch)!
	marked_ascii := if second & (u64(1) << 61) != 0 {
		second & (u64(1) << 62) != 0
	} else {
		first & (u64(1) << 63) != 0
	}
	if marked_ascii && !swift_replace_ascii(bytes) { return swift_string_count_failure() }
	return swift_grapheme_count(bytes)
}

fn swift_string_count(first u64, second u64) i64 {
	return swift_string_count_checked(first, second) or { panic(err) }
}
