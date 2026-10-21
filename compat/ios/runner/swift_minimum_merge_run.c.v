// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift keeps signed counts below 64 unchanged, including negative values.
// For larger counts, retain the highest six bits and round up if any of the
// discarded bits were set. The result is at most 64, even for Int.max.
fn swift_minimum_merge_run_length(count i64) i64 {
	mut length := count
	mut remainder := i64(0)
	for length >= 64 {
		remainder |= length & 1
		length >>= 1
	}
	return length + remainder
}
