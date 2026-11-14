// SPDX-License-Identifier: GPL-2.0-or-later
module selecttimeoutfixture

// A remainder may equal the supplied duration when the kernel's two samples
// coincide. Bound it by the enclosing user samples and the ABI's truncation.
// Validate canonical output before arithmetic, including noncanonical input's
// normalized duration. Keep this allocation-free helper shared with controls.
pub fn remaining_within_bounds(seconds i64, subsecond i64, initial_ns i64, elapsed_ns i64, unit_ns i64) bool {
	if unit_ns !in [i64(1),1000] || initial_ns < 0 || elapsed_ns < 0
		|| seconds < 0 || subsecond < 0 || subsecond >= 1_000_000_000 / unit_ns {
		return false
	}
	if seconds > initial_ns / 1_000_000_000 { return false }
	whole := seconds * 1_000_000_000
	part := subsecond * unit_ns
	if part > initial_ns - whole { return false }
	left := whole + part
	lower := if elapsed_ns >= initial_ns { i64(0) } else { initial_ns - elapsed_ns }
	truncated_lower := if lower < unit_ns - 1 { i64(0) } else { lower - (unit_ns - 1) }
	return left >= truncated_lower
}
