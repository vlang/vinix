// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The unconstrained overload borrows source and supplies DefaultStringInterpolation
// as _print_unlocked's target. Reuse the bounded printing profile and its owned
// temporary/deferred release; String.init(describing:) would consume the input.
fn swift_generic_interpolation_checked(source u64, metadata u64, destination u64) ! {
	swift_print_active()!
	if destination == 0 || destination & 7 != 0 || destination > ~u64(0) - 15 {
		return swift_print_failure()
	}
	target := swift_interpolation_metadata()
	swift_print_unlocked_checked(source, destination, metadata, target, target - 16 + 160)!
}

fn swift_generic_interpolation(source u64, metadata u64, destination u64) {
	swift_generic_interpolation_checked(source, metadata, destination) or { panic(err) }
}
