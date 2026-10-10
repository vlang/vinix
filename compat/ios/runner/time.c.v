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
fn C.ios_mktime(voidptr) i64
fn C.ios_clock_ticks() i64
fn C.ios_tzname() voidptr
fn C.tzset()

fn darwin_mktime(value voidptr) i64 {
	if value == unsafe { nil } { darwin_set_errno(14); return -1 }
	previous := unsafe { *C.ios_errno_address() }
	// -1 is also a valid instant immediately before the epoch. Clear native
	// errno to distinguish that timestamp from an actual conversion failure.
	darwin_set_errno(0)
	result := C.ios_mktime(value)
	native := unsafe { *C.ios_errno_address() }
	if result == -1 && native != 0 { darwin_set_errno(darwin_native_error(native)) }
	else { darwin_set_errno(previous) }
	return result
}

fn darwin_clock_ticks() i64 {
	previous := unsafe { *C.ios_errno_address() }
	result := C.ios_clock_ticks()
	if result == -1 { darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() })) }
	else { darwin_set_errno(previous) }
	return result
}

fn darwin_tzset() {
	previous := unsafe { *C.ios_errno_address() }
	C.tzset()
	native := unsafe { *C.ios_errno_address() }
	if native != previous { darwin_set_errno(darwin_native_error(native)) }
}

fn darwin_timezone_names() u64 {
	// musl initializes this native array lazily. Configure it before exposing
	// its address; later tzset/mktime calls update the same array in place.
	previous := unsafe { *C.ios_errno_address() }
	C.tzset()
	darwin_set_errno(previous)
	return u64(C.ios_tzname())
}

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
		'_mktime' { u64(unsafe { voidptr(darwin_mktime) }) }
		'_clock' { u64(unsafe { voidptr(darwin_clock_ticks) }) }
		'_tzset' { u64(unsafe { voidptr(darwin_tzset) }) }
		'_tzname' { darwin_timezone_names() }
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
