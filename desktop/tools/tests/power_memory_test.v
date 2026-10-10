// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// What the desktop does for power for as long as it runs must keep nothing
// allocated: a battery poll every five seconds, the Power page's read every
// second and its frame every pass, and the idle timer's look once a pass.
module main

import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

// The kernel's files as fixed text, served without allocating, so that
// whatever a client leaves on the heap is the client's own.
const power_heap_paths = [
	'/sys/class/power_supply/AC/type',
	'/sys/class/power_supply/AC/online',
	'/sys/class/power_supply/BAT0/type',
	'/sys/class/power_supply/BAT0/present',
	'/sys/class/power_supply/BAT0/capacity',
	'/sys/class/power_supply/BAT0/status',
	'/sys/class/power_supply/BAT0/energy_full',
	'/sys/class/power_supply/BAT0/time_to_empty_now',
	'/sys/class/power_supply/BAT0/time_to_full_now',
	'/dev/battery',
	'/sys/power/state',
	'/sys/power/suspend_stats/success',
	'/sys/power/lid/state',
	'/sys/power/lid/action',
	'/sys/power/profile_policy',
	'/sys/devices/system/cpu/cpufreq/profile',
]!
const power_heap_texts = [
	'Mains\n',
	'1\n',
	'Battery\n',
	'1\n',
	'73\n',
	'Charging\n',
	'50000000\n',
	'0\n',
	'5400\n',
	'61\n',
	'freeze mem\n',
	'3\n',
	'open\n',
	'[suspend] ignore\n',
	'[auto] manual\n',
	'balanced\n',
]!

struct PowerHeapFiles {
mut:
	// Whether /sys lists any power supply, as a PC does and an M1 does not.
	supplies bool = true
	file     int  = -1
	position int
	opens    int
	closes   int
	writes   int
}

fn (mut f PowerHeapFiles) open(path string, writable bool) (int, DeviceError) {
	assert f.file < 0
	for index, known in power_heap_paths {
		if known == path {
			f.file = index
			f.position = 0
			f.opens++
			return 3 + index, DeviceError.none
		}
	}
	// A directory that is not a supply has no `type`.
	assert !writable
	return -1, DeviceError.unavailable
}

fn (mut f PowerHeapFiles) read(fd int, mut buffer []u8) (int, DeviceError) {
	assert f.file >= 0 && fd == 3 + f.file
	text := power_heap_texts[f.file]
	// The device ends at the end of its text; /sys repeats it whole.
	start := if f.file == 9 { f.position } else { 0 }
	mut n := text.len - start
	if n > buffer.len {
		n = buffer.len
	}
	for i in 0 .. n {
		buffer[i] = text[start + i]
	}
	f.position += n
	return n, DeviceError.none
}

fn (mut f PowerHeapFiles) write(fd int, buffer []u8) (int, DeviceError) {
	assert f.file >= 0 && fd == 3 + f.file
	f.writes++
	return buffer.len, DeviceError.none
}

// No power file takes an ioctl.
fn (mut f PowerHeapFiles) ioctl(fd int, request u64, mut buffer []u8) DeviceError {
	assert false, 'ioctl ${request} on descriptor ${fd} with ${buffer.len} bytes'
	return .io
}

fn (mut f PowerHeapFiles) close(fd int) DeviceError {
	assert f.file >= 0 && fd == 3 + f.file
	f.file = -1
	f.closes++
	return .none
}

fn (mut f PowerHeapFiles) is_character(fd int) (bool, DeviceError) {
	return fd < 0, DeviceError.none
}

fn (mut f PowerHeapFiles) is_writable(fd int) (bool, DeviceError) {
	return fd >= 0, DeviceError.none
}

fn (mut f PowerHeapFiles) list(path string, mut names DeviceNames) DeviceError {
	names.count = 0
	if !f.supplies || path != power_supply_directory {
		return .unavailable
	}
	for name in ['AC', 'BAT0', 'policy']! {
		names.add(unsafe { name.str.vbytes(name.len) })
	}
	return .none
}

fn test_battery_and_power_reads_and_writes_retain_zero_bytes() {
	mut files := &PowerHeapFiles{}
	mut device := &PowerHeapFiles{
		supplies: false
	}
	// Made once, as the desktop's own is: a file set handed to a client as
	// it is called would be boxed on the heap at every call.
	mut supply_io := DeviceIO(files)
	mut device_io := DeviceIO(device)
	saved := Settings{
		lid_action:    .ignore
		power_profile: .power_saver
	}
	mut cache := BatteryCache{}
	// Once outside the measurement, for anything made on first use.
	assert read_battery_reading_with(mut supply_io).percent == 73
	assert read_battery_reading_with(mut device_io).percent == 61
	C.vinix_heap_begin()
	for pass in 0 .. 1000 {
		supply := read_battery_reading_with(mut supply_io)
		assert supply.percent == 73 && supply.source == .supply && supply.status == .charging
		assert supply.to_full_s == 5400 && supply.mains_online
		cache.store(u64(pass) * 5000, supply)
		outlook := battery_outlook(cache.reading, unsafe { &cache.history })
		assert outlook.to_full && outlook.estimate == 2
		assert battery_power(cache.reading) == .charging
		fallback := read_battery_reading_with(mut device_io)
		assert fallback.percent == 61 && fallback.source == .device

		controls := read_power_controls_with(mut supply_io)
		assert controls.sleep && controls.lid && controls.profile_known && controls.profile_settable
		assert set_lid_action_with(mut supply_io, if pass % 2 == 0 { LidAction.ignore } else { LidAction.suspend }) == .ok
		assert set_power_profile_with(mut supply_io, power_profiles[pass % power_profiles.len]) == .ok
		assert (read_suspend_successes_with(mut supply_io) or { 0 }) == 3
		apply_power_settings_with(mut supply_io, unsafe { &saved })
	}
	assert C.vinix_heap_end() == 0
	assert files.opens == files.closes && files.file < 0 && files.writes > 3000
	assert device.opens == device.closes
}

__global (
	power_heap_controls PowerControls
)

fn power_heap_read(mut out PowerControls) {
	out = power_heap_controls
}

fn power_heap_set_lid(action LidAction) PowerResult {
	power_heap_controls.lid_action = action
	return .ok
}

fn power_heap_set_profile(profile PowerProfile) PowerResult {
	power_heap_controls.profile = profile
	return .ok
}

fn power_heap_reading() BatteryReading {
	return BatteryReading{
		percent:      73
		source:       .supply
		status:       .charging
		to_full_s:    5400
		mains:        true
		mains_online: true
	}
}

fn power_heap_percent(_ bool) int {
	return 73
}

fn power_heap_history() BatteryHistory {
	return BatteryHistory{}
}

fn power_heap_frame(mut app SettingsApp) ! {
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 620, 376))!
	free_tree(tree)
}

// Made once: the pages are chosen through the sidebar's own actions.
const power_heap_power_page = '${settings_action_category}${settings_categories.index(SettingsCategory.power)}'
const power_heap_battery_page = '${settings_action_category}${settings_categories.index(SettingsCategory.battery)}'

fn power_heap_pass(mut app SettingsApp, pass int) ! {
	power := power_heap_power_page
	battery := power_heap_battery_page
	set_desktop_language(desktop_languages[pass % desktop_languages.len])
	app.handle(power)!
	power_heap_frame(mut app)!
	app.handle(settings_power_display_actions[pass % 8])!
	app.handle(settings_power_sleep_actions[(pass / 2) % 8])!
	app.handle(settings_power_lid_actions[pass % 2])!
	app.handle(settings_power_profile_actions[pass % 4])!
	// A page whose kernel has no lid and takes no profile, every other pass.
	power_heap_controls.lid = pass % 2 == 0
	power_heap_controls.profile_settable = pass % 2 == 0
	app.power_last_poll_ms = 0
	power_heap_frame(mut app)!
	app.handle(battery)!
	power_heap_frame(mut app)!
}

fn test_power_and_battery_pages_retain_zero_bytes_across_frames_and_languages() {
	power_heap_controls = PowerControls{
		sleep:            true
		lid:              true
		profile_known:    true
		profile_settable: true
	}
	mut desktop := Desktop{}
	mut app := &SettingsApp{
		desktop:           unsafe { &desktop }
		power_read:        power_heap_read
		power_set_lid:     power_heap_set_lid
		power_set_profile: power_heap_set_profile
		battery_read:      power_heap_percent
		battery_history:   power_heap_history
		battery_reading:   power_heap_reading
	}
	defer {
		app.close_app()
		unsafe {
			free(app)
			desktop.native_asset_icons.free()
		}
		set_desktop_language(.en)
	}
	// Every language once, so the measurement starts warm.
	for pass in 0 .. 2 * desktop_languages.len {
		power_heap_pass(mut app, pass)!
	}
	C.vinix_heap_begin()
	for pass in 0 .. 240 {
		power_heap_pass(mut app, pass)!
	}
	// The minutes and the hours worded for the language now in use are the
	// pages' to keep, and each change of language released the last set.
	// Releasing this one by hand leaves only what leaked.
	for i in 0 .. power_minute_labels.labels.len {
		if power_minute_labels.labels[i].len > 0 {
			unsafe { power_minute_labels.labels[i].free() }
			power_minute_labels.labels[i] = ''
		}
	}
	for i in 0 .. battery_hour_labels.labels.len {
		if battery_hour_labels.labels[i].len > 0 {
			unsafe { battery_hour_labels.labels[i].free() }
			battery_hour_labels.labels[i] = ''
		}
	}
	assert C.vinix_heap_end() == 0
}

__global (
	power_heap_now u64
)

fn power_heap_clock() u64 {
	return power_heap_now
}

fn power_heap_sleep() int {
	power_heap_now += 3_600_000
	return 0
}

fn power_heap_no_count() ?u64 {
	return none
}

fn power_heap_dim() int {
	return 137
}

fn power_heap_restore(nits int) BacklightResult {
	return if nits == 137 { BacklightResult.ok } else { BacklightResult.invalid }
}

fn test_idle_timer_passes_and_display_cycles_retain_zero_bytes() {
	power_heap_now = 1_000_000
	mut d := Desktop{
		canvas: Canvas{
			width:  1024
			height: 768
		}
	}
	d.tray.preferences_loaded = true
	d.idle.sleep_available = true
	d.idle.now = power_heap_clock
	d.idle.sleep = power_heap_sleep
	d.idle.successes = power_heap_no_count
	d.idle.dim = power_heap_dim
	d.idle.restore = power_heap_restore
	d.settings.display_off_minutes = 1
	d.settings.sleep_minutes = 2
	here := PointerPacket{
		x:     500
		y:     400
		max_x: 1000
		max_y: 1000
	}
	d.idle_pointer_input(here)
	d.idle_tick()
	C.vinix_heap_begin()
	for cycle in 0 .. 50 {
		// A minute of passes with nobody there, and the display goes off.
		for _ in 0 .. 60 {
			power_heap_now += 1000
			d.idle_pointer_input(here)
			d.idle_tick()
			d.idle_wait(1000)
		}
		assert d.idle.display_off
		if cycle % 2 == 0 {
			// Somebody comes back: a press, held, released.
			assert d.idle_pointer_input(PointerPacket{
				...here
				buttons: button_left
				pressed: button_left
			})
			assert d.idle_pointer_input(PointerPacket{
				...here
				released: button_left
			})
			assert !d.idle.display_off
			assert !d.idle_key_input()
		} else {
			// Nobody does: another minute and the machine is to sleep.
			for _ in 0 .. 60 {
				power_heap_now += 1000
				d.idle_tick()
			}
			assert d.idle.sleep_requested
			d.idle.sleep_requested = false
			d.idle.timer.woke(power_heap_now)
			d.display_turn_on()
		}
	}
	assert C.vinix_heap_end() == 0
}
