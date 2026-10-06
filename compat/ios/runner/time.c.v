// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_clock_gettime(i32, voidptr) i32
fn C.ios_clock_getres(i32, voidptr) i32
fn C.ios_nanosleep(voidptr, voidptr) i32
fn C.ios_localtime_r(voidptr, voidptr) voidptr
fn C.ios_gmtime_r(voidptr, voidptr) voidptr
fn C.ios_localtime(voidptr) voidptr
fn C.ios_gmtime(voidptr) voidptr
fn C.ios_strftime(&char, usize, &char, voidptr) usize

fn darwin_clock_id(clock i32) i32 {
	$if linux {
		return match clock {
			0 { i32(C.CLOCK_REALTIME) }
			4, 5, 6, 8, 9 { i32(C.CLOCK_MONOTONIC) }
			12 { i32(C.CLOCK_PROCESS_CPUTIME_ID) }
			16 { i32(C.CLOCK_THREAD_CPUTIME_ID) }
			else { i32(-1) }
		}
	}
	return clock
}

fn darwin_clock_gettime(clock i32, timestamp voidptr) i32 {
	id := darwin_clock_id(clock)
	if id < 0 || timestamp == unsafe { nil } { darwin_set_errno(22); return -1 }
	return C.ios_clock_gettime(id, timestamp)
}

fn darwin_clock_getres(clock i32, timestamp voidptr) i32 {
	id := darwin_clock_id(clock)
	if id < 0 { darwin_set_errno(22); return -1 }
	return C.ios_clock_getres(id, timestamp)
}

fn darwin_nanosleep(request voidptr, remainder voidptr) i32 { return C.ios_nanosleep(request, remainder) }

fn time_symbol(symbol string) ?u64 {
	return match symbol {
		'_clock_gettime' { u64(unsafe { voidptr(darwin_clock_gettime) }) }
		'_clock_getres' { u64(unsafe { voidptr(darwin_clock_getres) }) }
		'_nanosleep' { u64(unsafe { voidptr(darwin_nanosleep) }) }
		'_localtime_r' { u64(unsafe { voidptr(C.ios_localtime_r) }) }
		'_gmtime_r' { u64(unsafe { voidptr(C.ios_gmtime_r) }) }
		'_localtime' { u64(unsafe { voidptr(C.ios_localtime) }) }
		'_gmtime' { u64(unsafe { voidptr(C.ios_gmtime) }) }
		'_strftime' { u64(unsafe { voidptr(C.ios_strftime) }) }
		else { return none }
	}
}
