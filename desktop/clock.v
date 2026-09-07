// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The taskbar clock. Vinix has a real time clock only in the sense that
// Limine hands the kernel a boot epoch, so the time comes from
// clock_gettime(CLOCK_REALTIME) and the calendar arithmetic is done here
// rather than through libc, which keeps the desktop independent of what the
// target's time zone database does or does not contain.
module main

// When this desktop was built, stamped in by build-desktop-aarch64.sh. It is
// shown beside the clock so that a machine booted from a freshly deployed
// image can be told apart from one still running the last, which is otherwise
// guesswork: the desktop looks identical either way. A build that did not go
// through the script — a host test run, say — says `dev`.
const build_stamp = $d('vinix_build_stamp', 'dev')

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
	return if value < 10 { '0${value}' } else { '${value}' }
}

// The first line puts battery percentage immediately to the left of the time;
// the second keeps the existing date. Settings shares the five-second cache,
// so composing a frame does not open the device again within that interval.
fn (d &Desktop) clock_strings() (string, string) {
	percent := read_battery(false)
	seconds, _ := desktop_realtime()
	if seconds < 0 {
		return battery_clock_label(percent, '--:--:--'), ''
	}
	civil := civil_from_epoch(seconds + d.tz_offset_seconds)
	time_text := '${pad2(civil.hour)}:${pad2(civil.minute)}:${pad2(civil.second)}'
	date_text := '${weekday_names[civil.weekday]} ${civil.day} ${month_names[civil.month - 1]}'
	label := battery_clock_label(percent, time_text)
	unsafe { time_text.free() }
	return label, date_text
}

// monotonic_millis drives the frame pacing and the redraw clock.
fn monotonic_millis() i64 {
	now := desktop_monotonic_ms()
	if now == ~u64(0) || now > u64(0x7fffffffffffffff) {
		return 0
	}
	return i64(now)
}

// update_clock refreshes the taskbar's two lines and reports a change as
// something worth redrawing for. It is what makes an otherwise idle desktop
// recompose once a second instead of sixty times.
fn (mut d Desktop) update_clock() {
	time_text, date_text := d.clock_strings()
	if time_text != d.clock_time || date_text != d.clock_date {
		d.clock_time = time_text
		d.clock_date = date_text
		d.dirty = true
	}
}
