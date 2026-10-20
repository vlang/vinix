// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Sequence's default cannot expose contiguous storage. It returns .none
// without inspecting Self, its witnesses, the closure or the closure context.
// The Result value witness encodes nil using its actual spare inhabitants.
fn swift_sequence_storage_checked(result u64, output u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || output == 0 {
		return swift_sequence_failure()
	}
	value := swift_sequence_value_checked(result)!
	store_address := read64(read64(result - 8) + 56)
	if store_address == 0 || store_address & 3 != 0
		|| output & (value.alignment - 1) != 0
		|| output > ~u64(0) - value.size - 1 {
		return swift_sequence_failure()
	}
	store := unsafe { SwiftSequenceStoreTag(voidptr(store_address)) }
	store(output, 1, 1, result)
}

// ARM64: closure/context x0/x1, Self/Result metadata x2/x3, table x4,
// borrowed Self x20, indirect Optional<Result> x8. The noninvoked rethrows
// closure produces no error; preserve the incoming Swift error register x21.
fn swift_sequence_storage(_body u64, _context u64, _sequence u64, result u64,
	_table u64, _receiver u64, output u64) {
	swift_sequence_storage_checked(result, output) or { panic(err) }
}
