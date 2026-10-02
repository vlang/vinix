// SPDX-License-Identifier: GPL-2.0-or-later
module sys

import errno
import security
import time
import usercopy

// Linux's 64-bit timex layout, common to amd64 and aarch64 (208 bytes).
struct ClockTimex {
mut:
	modes       u32
	offset      i64
	freq        i64
	maxerror    i64
	esterror    i64
	status      int
	constant    i64
	precision   i64
	tolerance   i64
	time_sec    i64
	time_subsec i64
	tick        i64
	ppsfreq     i64
	jitter      i64
	shift       int
	stabil      i64
	jitcnt      i64
	calcnt      i64
	errcnt      i64
	stbcnt      i64
	tai         int
	padding     [11]int
}

pub fn syscall_clock_settime(_ voidptr, clock_id int, pointer u64) (u64, u64) {
	if !security.permitted(security.system_clock_set) { return errno.err, errno.eperm }
	if clock_id != time.clock_type_realtime { return errno.err, errno.einval }
	mut value := time.TimeSpec{}
	if !usercopy.copy_from_user(voidptr(unsafe { &value }), pointer, sizeof(time.TimeSpec)) {
		return errno.err, errno.efault
	}
	return set_wall_clock(value)
}

fn set_wall_clock(value time.TimeSpec) (u64, u64) {
	// Leave a year's headroom so ordinary ticking cannot overflow immediately.
	if value.tv_sec < 0 || value.tv_sec > 9191836036
		|| value.tv_nsec < 0 || value.tv_nsec >= 1000000000 {
		return errno.err, errno.einval
	}
	if !time.set_realtime(value, security.securelevel() > 1) { return errno.err, errno.eperm }
	return 0, 0
}

pub fn syscall_settimeofday(_ voidptr, tv u64, tz u64) (u64, u64) {
	if !security.permitted(security.system_clock_set) { return errno.err, errno.eperm }
	if tz != 0 {
		mut zone := [2]int{}
		if !usercopy.copy_from_user(voidptr(unsafe { &zone[0] }), tz, sizeof(int) * 2) {
			return errno.err, errno.efault
		}
		// RTC timezone warping is not supported. Accept the UTC convention only.
		if zone[0] != 0 || zone[1] != 0 { return errno.err, errno.eopnotsupp }
	}
	if tv == 0 { return 0, 0 }
	mut value := [2]i64{}
	if !usercopy.copy_from_user(voidptr(unsafe { &value[0] }), tv, sizeof(i64) * 2) {
		return errno.err, errno.efault
	}
	if value[1] < 0 || value[1] >= 1000000 { return errno.err, errno.einval }
	return set_wall_clock(time.TimeSpec{value[0], value[1] * 1000})
}

pub fn syscall_clock_adjtime(_ voidptr, clock_id int, pointer u64) (u64, u64) {
	if clock_id != time.clock_type_realtime { return errno.err, errno.einval }
	return syscall_adjtimex(unsafe { nil }, pointer)
}

pub fn syscall_adjtimex(_ voidptr, pointer u64) (u64, u64) {
	mut request := ClockTimex{}
	if !usercopy.copy_from_user(voidptr(unsafe { &request }), pointer, sizeof(ClockTimex)) {
		return errno.err, errno.efault
	}
	query := request.modes == 0 || request.modes == 0xa001 // ADJ_OFFSET_SS_READ
	if !query && !security.permitted(security.system_clock_set) { return errno.err, errno.eperm }
	mut mode := 0
	mut slew := i64(0)
	if request.modes == 0x8001 { // ADJ_OFFSET_SINGLESHOT, always microseconds
		if request.offset > 9223372036854775 || request.offset < -9223372036854775 {
			return errno.err, errno.einval
		}
		mode = 2
		slew = request.offset * 1000
	} else if !query {
		// A bounded oscillator correction is real discipline. PLL/PPS, leap
		// seconds and other NTP modes remain unsupported and fail explicitly.
		if request.modes & ~u32(0x12) != 0 { return errno.err, errno.eopnotsupp }
		if request.modes & 0x10 != 0 && request.status != 0x40 {
			return errno.err, errno.eopnotsupp
		}
		if request.modes & 2 != 0 {
			if request.freq < -time.max_clock_frequency || request.freq > time.max_clock_frequency {
				return errno.err, errno.einval
			}
			mode = 1
		}
	}
	frequency, previous := time.adjust_clock(mode, request.freq, slew)
	now := time.clock_now(time.clock_type_realtime) or { return errno.err, errno.einval }
	mut result := ClockTimex{
		modes:       request.modes
		offset:      previous / 1000
		freq:        frequency
		status:      0x40 // STA_UNSYNC: no PLL/PPS lock is claimed
		precision:   i64((time.clock_resolution_ns() + 999) / 1000)
		tolerance:   time.max_clock_frequency
		time_sec:    now.tv_sec
		time_subsec: now.tv_nsec / 1000
		tick:        i64(1000000 / time.timer_frequency)
	}
	if !usercopy.copy_to_user(pointer, voidptr(unsafe { &result }), sizeof(ClockTimex)) {
		return errno.err, errno.efault
	}
	return 5, 0 // TIME_ERROR, consistently with STA_UNSYNC
}
