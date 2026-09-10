// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Civil-time helpers shared by the Clock application and the taskbar clock.
// Vinix has a real time clock only in the sense that Limine hands the kernel a
// boot epoch, so it comes from clock_gettime(CLOCK_REALTIME) and the calendar
// arithmetic is done here rather than through libc, which keeps the desktop
// independent of what the target's time zone database does or does not have.
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

// taskbar_clock_strings_at stays deliberately compact: its two lines fit in
// the fixed status area at every desktop scale, leaving the remaining taskbar
// width entirely for window buttons.
fn (d &Desktop) taskbar_clock_strings_at(seconds i64) (string, string) {
	if seconds < 0 {
		return '--:--:--'.clone(), 'Clock unavailable'.clone()
	}
	civil := civil_from_epoch(seconds + d.tz_offset_seconds)
	hour := pad2(civil.hour)
	minute := pad2(civil.minute)
	second := pad2(civil.second)
	time_text := '${hour}:${minute}:${second}'
	unsafe {
		hour.free()
		minute.free()
		second.free()
	}
	day := civil.day.str()
	date_text := '${weekday_names[civil.weekday]} ${day} ${month_names[civil.month - 1]}'
	unsafe { day.free() }
	return time_text, date_text
}

// update_taskbar_clock is sampled on every compositor pass, but only formats
// and invalidates a frame when the displayed second changes. That preserves
// the idle renderer while keeping the status area alive after boot.
fn (mut d Desktop) update_taskbar_clock() {
	seconds, _ := desktop_realtime()
	d.update_taskbar_clock_at(seconds)
}

// update_taskbar_clock_at keeps the time source separate from updating the
// retained labels, which also makes the layout test deterministic.
fn (mut d Desktop) update_taskbar_clock_at(seconds i64) {
	if d.taskbar_clock_sampled && d.taskbar_clock_seconds == seconds {
		return
	}
	time_text, date_text := d.taskbar_clock_strings_at(seconds)
	if d.taskbar_clock_time.len > 0 {
		unsafe { d.taskbar_clock_time.free() }
	}
	if d.taskbar_clock_date.len > 0 {
		unsafe { d.taskbar_clock_date.free() }
	}
	d.taskbar_clock_time = time_text
	d.taskbar_clock_date = date_text
	d.taskbar_clock_seconds = seconds
	d.taskbar_clock_sampled = true
	d.dirty = true
}

// monotonic_millis drives frame pacing.
fn monotonic_millis() i64 {
	now := desktop_monotonic_ms()
	if now == ~u64(0) || now > u64(0x7fffffffffffffff) {
		return 0
	}
	return i64(now)
}
