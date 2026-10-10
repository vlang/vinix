// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The screen across a sleep: dark while the machine is down, and as it was
// when it is back. What can be done about a screen is the terminal's to know
// (term/sleep.v); this is where the sleep sequence asks for it and where
// /sys says how often it was done:
//
//	/sys/power/suspend_stats/screen_dark   sleeps the screen was dark for
//	/sys/power/suspend_stats/screen_lit    sleeps it stayed lit for, because
//	                                       its picture could not be put away
module syspower

import fs
import lib
import term

// The devices are down and nothing draws: the screen goes dark.
fn screen_down() {
	term.screen_sleep()
}

// The machine is back. Before the devices: the picture is the first thing
// anyone waiting for the machine sees.
fn screen_up() {
	term.screen_wake()
}

fn show_screen_dark(_ voidptr, mut text lib.Text) {
	dark, _ := term.screen_sleep_counts()
	number_line(mut text, dark)
}

fn show_screen_lit(_ voidptr, mut text lib.Text) {
	_, lit := term.screen_sleep_counts()
	number_line(mut text, lit)
}

fn publish_screen() {
	fs.sysfs_attribute('power/suspend_stats/screen_dark', 0o444, show_screen_dark, unsafe { nil },
		unsafe { nil })
	fs.sysfs_attribute('power/suspend_stats/screen_lit', 0o444, show_screen_lit, unsafe { nil },
		unsafe { nil })
}
