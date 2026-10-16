// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Core Animation's absolute time is the Mach clock expressed in seconds.
// The runner's Mach clock already has a nanosecond timebase on every host.
fn ca_current_media_time() f64 {
	return f64(darwin_mach_absolute_time()) / 1_000_000_000.0
}

fn quartzcore_time_symbol(symbol string) ?u64 {
	if symbol == '_CACurrentMediaTime' {
		return u64(unsafe { voidptr(ca_current_media_time) })
	}
	return none
}
