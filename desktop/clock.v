// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Civil-time helpers shared by the Clock application and the taskbar clock.
// Vinix has a real time clock only in the sense that Limine hands the kernel a
// boot epoch, so it comes from clock_gettime(CLOCK_REALTIME) and the calendar
// arithmetic is done here rather than through libc, which keeps the desktop
// independent of what the target's time zone database does or does not have.
module main

// English abbreviations, for code that has not yet moved to the translated
// names below. Text the user reads comes from date_weekday_short and friends.
const weekday_names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const month_names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
	'Dec']

// The names a date is written with, in the desktop's language. Weekdays count
// from Sunday as CivilTime does, months from one. The table owns every name:
// none of them may be freed.
//
// Each context has names of its own because languages differ in more than
// spelling. Russian writes a month in the genitive after a day (28 сентября)
// and in the nominative on its own (Сентябрь 2026, in calendar.v), and spells
// out the long date that English abbreviates.

// date_weekday_short is the abbreviation the taskbar and the calendar's
// column headings use.
fn date_weekday_short(weekday int) string {
	return match weekday {
		0 { tr('date.weekday.short.sun') }
		1 { tr('date.weekday.short.mon') }
		2 { tr('date.weekday.short.tue') }
		3 { tr('date.weekday.short.wed') }
		4 { tr('date.weekday.short.thu') }
		5 { tr('date.weekday.short.fri') }
		else { tr('date.weekday.short.sat') }
	}
}

// date_month_short is the abbreviation written after a day number.
fn date_month_short(month int) string {
	return match month {
		1 { tr('date.month.short.jan') }
		2 { tr('date.month.short.feb') }
		3 { tr('date.month.short.mar') }
		4 { tr('date.month.short.apr') }
		5 { tr('date.month.short.may') }
		6 { tr('date.month.short.jun') }
		7 { tr('date.month.short.jul') }
		8 { tr('date.month.short.aug') }
		9 { tr('date.month.short.sep') }
		10 { tr('date.month.short.oct') }
		11 { tr('date.month.short.nov') }
		else { tr('date.month.short.dec') }
	}
}

// date_long_weekday and date_long_month are the names in the long date the
// Clock and Calendar show. English keeps the abbreviations it has always
// used there.
fn date_long_weekday(weekday int) string {
	return match weekday {
		0 { tr('date.long.weekday.sun') }
		1 { tr('date.long.weekday.mon') }
		2 { tr('date.long.weekday.tue') }
		3 { tr('date.long.weekday.wed') }
		4 { tr('date.long.weekday.thu') }
		5 { tr('date.long.weekday.fri') }
		else { tr('date.long.weekday.sat') }
	}
}

fn date_long_month(month int) string {
	return match month {
		1 { tr('date.long.month.jan') }
		2 { tr('date.long.month.feb') }
		3 { tr('date.long.month.mar') }
		4 { tr('date.long.month.apr') }
		5 { tr('date.long.month.may') }
		6 { tr('date.long.month.jun') }
		7 { tr('date.long.month.jul') }
		8 { tr('date.long.month.aug') }
		9 { tr('date.long.month.sep') }
		10 { tr('date.long.month.oct') }
		11 { tr('date.long.month.nov') }
		else { tr('date.long.month.dec') }
	}
}

// date_long_text writes out a date with its weekday: "Mon, Sep 28, 2026",
// "понедельник, 28 сентября 2026 г.", "lunes, 28 de septiembre de 2026". The
// result belongs to the caller.
fn date_long_text(year int, month int, day int, weekday int) string {
	day_text := day.str()
	year_text := year.str()
	date := tr_fill3('date.long.day_month_year', day_text, date_long_month(month), year_text)
	text := tr_fill2('date.long', date_long_weekday(weekday), date)
	unsafe {
		day_text.free()
		year_text.free()
		date.free()
	}
	return text
}

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
		return if d.settings.clock_show_seconds { '--:--:--'.clone() } else { '--:--'.clone() },
			tr('clock.unavailable').clone()
	}
	civil := civil_from_epoch(seconds + d.tz_offset_seconds)
	minute := pad2(civil.minute)
	mut hour := ''
	if d.settings.clock_24_hour {
		hour = pad2(civil.hour)
	} else {
		mut display_hour := civil.hour % 12
		if display_hour == 0 {
			display_hour = 12
		}
		hour = display_hour.str()
	}
	mut time_text := ''
	if d.settings.clock_show_seconds {
		second := pad2(civil.second)
		time_text = '${hour}:${minute}:${second}'
		unsafe { second.free() }
	} else {
		time_text = '${hour}:${minute}'
	}
	unsafe {
		hour.free()
		minute.free()
	}
	if !d.settings.clock_24_hour {
		// Each language places its own AM and PM around the time.
		clock := time_text
		time_text = if civil.hour < 12 {
			tr_fill('date.time_am', clock)
		} else {
			tr_fill('date.time_pm', clock)
		}
		unsafe { clock.free() }
	}

	mut date_text := ''
	if d.settings.clock_show_date {
		day := civil.day.str()
		month := date_month_short(civil.month)
		date_text = if d.settings.clock_show_weekday {
			tr_fill3('date.weekday_day_month', date_weekday_short(civil.weekday), day, month)
		} else {
			tr_fill2('date.day_month', day, month)
		}
		unsafe { day.free() }
	} else if d.settings.clock_show_weekday {
		date_text = date_weekday_short(civil.weekday).clone()
	}
	return time_text, date_text
}

// The executable's modification time records when this binary was built, even
// when a cached build is reused. Display it in the live clock's time zone.
fn (d &Desktop) taskbar_build_strings_at(seconds i64, gpu_driver_enabled bool) (string, string) {
	if seconds <= 0 {
		return tr_fill('clock.built', '--:--'), tr('clock.date_unavailable').clone()
	}
	civil := civil_from_epoch(seconds + d.tz_offset_seconds)
	hour := pad2(civil.hour)
	minute := pad2(civil.minute)
	day := pad2(civil.day)
	clock := '${hour}:${minute}'
	time_text := tr_fill('clock.built', clock)
	mut date_text := tr_fill2('date.day_month', day, date_month_short(civil.month))
	if gpu_driver_enabled {
		// A developer's marker rather than a word, the same in every language.
		plain := date_text
		date_text = '${plain} gpu+'
		unsafe { plain.free() }
	}
	unsafe {
		hour.free()
		minute.free()
		day.free()
		clock.free()
	}
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
	// The build stamp is formatted once, and again whenever something that
	// shapes the taskbar's text changes — the language among them — which is
	// what clears taskbar_clock_sampled.
	if d.taskbar_build_time.len == 0 || !d.taskbar_clock_sampled {
		build_time, build_date := d.taskbar_build_strings_at(desktop_build_epoch(),
			desktop_gpu_driver_enabled())
		if d.taskbar_build_time.len > 0 {
			unsafe { d.taskbar_build_time.free() }
		}
		if d.taskbar_build_date.len > 0 {
			unsafe { d.taskbar_build_date.free() }
		}
		d.taskbar_build_time = build_time
		d.taskbar_build_date = build_date
	}
	if d.taskbar_clock_sampled && d.taskbar_clock_seconds == seconds {
		return
	}
	time_text, date_text := d.taskbar_clock_strings_at(seconds)
	was_sampled := d.taskbar_clock_sampled
	d.taskbar_clock_seconds = seconds
	d.taskbar_clock_sampled = true
	// Without seconds on show the text changes once a minute; the other 59
	// ticks have nothing to draw.
	if was_sampled && time_text == d.taskbar_clock_time && date_text == d.taskbar_clock_date {
		unsafe {
			time_text.free()
			date_text.free()
		}
		return
	}
	// A new day can change what windows show too (Calendar marks today), so
	// only the time ticking over is a taskbar-only change.
	date_changed := date_text != d.taskbar_clock_date
	if d.taskbar_clock_time.len > 0 {
		unsafe { d.taskbar_clock_time.free() }
	}
	if d.taskbar_clock_date.len > 0 {
		unsafe { d.taskbar_clock_date.free() }
	}
	d.taskbar_clock_time = time_text
	d.taskbar_clock_date = date_text
	if was_sampled && !date_changed {
		d.damage_taskbar()
	} else {
		d.dirty = true
	}
}

// taskbar_clock_idle_interval ends an idle wait just after the wall clock
// next changes what the taskbar shows. The wait was a second from whenever
// the last pass ran, so the time could turn over up to a second late. A few
// milliseconds of margin keep the wake from landing just before the change,
// since the caller also subtracts the time its own pass took.
fn (d &Desktop) taskbar_clock_idle_interval(interval i64) i64 {
	seconds, nanoseconds := desktop_realtime()
	if seconds < 0 || nanoseconds < 0 || nanoseconds >= 1_000_000_000 {
		return interval
	}
	mut wait := (1_000_000_000 - nanoseconds) / 1_000_000 + 5
	if !d.settings.clock_show_seconds {
		wait += (59 - seconds % 60) * 1000
	}
	return if wait < interval { wait } else { interval }
}

// monotonic_millis drives frame pacing.
fn monotonic_millis() i64 {
	now := desktop_monotonic_ms()
	if now == ~u64(0) || now > u64(0x7fffffffffffffff) {
		return 0
	}
	return i64(now)
}

// Shared by the ordinary desktop loop and first-launch registration. Keep it
// with the monotonic clock so staged registration tests need not import the
// executable's main entry point.
fn sleep_to_next_frame(frame_started i64, interval i64) {
	elapsed := monotonic_millis() - frame_started
	wait := desktop_frame_wait_ms(elapsed, interval)
	if wait > 0 {
		desktop_sleep_ms(wait)
	}
}
