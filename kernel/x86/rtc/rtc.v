// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The PC's battery-backed clock: the one clock that keeps going while the
// machine is in a suspend to RAM, and the one thing in it that can end one at
// a set time.
//
// The kernel does not keep its time here -- the boot loader says what time it
// is at boot and a counter carries on from there -- and reads this clock for
// two things only. How long a deep sleep lasted: the counter stops or starts
// again with the power, this does not. And the alarm: with the alarm
// interrupt enabled in the clock and its wake event enabled in ACPI, the
// chipset powers the machine up when hours, minutes and seconds match.
//
// The clock counts in whole seconds, so a sleep is measured to within one.
// The alarm has no date in it: it can be set at most a day ahead.
@[has_globals]
module rtc

import klock
import x86.kio

const port_index = u16(0x70)
const port_data = u16(0x71)

const reg_seconds = u8(0x00)
const reg_seconds_alarm = u8(0x01)
const reg_minutes = u8(0x02)
const reg_minutes_alarm = u8(0x03)
const reg_hours = u8(0x04)
const reg_hours_alarm = u8(0x05)
const reg_day = u8(0x07)
const reg_month = u8(0x08)
const reg_year = u8(0x09)
const reg_a = u8(0x0a)
const reg_b = u8(0x0b)
const reg_c = u8(0x0c)

const a_update_in_progress = u8(0x80)
const b_24_hour = u8(0x02)
const b_binary = u8(0x04)
const b_alarm_interrupt = u8(0x20)
const c_alarm = u8(0x20)
const hour_pm = u8(0x80)

// The longest the alarm can be set ahead: it matches a time of day.
pub const alarm_limit_seconds = u64(24 * 3600 - 1)

// An update takes under 2 ms and happens once a second; a read that keeps
// finding one in progress is a clock that is not there.
const update_spins = 100000
const read_attempts = 5

__global (
	rtc_lock klock.Lock
)

struct Reading {
mut:
	second u8
	minute u8
	hour   u8
	day    u8
	month  u8
	year   u8
	mode   u8
}

fn read_register(register u8) u8 {
	// Bit 7 of the index port gates NMI on a PC; it is left clear.
	kio.port_out[u8](port_index, register)
	return kio.port_in[u8](port_data)
}

fn write_register(register u8, value u8) {
	kio.port_out[u8](port_index, register)
	kio.port_out[u8](port_data, value)
}

fn from_bcd(value u8) u8 {
	return (value & 0x0f) + (value >> 4) * 10
}

fn to_bcd(value u8) u8 {
	return ((value / 10) << 4) | (value % 10)
}

// One pass over the time registers, taken while no update is under way.
fn read_once() ?Reading {
	mut spins := 0
	for read_register(reg_a) & a_update_in_progress != 0 {
		spins++
		if spins > update_spins {
			return none
		}
	}
	return Reading{
		second: read_register(reg_seconds)
		minute: read_register(reg_minutes)
		hour:   read_register(reg_hours)
		day:    read_register(reg_day)
		month:  read_register(reg_month)
		year:   read_register(reg_year)
		mode:   read_register(reg_b)
	}
}

fn same(a Reading, b Reading) bool {
	return a.second == b.second && a.minute == b.minute && a.hour == b.hour && a.day == b.day
		&& a.month == b.month && a.year == b.year
}

// Days from 1970-01-01 to the given date of the Gregorian calendar.
fn days_from_civil(year i64, month i64, day i64) i64 {
	y := if month <= 2 { year - 1 } else { year }
	era := (if y >= 0 { y } else { y - 399 }) / 400
	yoe := y - era * 400
	shifted := if month > 2 { month - 3 } else { month + 9 }
	doy := (153 * shifted + 2) / 5 + day - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
}

// What the clock says, in seconds since 1970. None when it cannot be read,
// or says something that is not a time. Two readings that agree are taken:
// one alone may straddle the clock's own update.
pub fn now() ?u64 {
	rtc_lock.acquire()
	defer {
		rtc_lock.release()
	}
	mut previous := read_once()?
	for _ in 0 .. read_attempts {
		current := read_once()?
		if same(previous, current) {
			return seconds_of(current)
		}
		previous = current
	}
	return none
}

fn seconds_of(reading Reading) ?u64 {
	binary := reading.mode & b_binary != 0
	mut hour := reading.hour
	mut pm := false
	if reading.mode & b_24_hour == 0 {
		pm = hour & hour_pm != 0
		hour &= ~hour_pm
	}
	mut second := reading.second
	mut minute := reading.minute
	mut day := reading.day
	mut month := reading.month
	mut year := reading.year
	if !binary {
		second = from_bcd(second)
		minute = from_bcd(minute)
		hour = from_bcd(hour)
		day = from_bcd(day)
		month = from_bcd(month)
		year = from_bcd(year)
	}
	if reading.mode & b_24_hour == 0 {
		// 12 is midnight or noon.
		hour = (hour % 12) + if pm { u8(12) } else { u8(0) }
	}
	if second > 59 || minute > 59 || hour > 23 || day < 1 || day > 31 || month < 1 || month > 12
		|| year > 99 {
		return none
	}
	// Two digits of year: this kernel was not around before 2000.
	days := days_from_civil(2000 + i64(year), i64(month), i64(day))
	if days < 0 {
		return none
	}
	return u64(days) * 86400 + u64(hour) * 3600 + u64(minute) * 60 + u64(second)
}

// Have the clock raise its alarm `seconds` from now, between one second and
// alarm_limit_seconds. False when the clock cannot be read or the time is
// out of range; nothing is set then.
pub fn set_alarm(seconds u64) bool {
	if seconds == 0 || seconds > alarm_limit_seconds {
		return false
	}
	current := now() or { return false }
	target := (current + seconds) % 86400
	rtc_lock.acquire()
	defer {
		rtc_lock.release()
	}
	mode := read_register(reg_b)
	binary := mode & b_binary != 0
	mut hour := u8(target / 3600)
	minute := u8((target / 60) % 60)
	second := u8(target % 60)
	mut pm := u8(0)
	if mode & b_24_hour == 0 {
		if hour >= 12 {
			pm = hour_pm
		}
		hour = hour % 12
		if hour == 0 {
			hour = 12
		}
	}
	// No alarm while its time is half written.
	write_register(reg_b, mode & ~b_alarm_interrupt)
	write_register(reg_seconds_alarm, if binary { second } else { to_bcd(second) })
	write_register(reg_minutes_alarm, if binary { minute } else { to_bcd(minute) })
	write_register(reg_hours_alarm, (if binary { hour } else { to_bcd(hour) }) | pm)
	// Reading the flags clears them: an alarm from before is not this one.
	read_register(reg_c)
	write_register(reg_b, (mode & ~b_alarm_interrupt) | b_alarm_interrupt)
	return true
}

// Switch the alarm off. True if it had gone off.
pub fn cancel_alarm() bool {
	rtc_lock.acquire()
	defer {
		rtc_lock.release()
	}
	mode := read_register(reg_b)
	write_register(reg_b, mode & ~b_alarm_interrupt)
	return read_register(reg_c) & c_alarm != 0
}
