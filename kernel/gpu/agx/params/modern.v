// SPDX-License-Identifier: GPL-2.0-or-later
module params

// Match Asahi GET_TIME's reduced rational conversion, including u64 wrapping.
// Legacy GET_TIME continues to return raw ticks in timer_frequency_hz units.
pub fn timestamp_ns(raw u64, frequency u64) u64 {
	if frequency == 0 { return 0 }
	mut a, mut b := frequency, u64(1_000_000_000)
	for b != 0 { a, b = b, a % b }
	return (raw * (u64(1_000_000_000) / a)) / (frequency / a)
}
