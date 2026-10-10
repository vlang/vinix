// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// suspend: the machine sleeps and comes back, by each way there is to wake it.
//
//   - a rehearsal (pm_test = devices) suspends and resumes every device
//     without sleeping, so a driver that cannot come back is found without
//     depending on a wakeup;
//   - a sleep ended by the alarm, during which a thread of this program that
//     does nothing but count must stand still;
//   - a sleep ended by a key the host presses;
//   - a sleep ended by the power button, which must wake the machine and not
//     turn it off;
//   - a sleep during which the keyboard is not allowed to wake the machine:
//     the key is counted and ignored, and the alarm ends the sleep.
//
// After each the kernel's own account is checked: what woke it, that the
// sleep was counted as a success, and that the CPU's protection registers
// were compared and found unchanged.
@[has_globals]
module main

import sync.stdatomic
import time

const stats = '/sys/power/suspend_stats/'

__global suspend_counter = u64(0)

fn count_for_ever() {
	for {
		// Atomic so that the count is in memory, where the other thread
		// reads it, and not in a register of a loop that never ends.
		stdatomic.add_u64(&suspend_counter, 1)
	}
}

fn stat_word(name string) string {
	return read_word(stats + name)
}

// Writes `word` to /sys/power/state and returns how long the write took, in
// milliseconds: the write returns when the machine is awake again.
fn sleep_now(mut t Test, word string) i64 {
	started := time.sys_mono_now()
	write_text('/sys/power/state', word) or { t.check(false, 'writing ${word} to state: ${err}') }
	return i64((time.sys_mono_now() - started) / 1000000)
}

fn scenario_suspend(mut t Test) {
	state := read_word('/sys/power/state')
	t.check(state.contains('freeze'), 'state does not offer freeze: "${state}"')
	spawn count_for_ever()
	sleep_ms(200)

	// A rehearsal.
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err}') }
	write_text('/sys/power/pm_test_delay_ms', '500') or { t.check(false, 'pm_test_delay_ms: ${err}') }
	mut took := sleep_now(mut t, 'freeze')
	t.check(took >= 500 && took < 5000, 'the rehearsal took ${took} ms')
	t.check(stat_word('success') == '1', 'success is ${stat_word('success')} after the rehearsal')
	t.check(stat_word('last_wake') == 'rehearsal', 'last_wake is ${stat_word('last_wake')}')
	t.info('rehearsal: ${took} ms, devices down in ${stat_word('last_suspend_ms')} ms, back in ${stat_word('last_resume_ms')} ms')
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err}') }

	// The alarm, and a frozen userspace.
	rate_from := counted()
	sleep_ms(300)
	awake_rate := counted() - rate_from
	write_text('/sys/class/rtc/rtc0/wakealarm', '+2') or { t.check(false, 'wakealarm: ${err}') }
	t.check(read_word('/sys/class/rtc/rtc0/wakealarm') != '', 'the alarm does not read back')
	before := counted()
	took = sleep_now(mut t, 'freeze')
	asleep := counted() - before
	t.check(took >= 1900 && took < 6000, 'the alarm sleep took ${took} ms')
	t.check(stat_word('last_wake') == 'alarm', 'last_wake is ${stat_word('last_wake')}, not alarm')
	// Counting for two seconds awake would be more than six times awake_rate.
	t.check(asleep < awake_rate, 'userspace ran while asleep: ${asleep} counts, ${awake_rate} per 300 ms awake')
	t.info('frozen: ${asleep} counts in ${took} ms asleep, ${awake_rate} per 300 ms awake')

	// A key.
	sleep_ms(500)
	t.step('asleep for a key')
	took = sleep_now(mut t, 'mem')
	t.check(stat_word('last_wake') == 'keyboard', 'last_wake is ${stat_word('last_wake')}, not keyboard')
	t.info('key: woke after ${took} ms')

	// The power button wakes, and does not turn the machine off.
	sleep_ms(500)
	t.step('asleep for the power button')
	took = sleep_now(mut t, 'freeze')
	t.check(stat_word('last_wake') == 'power-button', 'last_wake is ${stat_word('last_wake')}, not power-button')
	t.info('power button: woke after ${took} ms')
	sleep_ms(500)

	// A source that is not allowed to wake the machine does not.
	keyboard := '/sys/class/wakeup/wakeup3/'
	t.check(read_word(keyboard + 'name') == 'keyboard', 'wakeup3 is ${read_word(keyboard + 'name')}')
	wakeups := read_word(keyboard + 'wakeup_count')
	write_text(keyboard + 'enabled', 'disabled') or { t.check(false, 'disabling the keyboard: ${err}') }
	write_text('/sys/class/rtc/rtc0/wakealarm', '+3') or { t.check(false, 'wakealarm: ${err}') }
	t.step('asleep, keys ignored')
	took = sleep_now(mut t, 'freeze')
	t.check(took >= 2900, 'a key that may not wake ended the sleep after ${took} ms')
	t.check(stat_word('last_wake') == 'alarm', 'last_wake is ${stat_word('last_wake')}, not alarm')
	t.check(read_word(keyboard + 'wakeup_count') == wakeups, 'the ignored key was counted as a wakeup')

	t.check(stat_word('success') == '5', 'success is ${stat_word('success')}, not 5')
	t.check(stat_word('fail') == '0', 'fail is ${stat_word('fail')}')
	t.check(stat_word('security_checks') == '5', 'security_checks is ${stat_word('security_checks')}')
	t.check(stat_word('security_changes') == '0', 'CPU protections changed across a sleep')
}

fn counted() u64 {
	return stdatomic.load_u64(&suspend_counter)
}
