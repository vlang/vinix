// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

// Host-test replacement for hardware seeding only. The production algorithm
// is copied unchanged by run-krandom.sh. Predictable bytes are never trusted.
fn architecture_seed(mut output [64]u8) bool {
	for i in 0 .. output.len {
		output[i] = u8(i)
	}
	return false
}
