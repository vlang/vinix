// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Sleep as /sys shows it, by Linux's names where Linux has one:
//
//	/sys/power/state              freeze mem; write one to sleep
//	/sys/power/mem_sleep          what mem means: [s2idle] deep
//	/sys/power/pm_test            [none] devices: rehearse instead of sleeping
//	/sys/power/pm_test_delay_ms   how long a rehearsal stays down (Vinix's)
//	/sys/power/suspend_stats/     success fail last_failed_dev last_failed_step,
//	                              and Vinix's last_wake, last_*_ms and
//	                              security_checks, security_changes, screen_dark
//	                              and screen_lit (screen.v)
//	/sys/power/profile_policy     [auto] manual: whether the CPU performance
//	                              profile follows the power source
//	/sys/power/lid/               state (open, closed, unknown), closes, and
//	                              action: suspend or ignore
//	/sys/class/wakeup/wakeupN/    name event_count wakeup_count, and Vinix's
//	                              enabled, which may be written
//	/sys/class/rtc/rtc0/wakealarm seconds since the epoch, or +seconds from
//	                              now, at which to wake; 0 cancels
//
// The write to `state` returns when the machine is awake again.
@[has_globals]
module syspower

import devcore
import errno
import event
import event.eventstruct
import fs
import katomic
import lib
import psupply
import sched
import time
import wakesrc

__global (
	// When the alarm goes off, on the monotonic clock; zero for no alarm.
	syspower_alarm_ns      u64
	// The same moment in seconds since the epoch, to read back.
	syspower_alarm_epoch   u64
	syspower_alarm_changed eventstruct.Event
)

// Publish the files and start the alarm. Called once /sys is mounted.
pub fn publish() {
	fs.sysfs_attribute('power/state', 0o644, show_state, store_state, unsafe { nil })
	fs.sysfs_attribute('power/mem_sleep', 0o644, show_mem_sleep, store_mem_sleep, unsafe { nil })
	fs.sysfs_attribute('power/pm_test', 0o644, show_pm_test, store_pm_test, unsafe { nil })
	fs.sysfs_attribute('power/pm_test_delay_ms', 0o644, show_test_delay, store_test_delay,
		unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/success', 0o444, show_success, unsafe { nil },
		unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/fail', 0o444, show_fail, unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/last_failed_dev', 0o444, show_failed_device,
		unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/last_failed_step', 0o444, show_failed_step,
		unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/last_wake', 0o444, show_last_wake, unsafe { nil },
		unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/last_suspend_ms', 0o444, show_last_suspend,
		unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/last_sleep_ms', 0o444, show_last_sleep, unsafe { nil },
		unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/last_resume_ms', 0o444, show_last_resume,
		unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/security_checks', 0o444, show_security_checks,
		unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/security_changes', 0o444, show_security_changes,
		unsafe { nil }, unsafe { nil })
	publish_screen()

	// The file's context is the source's number plus one, so that the first
	// is not the nil a file with no context has.
	for index in 0 .. wakesrc.source_count {
		context := voidptr(u64(index) + 1)
		mut base := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
		unsafe { *base = lib.new_text(40) }
		base.add('class/wakeup/wakeup')
		base.add_decimal(i64(index))
		directory := base.str()
		wakeup_file(directory, '/name', 0o444, show_wake_name, unsafe { nil }, context)
		wakeup_file(directory, '/event_count', 0o444, show_wake_events, unsafe { nil }, context)
		wakeup_file(directory, '/wakeup_count', 0o444, show_wake_wakeups, unsafe { nil },
			context)
		wakeup_file(directory, '/enabled', 0o644, show_wake_enabled, store_wake_enabled,
			context)
		unsafe { directory.free() }
	}

	fs.sysfs_attribute('power/lid/state', 0o444, show_lid_state, unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('power/lid/action', 0o644, show_lid_action, store_lid_action, unsafe { nil })
	fs.sysfs_attribute('power/lid/closes', 0o444, show_lid_closes, unsafe { nil }, unsafe { nil })
	psupply.publish()
	fs.sysfs_attribute('power/profile_policy', 0o644, show_profile_policy, store_profile_policy,
		unsafe { nil })

	fs.sysfs_attribute('class/rtc/rtc0/wakealarm', 0o644, show_alarm, store_alarm, unsafe { nil })
	fs.sysfs_attribute('class/rtc/rtc0/since_epoch', 0o444, show_epoch, unsafe { nil }, unsafe { nil })
	sched.new_kernel_thread(voidptr(alarm_thread), unsafe { nil }, true)
}

fn wakeup_file(directory string, name string, mode u32, show fs.SysfsShow, store fs.SysfsStore, context voidptr) {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(directory.len + name.len) }
	text.add(directory)
	text.add(name)
	path := text.str()
	fs.sysfs_attribute(path, mode, show, store, context)
	unsafe { path.free() }
}

fn number_line(mut text lib.Text, value u64) {
	text.add_unsigned(value)
	text.add_byte(`\n`)
}

// ── /sys/power ──────────────────────────────────────────────────────────────

fn show_state(_ voidptr, mut text lib.Text) {
	text.add('freeze mem\n')
}

fn store_state(_ voidptr, data &u8, length u64) u64 {
	word := fs.sysfs_word(data, length)
	kind := if word == 'freeze' {
		SleepDepth.idle
	} else if word == 'mem' {
		if mem_is_deep() { SleepDepth.deep } else { SleepDepth.idle }
	} else {
		return errno.einval
	}
	if sleeping() {
		return errno.ebusy
	}
	return if enter_sleep(kind) { u64(0) } else { u64(errno.eio) }
}

fn show_mem_sleep(_ voidptr, mut text lib.Text) {
	if !deep_available() {
		text.add('[s2idle]\n')
	} else if mem_is_deep() {
		text.add('s2idle [deep]\n')
	} else {
		text.add('[s2idle] deep\n')
	}
}

fn store_mem_sleep(_ voidptr, data &u8, length u64) u64 {
	word := fs.sysfs_word(data, length)
	if word == 's2idle' {
		set_mem_deep(false)
		return 0
	}
	if word == 'deep' && set_mem_deep(true) {
		return 0
	}
	return errno.einval
}

fn show_pm_test(_ voidptr, mut text lib.Text) {
	text.add(if rehearsal() == .devices { 'none [devices]\n' } else { '[none] devices\n' })
}

fn store_pm_test(_ voidptr, data &u8, length u64) u64 {
	word := fs.sysfs_word(data, length)
	if word == 'none' {
		set_rehearsal(.none)
	} else if word == 'devices' {
		set_rehearsal(.devices)
	} else {
		return errno.einval
	}
	return 0
}

fn show_test_delay(_ voidptr, mut text lib.Text) {
	number_line(mut text, test_delay_ms())
}

fn store_test_delay(_ voidptr, data &u8, length u64) u64 {
	value := fs.sysfs_unsigned(data, length) or { return errno.einval }
	if value == 0 || value > 600000 {
		return errno.einval
	}
	set_test_delay_ms(value)
	return 0
}

fn show_success(_ voidptr, mut text lib.Text) {
	number_line(mut text, syspower_stats.success)
}

fn show_fail(_ voidptr, mut text lib.Text) {
	number_line(mut text, syspower_stats.fail)
}

fn show_failed_device(_ voidptr, mut text lib.Text) {
	text.add(syspower_stats.failed_device)
	text.add_byte(`\n`)
}

fn show_failed_step(_ voidptr, mut text lib.Text) {
	text.add(syspower_stats.failed_step)
	text.add_byte(`\n`)
}

fn show_last_wake(_ voidptr, mut text lib.Text) {
	text.add(syspower_stats.last_wake)
	text.add_byte(`\n`)
}

fn show_last_suspend(_ voidptr, mut text lib.Text) {
	number_line(mut text, syspower_stats.last_suspend_ms)
}

fn show_last_sleep(_ voidptr, mut text lib.Text) {
	number_line(mut text, syspower_stats.last_sleep_ms)
}

fn show_last_resume(_ voidptr, mut text lib.Text) {
	number_line(mut text, syspower_stats.last_resume_ms)
}

fn show_security_checks(_ voidptr, mut text lib.Text) {
	number_line(mut text, syspower_stats.security_checks)
}

fn show_security_changes(_ voidptr, mut text lib.Text) {
	number_line(mut text, syspower_stats.security_changes)
}

// ── /sys/class/wakeup ───────────────────────────────────────────────────────

fn wake_source(context voidptr) wakesrc.Source {
	return unsafe { wakesrc.Source(int(u64(context) - 1)) }
}

fn show_wake_name(context voidptr, mut text lib.Text) {
	text.add(wakesrc.name(wake_source(context)))
	text.add_byte(`\n`)
}

fn show_wake_events(context voidptr, mut text lib.Text) {
	number_line(mut text, wakesrc.events(wake_source(context)))
}

fn show_wake_wakeups(context voidptr, mut text lib.Text) {
	number_line(mut text, wakesrc.wakeups(wake_source(context)))
}

fn show_wake_enabled(context voidptr, mut text lib.Text) {
	text.add(if wakesrc.allowed(wake_source(context)) { 'enabled\n' } else { 'disabled\n' })
}

fn store_wake_enabled(context voidptr, data &u8, length u64) u64 {
	word := fs.sysfs_word(data, length)
	if word == 'enabled' || word == '1' {
		wakesrc.allow(wake_source(context), true)
	} else if word == 'disabled' || word == '0' {
		wakesrc.allow(wake_source(context), false)
	} else {
		return errno.einval
	}
	return 0
}

// ── The alarm ───────────────────────────────────────────────────────────────

fn epoch_now() u64 {
	return u64(realtime_clock.tv_sec)
}

fn show_epoch(_ voidptr, mut text lib.Text) {
	number_line(mut text, epoch_now())
}

// Empty when no alarm is set, as on Linux.
fn show_alarm(_ voidptr, mut text lib.Text) {
	if katomic.load(&syspower_alarm_ns) != 0 {
		number_line(mut text, katomic.load(&syspower_alarm_epoch))
	}
}

fn store_alarm(_ voidptr, data &u8, length u64) u64 {
	word := fs.sysfs_word(data, length)
	relative := word.len > 1 && word[0] == `+`
	digits := if relative { unsafe { tos(word.str + 1, word.len - 1) } } else { word }
	value := fs.sysfs_unsigned(digits.str, u64(digits.len)) or { return errno.einval }
	now := epoch_now()
	if !relative && value == 0 {
		katomic.store(mut &syspower_alarm_ns, u64(0))
		event.trigger(mut syspower_alarm_changed, false)
		return 0
	}
	seconds := if relative {
		value
	} else if value > now {
		value - now
	} else {
		// A moment that has passed is refused, not treated as now.
		return errno.einval
	}
	if seconds > 366 * 24 * 3600 {
		return errno.einval
	}
	katomic.store(mut &syspower_alarm_epoch, now + seconds)
	katomic.store(mut &syspower_alarm_ns, devcore.now_ns() + seconds * 1000000000)
	event.trigger(mut syspower_alarm_changed, false)
	return 0
}

// Waits for the moment the alarm is set to, and reports it as a wake source.
// Until a suspend to RAM exists the kernel's own timer is the alarm: in a
// suspend to idle it keeps running.
fn alarm_thread() {
	for {
		generation := event.generation(mut syspower_alarm_changed)
		deadline := katomic.load(&syspower_alarm_ns)
		if deadline == 0 {
			event.await_one_from_generation(mut syspower_alarm_changed, true, generation) or {}
			continue
		}
		now := devcore.now_ns()
		if now >= deadline {
			if katomic.cas(mut &syspower_alarm_ns, deadline, u64(0)) {
				wakesrc.report(.alarm)
			}
			continue
		}
		remaining := deadline - now
		mut timer := time.new_timer(time.TimeSpec{i64(remaining / 1000000000), i64(remaining % 1000000000)})
		mut storage := [&syspower_alarm_changed, &timer.event]!
		mut events := unsafe { event.stack_list(&storage[0], storage.len) }
		event.await_from_generation(mut events, true, 0, generation) or {}
		timer.disarm()
		unsafe { free(timer) }
	}
}

// ── The lid ─────────────────────────────────────────────────────────────────

fn show_lid_state(_ voidptr, mut text lib.Text) {
	text.add(lid_state_name())
	text.add_byte(`\n`)
}

fn show_lid_action(_ voidptr, mut text lib.Text) {
	text.add(if lid_action() == .ignore { 'suspend [ignore]\n' } else { '[suspend] ignore\n' })
}

fn store_lid_action(_ voidptr, data &u8, length u64) u64 {
	word := fs.sysfs_word(data, length)
	if word == 'suspend' {
		set_lid_action(.suspend)
	} else if word == 'ignore' {
		set_lid_action(.ignore)
	} else {
		return errno.einval
	}
	return 0
}

fn show_lid_closes(_ voidptr, mut text lib.Text) {
	number_line(mut text, lid_closes())
}

// ── The performance profile ─────────────────────────────────────────────────

fn show_profile_policy(_ voidptr, mut text lib.Text) {
	text.add(if profile_follows_source() { '[auto] manual\n' } else { 'auto [manual]\n' })
}

fn store_profile_policy(_ voidptr, data &u8, length u64) u64 {
	word := fs.sysfs_word(data, length)
	if word == 'auto' {
		set_profile_follows_source(true)
	} else if word == 'manual' {
		set_profile_follows_source(false)
	} else {
		return errno.einval
	}
	return 0
}
