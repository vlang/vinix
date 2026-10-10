// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// screen-sleep: the screen is dark while the machine sleeps and comes back
// as it was.
//
// What is on the screen is not something a program in the machine can see:
// the controller takes a picture of it at each step named here, and judges
// the pictures once the machine has ended. This program's part is to be in
// the right state when each picture is taken and to check what the kernel
// says it did.
module main

const screen_stats = '/sys/power/suspend_stats/'

fn scenario_screen_sleep(mut t Test) {
	t.check(read_word(screen_stats + 'screen_dark') == '0', 'screen_dark is "${read_word(
		screen_stats + 'screen_dark')}" before any sleep')

	// The console's text is on the screen.
	t.step('screen before the sleep')
	sleep_ms(500)

	// A sleep the alarm ends, long enough for a picture in the middle.
	write_text('/sys/class/rtc/rtc0/wakealarm', '+4') or { t.check(false, 'wakealarm: ${err}') }
	t.step('asleep for the screen')
	mut took := sleep_now(mut t, 'freeze')
	t.check(took >= 3900 && took < 9000, 'the sleep took ${took} ms')
	t.check(read_word(screen_stats + 'last_wake') == 'alarm', 'last_wake is ${read_word(
		screen_stats + 'last_wake')}, not alarm')
	t.check(read_word(screen_stats + 'screen_dark') == '1', 'screen_dark is "${read_word(
		screen_stats + 'screen_dark')}" after one sleep')
	t.check(read_word(screen_stats + 'screen_lit') == '0', 'the screen was left lit for want of memory')
	t.step('screen after the sleep')
	sleep_ms(500)

	// A rehearsal takes the screen down and brings it back as a sleep does.
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err}') }
	write_text('/sys/power/pm_test_delay_ms', '3000') or { t.check(false, 'pm_test_delay_ms: ${err}') }
	t.step('rehearsing for the screen')
	took = sleep_now(mut t, 'freeze')
	t.check(took >= 3000 && took < 9000, 'the rehearsal took ${took} ms')
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err}') }
	t.check(read_word(screen_stats + 'screen_dark') == '2', 'screen_dark is "${read_word(
		screen_stats + 'screen_dark')}" after a sleep and a rehearsal')
	t.step('screen after the rehearsal')
	sleep_ms(500)
}
