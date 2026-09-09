// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Civil-time helpers shared by the clock application. Vinix has a real time
// clock only in the sense that Limine hands the kernel a boot epoch, so it comes from
// clock_gettime(CLOCK_REALTIME) and the calendar arithmetic is done here
// rather than through libc, which keeps the desktop independent of what the
// target's time zone database does or does not contain.
module main

const weekday_names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const month_names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
	'Dec']

struct CivilTime {
	year    int
	month   int
	day     int
	hour    int
	minute  int
	second  int
	weekday int
}

// civil_from_epoch is Howard Hinnant's days-to-civil algorithm, which is exact
// for every proleptic Gregorian date and needs no tables.
fn civil_from_epoch(epoch i64) CivilTime {
	mut days := epoch / 86400
	mut rem := epoch % 86400
	if rem < 0 {
		rem += 86400
		days--
	}

	weekday := int(((days % 7) + 11) % 7) // 1970-01-01 was a Thursday

	z := days + 719468
	era := if z >= 0 { z } else { z - 146096 } / 146097
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	mut year := yoe + era * 400
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	day := doy - (153 * mp + 2) / 5 + 1
	month := if mp < 10 { mp + 3 } else { mp - 9 }
	if month <= 2 {
		year++
	}

	return CivilTime{
		year: int(year)
		month: int(month)
		day: int(day)
		hour: int(rem / 3600)
		minute: int((rem % 3600) / 60)
		second: int(rem % 60)
		weekday: weekday
	}
}

@[inline]
fn pad2(value int) string {
	text := value.str()
	if value >= 10 {
		return text
	}
	padded := '0${text}'
	unsafe { text.free() }
	return padded
}

// monotonic_millis drives frame pacing.
fn monotonic_millis() i64 {
	now := desktop_monotonic_ms()
	if now == ~u64(0) || now > u64(0x7fffffffffffffff) {
		return 0
	}
	return i64(now)
}
