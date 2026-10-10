// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Sleep and Restart in the Start menu, and the compositor's side of the idle
// timer, against a machine these tests stand in for: a clock they move, a
// sleep that succeeds or is refused, the kernel's count of sleeps and a
// backlight.
@[has_globals]
module main

import os
import ui2

__global (
	power_test_now        u64
	power_test_sleeps     int
	power_test_sleep_code int
	power_test_slept_ms   u64
	power_test_counted    bool
	power_test_successes  u64
	// The write failed and the machine slept all the same.
	power_test_slept_anyway bool
	power_test_dims         int
	power_test_level        int
	power_test_restored     []int
)

fn power_test_clock() u64 {
	return power_test_now
}

fn power_test_sleep() int {
	power_test_sleeps++
	power_test_now += power_test_slept_ms
	if power_test_sleep_code == 0 || power_test_slept_anyway {
		power_test_successes++
	}
	return power_test_sleep_code
}

fn power_test_success_count() ?u64 {
	if !power_test_counted {
		return none
	}
	return power_test_successes
}

fn power_test_dim() int {
	power_test_dims++
	return power_test_level
}

fn power_test_restore(nits int) BacklightResult {
	power_test_restored << nits
	return .ok
}

fn power_test_desktop() Desktop {
	power_test_now = 1_000_000
	power_test_sleeps = 0
	power_test_sleep_code = 0
	power_test_slept_ms = 0
	power_test_counted = false
	power_test_successes = 0
	power_test_slept_anyway = false
	power_test_dims = 0
	power_test_level = -1
	power_test_restored = []int{}
	mut d := Desktop{
		canvas: Canvas{
			width:  1024
			height: 768
		}
	}
	d.tray.preferences_loaded = true
	d.idle.sleep_available = true
	d.idle.now = power_test_clock
	d.idle.sleep = power_test_sleep
	d.idle.successes = power_test_success_count
	d.idle.dim = power_test_dim
	d.idle.restore = power_test_restore
	return d
}

// One pass of the compositor a second, for `ms` with nobody at the machine.
fn power_test_idle(mut d Desktop, ms u64) {
	mut left := ms
	for left > 0 {
		step := if left > 1000 { u64(1000) } else { left }
		power_test_now += step
		left -= step
		d.idle_tick()
	}
}

fn power_test_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := power_test_element(child, id) {
			return found
		}
	}
	return none
}

fn power_test_menu(mut d Desktop) ui2.Element {
	if !d.start_menu_open {
		d.toggle_start_menu()
	}
	begin_frame_elements()
	return d.start_menu_element()
}

fn test_start_menu_offers_restart_and_sleep_only_where_the_kernel_can() {
	mut d := power_test_desktop()
	// A kernel without /sys/power/state: Restart and Shut down, no Sleep.
	d.idle.sleep_available = false
	mut tree := power_test_menu(mut d)
	if _ := power_test_element(tree, action_start_sleep) {
		assert false, 'Sleep offered on a machine that cannot sleep'
	}
	mut shutdown := power_test_element(tree, action_start_shutdown) or { panic('no Shut down') }
	mut restart := power_test_element(tree, action_start_restart) or { panic('no Restart') }
	assert shutdown.text == 'Shut down' && restart.text == 'Restart'
	// Shut down is where it has always been; Restart sits on it.
	assert shutdown.frame.y == tree.frame.height - 49 && shutdown.frame.height == 34
	assert restart.frame.x == shutdown.frame.x && restart.frame.width == shutdown.frame.width
	assert restart.frame.y + restart.frame.height <= shutdown.frame.y
	free_tree(tree)

	d.idle.sleep_available = true
	tree = power_test_menu(mut d)
	shutdown = power_test_element(tree, action_start_shutdown) or { panic('no Shut down') }
	restart = power_test_element(tree, action_start_restart) or { panic('no Restart') }
	sleep := power_test_element(tree, action_start_sleep) or { panic('no Sleep') }
	assert sleep.text == 'Sleep'
	assert sleep.frame.x == shutdown.frame.x && sleep.frame.width == shutdown.frame.width
	assert sleep.frame.y + sleep.frame.height <= restart.frame.y
	assert sleep.frame.y >= 0 && shutdown.frame.y + shutdown.frame.height <= tree.frame.height
	assert sleep.frame.x + sleep.frame.width <= tree.frame.width
	// The three stand clear of the links above them.
	help := power_test_element(tree, action_start_welcome) or { panic('no Help') }
	assert help.frame.y + help.frame.height <= sleep.frame.y
	free_tree(tree)

	// The list of recent items gives up the room they take.
	d.handle_start_action(action_start_recent)
	tree = power_test_menu(mut d)
	top := power_test_element(tree, action_start_sleep) or { panic('no Sleep') }
	for child in tree.children {
		if child.id.starts_with(action_start_recent_prefix) {
			assert child.frame.y + child.frame.height <= top.frame.y, child.id
		}
	}
	free_tree(tree)
	d.close_start_menu()
	unsafe { d.native_asset_icons.free() }
}

fn test_start_menu_session_buttons_fit_in_every_language() {
	mut d := power_test_desktop()
	d.fonts = load_fonts()
	defer {
		set_desktop_language(.en)
	}
	for language in desktop_languages {
		set_desktop_language(language)
		tree := power_test_menu(mut d)
		for action in [action_start_sleep, action_start_restart, action_start_shutdown] {
			button := power_test_element(tree, action) or { panic('no ${action}') }
			width := d.face_for(button.text_style).text_width(button.text)
			assert button.text.len > 0 && width <= int(button.frame.width), '${language} «${button.text}» is ${width}px'
		}
		free_tree(tree)
		d.idle.notice_until = 1
		notice := d.idle_notice_element() or { panic('no notice') }
		text := power_test_element(notice, 'power.notice.text') or { panic('no notice text') }
		assert d.face_for(text.text_style).text_width(text.text) <= int(text.frame.width), '${language} «${text.text}»'
		d.idle.notice_until = 0
	}
	d.close_start_menu()
}

struct PowerTestGuard {
mut:
	allowed bool
	asked   int
}

fn (mut _ PowerTestGuard) build(_ ui2.Rect) !ui2.Element {
	return ui2.Element{}
}

fn (mut _ PowerTestGuard) handle(_ string) ! {}

fn (mut g PowerTestGuard) prepare_close() bool {
	g.asked++
	return g.allowed
}

fn test_restart_ends_the_session_the_way_shut_down_does() {
	os.setenv('VINIX_SYSTEM_SESSION', '1', true)
	defer {
		os.unsetenv('VINIX_SYSTEM_SESSION')
	}
	mut guard := &PowerTestGuard{}
	mut d := power_test_desktop()
	d.apps << NativeApp(guard)
	d.windows << Window{
		id:        7
		title:     'Draft'
		page:      .app
		app_index: 0
		minimized: true
		width:     300
		height:    200
	}
	// An application that cannot close keeps the session, and is brought
	// back into view, exactly as for Shut down.
	d.toggle_start_menu()
	d.handle_start_action(action_start_restart)
	assert !d.start_menu_open && guard.asked == 1
	assert d.running && d.power == .keep_running
	assert d.focus == 7 && !d.windows[0].minimized
	// Once it can, the session ends and the machine is to restart.
	guard.allowed = true
	d.handle_start_action(action_start_restart)
	assert guard.asked == 2 && !d.running && d.power == .restart
	assert power_test_sleeps == 0 && !d.idle.sleep_requested

	// Shut down is unchanged beside it.
	mut other := power_test_desktop()
	other.handle_start_action(action_start_shutdown)
	assert !other.running && other.power == .power_off
	// A desktop started from a shell ends its session and leaves the machine.
	os.unsetenv('VINIX_SYSTEM_SESSION')
	if !desktop_is_system_session() {
		mut plain := power_test_desktop()
		plain.handle_start_action(action_start_restart)
		assert !plain.running && plain.power == .keep_running
	}
}

fn test_sleep_keeps_the_session_and_repaints_when_the_machine_wakes() {
	mut d := power_test_desktop()
	d.spawn('System', .system, 100, 100, 300, 200)
	d.toggle_start_menu()
	d.handle_start_action(action_start_sleep)
	// The menu comes down and the machine is asked to sleep between two
	// passes, not from inside the click.
	assert !d.start_menu_open && d.idle.sleep_requested && power_test_sleeps == 0
	assert d.running && d.power == .keep_running

	d.dirty = false
	d.cursor_backing.box = DamageRect{
		w:     8
		h:     8
		valid: true
	}
	d.taskbar_clock_sampled = true
	d.tray.sampled = false
	power_test_slept_ms = 3 * 60 * 60 * 1000
	assert d.sleep_now()
	assert power_test_sleeps == 1 && !d.idle.sleep_requested
	// Nothing about the session ended.
	assert d.running && d.power == .keep_running && d.windows.len == 1
	// The whole screen is repainted, the clock is read again and so is the
	// battery, by way of the taskbar's sample.
	assert d.dirty && !d.cursor_backing.box.valid && !d.taskbar_clock_sampled
	assert d.tray.sampled
	assert d.idle.notice_until == 0
	if _ := d.idle_notice_element() {
		assert false, 'a notice after a sleep that worked'
	}
	// Waking is somebody at the machine: nothing is overdue on the next pass,
	// however long it slept.
	assert d.idle.timer.phase == .active && d.idle.timer.last_input_ms == power_test_now
	d.settings.display_off_minutes = 1
	d.settings.sleep_minutes = 2
	d.idle_tick()
	assert !d.idle.display_off && !d.idle.sleep_requested

	// A machine that cannot sleep is not asked to, even by a stale button.
	d.idle.sleep_available = false
	d.handle_start_action(action_start_sleep)
	d.request_sleep()
	assert !d.idle.sleep_requested && power_test_sleeps == 1
}

fn test_a_refused_sleep_is_reported_and_changes_nothing() {
	mut d := power_test_desktop()
	d.spawn('System', .system, 100, 100, 300, 200)
	power_test_sleep_code = 1 // EPERM
	d.request_sleep()
	d.dirty = false
	assert !d.sleep_now()
	assert power_test_sleeps == 1 && !d.idle.sleep_requested
	assert d.running && d.power == .keep_running && d.windows.len == 1
	assert d.idle.timer.phase == .active && d.idle.timer.refused
	// The notice goes up at once and comes down by itself.
	assert d.dirty && d.idle.notice_until != 0
	notice := d.idle_notice_element() or { panic('no notice of the refusal') }
	text := power_test_element(notice, 'power.notice.text') or { panic('no notice text') }
	assert text.text == 'This computer could not go to sleep.'
	assert notice.frame.x >= 0 && notice.frame.x + notice.frame.width <= d.canvas.width
	assert d.idle_wait(60_000) <= idle_notice_ms
	d.idle.notice_until = 1
	d.dirty = false
	d.idle_tick()
	assert d.idle.notice_until == 0 && d.dirty
	if _ := d.idle_notice_element() {
		assert false, 'the notice stayed up'
	}

	// With the kernel's count of sleeps to go by, a write that failed after
	// the machine slept and woke is a sleep, and one that changed no count is
	// a refusal.
	power_test_counted = true
	power_test_sleep_code = 4 // EINTR
	power_test_slept_anyway = true
	d.request_sleep()
	assert d.sleep_now()
	assert d.idle.notice_until == 0 && !d.idle.timer.refused
	power_test_slept_anyway = false
	d.request_sleep()
	assert !d.sleep_now()
	assert d.idle.notice_until != 0 && d.idle.timer.refused
	assert power_test_sleeps == 3
}

fn test_idle_display_turns_off_and_the_input_that_wakes_it_is_swallowed() {
	mut d := power_test_desktop()
	d.settings.display_off_minutes = 2
	d.settings.sleep_minutes = 0
	power_test_level = 137
	here := PointerPacket{
		x:     500
		y:     400
		max_x: 1000
		max_y: 1000
	}
	// With the display on, input is the application's.
	assert !d.idle_pointer_input(here)
	assert !d.idle_key_input()
	d.idle_tick()
	power_test_idle(mut d, 119_000)
	assert !d.idle.display_off && power_test_dims == 0
	// The device answers every read with where the pointer is. A packet that
	// says nothing new is not somebody at the machine.
	assert !d.idle_pointer_input(here)
	power_test_idle(mut d, 1000)
	assert d.idle.display_off && d.idle.blank_pending
	assert power_test_dims == 1 && d.idle.backlight_nits == 137
	// Off is one black frame, which the main loop presents once.
	d.idle.blank_pending = false
	power_test_idle(mut d, 60_000)
	assert d.idle.display_off && !d.idle.blank_pending && power_test_dims == 1
	assert !d.idle_pointer_input(here) && d.idle.display_off

	// A press turns the display on, puts the backlight back exactly, repaints
	// everything, and is not a click on whatever was under the pointer.
	d.dirty = false
	d.cursor_backing.box = DamageRect{
		w:     8
		h:     8
		valid: true
	}
	assert d.idle_pointer_input(PointerPacket{
		...here
		buttons: button_left
		pressed: button_left
	})
	assert !d.idle.display_off && power_test_restored == [137] && d.idle.backlight_nits == -1
	assert d.dirty && !d.cursor_backing.box.valid
	// Nor is the rest of that press, its release included.
	assert d.idle_pointer_input(PointerPacket{
		...here
		x:       520
		buttons: button_left
	})
	assert d.idle_pointer_input(PointerPacket{
		...here
		x:        520
		released: button_left
	})
	// The next click is delivered.
	assert !d.idle_pointer_input(PointerPacket{
		...here
		x:       520
		buttons: button_left
		pressed: button_left
	})
	assert !d.idle_pointer_input(PointerPacket{
		...here
		x:        520
		released: button_left
	})

	// The count started again at the wake: off after another two minutes,
	// and this time a key, a move and a scroll each wake it and are dropped.
	for wake in 0 .. 3 {
		power_test_idle(mut d, 120_000)
		assert d.idle.display_off, 'wake ${wake}'
		swallowed := match wake {
			0 {
				d.idle_key_input()
			}
			1 {
				d.idle_pointer_input(PointerPacket{
					...here
					x: 601
				})
			}
			else {
				d.idle_pointer_input(PointerPacket{
					...here
					x:      601
					scroll: 1
				})
			}
		}
		assert swallowed && !d.idle.display_off && !d.idle.swallow_pointer
		// What follows is ordinary input again.
		assert !d.idle_key_input()
	}
	assert power_test_dims == 4 && power_test_restored == [137, 137, 137, 137]

	// A machine with no backlight to set: a black frame and nothing else.
	power_test_level = -1
	power_test_idle(mut d, 120_000)
	assert d.idle.display_off && d.idle.backlight_nits == -1
	assert d.idle_key_input()
	assert power_test_restored.len == 4
}

fn test_idle_sleep_follows_the_display_and_a_refusal_is_not_repeated() {
	mut d := power_test_desktop()
	d.settings.display_off_minutes = 1
	d.settings.sleep_minutes = 2
	power_test_level = 80
	d.idle_tick()
	power_test_idle(mut d, 60_000)
	assert d.idle.display_off && !d.idle.sleep_requested
	power_test_idle(mut d, 60_000)
	assert d.idle.sleep_requested && power_test_sleeps == 0
	// The main loop carries it out between passes; the machine sleeps eight
	// hours and wakes with its display on and its backlight back.
	power_test_slept_ms = 8 * 60 * 60 * 1000
	assert d.sleep_now()
	assert !d.idle.display_off && power_test_restored == [80]
	assert d.idle.timer.phase == .active
	// And goes through the same again from there.
	power_test_slept_ms = 0
	power_test_idle(mut d, 119_000)
	assert d.idle.display_off && !d.idle.sleep_requested
	power_test_idle(mut d, 1000)
	assert d.idle.sleep_requested

	// Refused this time: the display stays off, and the machine is not asked
	// again on every pass for the rest of the night.
	power_test_sleep_code = 1
	assert !d.sleep_now()
	assert d.idle.display_off && d.idle.timer.refused && power_test_sleeps == 2
	power_test_idle(mut d, 2 * 60 * 60 * 1000)
	assert !d.idle.sleep_requested && d.idle.display_off
	// Somebody uses it; it is asked again after another whole timeout.
	assert d.idle_key_input()
	power_test_idle(mut d, 119_000)
	assert !d.idle.sleep_requested
	power_test_idle(mut d, 1000)
	assert d.idle.sleep_requested

	// Without a kernel that can sleep the timeout is not kept at all.
	mut awake := power_test_desktop()
	awake.idle.sleep_available = false
	awake.settings.display_off_minutes = 0
	awake.settings.sleep_minutes = 1
	awake.idle_tick()
	power_test_idle(mut awake, 60 * 60 * 1000)
	assert !awake.idle.sleep_requested && !awake.idle.display_off
	// And with it, sleep alone needs no display timeout.
	awake.idle.sleep_available = true
	awake.idle_key_input()
	power_test_idle(mut awake, 60_000)
	assert awake.idle.sleep_requested && !awake.idle.display_off
}

fn test_idle_timeouts_come_from_settings_and_recording_is_use() {
	mut d := power_test_desktop()
	// Never, the way a profile that chose it has it.
	d.settings.display_off_minutes = 0
	d.settings.sleep_minutes = 0
	d.idle_tick()
	power_test_idle(mut d, 3 * 60 * 60 * 1000)
	assert !d.idle.display_off && !d.idle.sleep_requested
	// The default: ten minutes for the display, never for sleep.
	d.settings = Settings{}
	d.idle_key_input()
	power_test_idle(mut d, 599_000)
	assert !d.idle.display_off
	power_test_idle(mut d, 1000)
	assert d.idle.display_off
	power_test_idle(mut d, 3 * 60 * 60 * 1000)
	assert !d.idle.sleep_requested
	// A longer timeout accepted from Settings while the display is off
	// brings it back; nothing is swallowed for that.
	d.settings.display_off_minutes = 0
	d.dirty = false
	d.idle_tick()
	assert !d.idle.display_off && d.dirty
	assert !d.idle_key_input()

	// The compositor recording the screen is the screen in use.
	d.settings.display_off_minutes = 1
	d.settings.sleep_minutes = 2
	d.capture.report.phase = .recording
	power_test_idle(mut d, 30 * 60 * 1000)
	assert !d.idle.display_off && !d.idle.sleep_requested
	d.capture.report.phase = .idle
	power_test_idle(mut d, 60_000)
	assert d.idle.display_off

	// The idle wait never sleeps through a timeout, and with none set it is
	// whatever the rest of the desktop allows.
	mut waiting := power_test_desktop()
	waiting.settings.display_off_minutes = 0
	assert waiting.idle_wait(1000) == 1000
	waiting.settings.display_off_minutes = 1
	waiting.idle_tick()
	assert waiting.idle_wait(1000) == 1000
	assert waiting.idle_wait(60_000) == i64(idle_gap_ms / 2)
	power_test_idle(mut waiting, 59_600)
	assert waiting.idle_wait(1000) == 400
	assert waiting.idle_wait(0) == 0
}
