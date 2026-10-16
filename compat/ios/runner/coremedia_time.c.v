// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// The iOS ABI passes this 24-byte record indirectly, and returns it through x8.
struct CMTime {
	value i64
	scale i32
	flags u32
	epoch i64
}

fn cm_time_make(value i64, scale i32) CMTime {
	return cm_time_make_epoch(value, scale, 0)
}

fn cm_time_make_epoch(value i64, scale i32, epoch i64) CMTime {
	if scale <= 0 { return CMTime{} }
	return CMTime{value, scale, 1, epoch}
}

fn cm_time_seconds(time CMTime) f64 {
	// Invalid and indefinite take precedence over either infinity flag.
	if time.flags & 17 != 1 { return math.nan() }
	if time.flags & 4 != 0 { return math.inf(1) }
	if time.flags & 8 != 0 { return math.inf(-1) }
	return f64(time.value) / f64(time.scale)
}

fn cm_time_make_seconds(seconds f64, preferred_scale i32) CMTime {
	if preferred_scale <= 0 { return CMTime{} }
	// Native CoreMedia converts NaN to a rounded zero at the requested scale.
	if math.is_nan(seconds) { return CMTime{0, preferred_scale, 3, 0} }
	mut scale := preferred_scale
	mut magnitude := math.abs(seconds * f64(scale))
	for magnitude > 9223372036854775808.0 {
		if scale == 1 { return CMTime{0, 0, if seconds < 0 { u32(9) } else { u32(5) }, 0} }
		scale /= 2
		magnitude = math.abs(seconds * f64(scale))
	}
	// Truncate toward zero, including half ticks. Guard the f64-to-i64 cast:
	// INT64_MAX rounds to 2^63 in f64, which native clamps symmetrically.
	mut value := if magnitude == 9223372036854775808.0 { i64(9223372036854775807) } else { i64(magnitude) }
	if seconds < 0 { value = -value }
	flags := if f64(value) / f64(scale) == seconds { u32(1) } else { u32(3) }
	return CMTime{value, scale, flags, 0}
}

fn coremedia_time_symbol(symbol string) ?u64 {
	return match symbol {
		'_CMTimeMake' { u64(unsafe { voidptr(cm_time_make) }) }
		'_CMTimeMakeWithEpoch' { u64(unsafe { voidptr(cm_time_make_epoch) }) }
		'_CMTimeMakeWithSeconds' { u64(unsafe { voidptr(cm_time_make_seconds) }) }
		'_CMTimeGetSeconds' { u64(unsafe { voidptr(cm_time_seconds) }) }
		else { return none }
	}
}
