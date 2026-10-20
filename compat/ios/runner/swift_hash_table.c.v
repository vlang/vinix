// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

struct SwiftHashTableFailure {}

fn (_ &SwiftHashTableFailure) msg() string {
	return 'iOS: HashTable.previousHole requires a valid bucket, a power-of-two bitmap with set padding bits, and at least one hole'
}

fn (_ &SwiftHashTableFailure) code() int { return 1 }

__global swift_hash_table_failure_value = SwiftHashTableFailure{}

fn swift_hash_table_failure() IError { return unsafe { &swift_hash_table_failure_value } }

// Frozen ARM64 arguments: Bucket.offset in x0, Self.words/bucketMask in
// x1/x2; the returned Bucket is one word in x0. The caller borrows the complete
// bitmap span and keeps it stable. No container header, owner or ARC is used.
fn swift_hash_table_previous_checked(before u64, words u64, mask u64) !u64 {
	count := mask + u64(1)
	if words == 0 || words & 7 != 0 || count == 0 || count > 0x7fffffffffffffff
		|| count & mask != 0 || before > mask {
		return swift_hash_table_failure()
	}
	word_count := (mask >> 6) + 1
	if words > ~u64(0) - word_count * 8 { return swift_hash_table_failure() }
	if count < 64 && read64(words) | ((u64(1) << u32(count)) - 1) != ~u64(0) {
		return swift_hash_table_failure()
	}
	mut word := before >> 6
	bit := u32(before & 63)
	mut holes := ~read64(words + word * 8) & ((u64(1) << bit) - 1)
	if holes != 0 { return word * 64 + 63 - u64(bits.leading_zeros_64(holes)) }
	// Scan earlier words, wrapping once and finally considering the remainder
	// of the starting word. A completely occupied bitmap fails finitely.
	for _ in u64(0) .. word_count {
		word = if word == 0 { word_count - 1 } else { word - 1 }
		holes = ~read64(words + word * 8)
		if holes != 0 { return word * 64 + 63 - u64(bits.leading_zeros_64(holes)) }
	}
	return swift_hash_table_failure()
}

fn swift_hash_table_previous(before u64, words u64, mask u64) u64 {
	return swift_hash_table_previous_checked(before, words, mask) or { panic(err) }
}

fn swift_hash_table_symbol(symbol string) ?u64 {
	if symbol != '_$ss10_HashTableV12previousHole6beforeAB6BucketVAF_tF'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return u64(unsafe { voidptr(swift_hash_table_previous) })
}
