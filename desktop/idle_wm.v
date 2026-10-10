// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The compositor's side of the idle timer and of Sleep: noticing input,
// turning the display off and on, and putting the machine to sleep without
// ending the session. idle_timer.v decides; this acts on what it decides.
//
// A display that is off is one black frame and, where the panel's backlight
// can be set, its minimum level: there is no way yet to cut a panel's power.
// Nothing tells the compositor that an application is showing something
// worth staying awake for, so a film watched without touching the machine
// is turned off like anything else.
module main

import ui2

// How long the notice of a refused sleep stays up.
const idle_notice_ms = i64(4000)
const idle_notice_width = 420
const idle_notice_height = 56

struct IdleSession {
mut:
	timer IdleTimer
	// /sys/power/state takes `mem`, so there is a Sleep to offer and a
	// timeout to keep. Read once as the desktop starts.
	sleep_available bool
	// Sleep was chosen, from the menu or by the timer. The main loop carries
	// it out between two frames.
	sleep_requested bool
	// Nothing is composed or presented while the display is off. The main
	// loop owns the framebuffer and so presents the black frame itself, once,
	// while `blank_pending`.
	display_off   bool
	blank_pending bool
	// The backlight level to put back when the display comes on, or -1 when
	// the backlight was not touched.
	backlight_nits int = -1
	// The pointer as last reported. The device answers every read with where
	// the pointer is, so only a packet that says something new is input.
	pointer_seen    bool
	pointer_x       i32
	pointer_y       i32
	pointer_buttons u32
	// A press woke the display: the rest of that press, its release included,
	// is not the application's either.
	swallow_pointer bool
	// When the notice of a refused sleep comes down, or zero while it is not
	// up.
	notice_until i64
	// The machine underneath, replaceable so host tests can stand in for it.
	now       fn () u64 = desktop_monotonic_ms
	sleep     fn () int = desktop_system_sleep
	successes fn () ?u64 = read_suspend_successes
	dim       fn () int  = dim_backlight
	restore   fn (int) BacklightResult = set_backlight_nits
}

// start_power_session is the desktop taking up the machine's power settings
// as it starts: whether there is a Sleep to offer, and the lid action and
// performance profile that were saved, which the kernel has forgotten.
fn (mut d Desktop) start_power_session() {
	mut controls := PowerControls{}
	read_power_controls(mut controls)
	d.idle.sleep_available = controls.sleep
	apply_power_settings(&d.settings)
}

// idle_input notes a key or a pointer event, and wakes a display that was
// off. It reports whether the event is to be swallowed.
fn (mut d Desktop) idle_input() bool {
	swallow := d.idle.timer.input(d.idle.now())
	if swallow {
		d.display_turn_on()
	}
	return swallow
}

// idle_key_input is told of every read from the keyboard that returned
// something, before anything else sees it.
fn (mut d Desktop) idle_key_input() bool {
	return d.idle_input()
}

// idle_pointer_input is told of every pointer packet before anything acts on
// it, and reports whether the packet is to be dropped.
fn (mut d Desktop) idle_pointer_input(packet PointerPacket) bool {
	changed := !d.idle.pointer_seen || packet.x != d.idle.pointer_x
		|| packet.y != d.idle.pointer_y || packet.buttons != d.idle.pointer_buttons
		|| packet.pressed != 0 || packet.released != 0 || packet.scroll != 0
		|| packet.scroll_x != 0
	d.idle.pointer_seen = true
	d.idle.pointer_x = packet.x
	d.idle.pointer_y = packet.y
	d.idle.pointer_buttons = packet.buttons
	if d.idle.swallow_pointer {
		// Until every button is up: an application must not get the release
		// of a press it never saw.
		if packet.buttons == 0 {
			d.idle.swallow_pointer = false
		}
		if changed {
			d.idle_input()
		}
		return true
	}
	if !changed {
		return false
	}
	if d.idle_input() {
		d.idle.swallow_pointer = packet.buttons != 0
		return true
	}
	return false
}

// idle_tick is the main loop's look at the idle timer, once a pass, after the
// pass's input.
fn (mut d Desktop) idle_tick() {
	if d.idle.notice_until != 0 && monotonic_millis() >= d.idle.notice_until {
		d.idle.notice_until = 0
		d.dirty = true
	}
	now := d.idle.now()
	// The compositor's own recording of the screen is the screen in use.
	if d.capture.report.phase == .recording {
		d.idle_input()
	}
	// With no way to sleep there is no sleep timeout to keep.
	sleep_minutes := if d.idle.sleep_available { d.settings.sleep_minutes } else { 0 }
	match d.idle.timer.tick(now, d.settings.display_off_minutes, sleep_minutes) {
		.none_ {}
		.display_off { d.display_turn_off() }
		.display_on { d.display_turn_on() }
		.sleep { d.idle.sleep_requested = true }
	}
}

// idle_wait shortens an idle wait so the next timeout, and the end of the
// notice, arrive on time.
fn (d &Desktop) idle_wait(interval i64) i64 {
	if interval <= 0 {
		return interval
	}
	sleep_minutes := if d.idle.sleep_available { d.settings.sleep_minutes } else { 0 }
	mut wait := i64(d.idle.timer.wait_ms(d.idle.now(), d.settings.display_off_minutes,
		sleep_minutes, u64(interval)))
	if d.idle.notice_until != 0 {
		left := d.idle.notice_until - monotonic_millis()
		if left < wait {
			wait = if left > 0 { left } else { 0 }
		}
	}
	return wait
}

fn (mut d Desktop) display_turn_off() {
	if d.idle.display_off {
		return
	}
	d.idle.display_off = true
	d.idle.blank_pending = true
	d.idle.backlight_nits = d.idle.dim()
}

fn (mut d Desktop) display_turn_on() {
	if !d.idle.display_off {
		return
	}
	d.idle.display_off = false
	d.idle.blank_pending = false
	if d.idle.backlight_nits >= 0 {
		d.idle.restore(d.idle.backlight_nits)
		d.idle.backlight_nits = -1
	}
	d.repaint_everything()
}

// repaint_everything makes the next frame a whole one. After a black frame or
// a sleep nothing on the screen can be trusted to be what the canvas holds,
// the pointer's backing included, and the clock's text is as old as the
// pause was long.
fn (mut d Desktop) repaint_everything() {
	d.dirty = true
	d.frame_damage = FrameDamage{}
	d.drag_damage = DamageRect{}
	d.cursor_backing.box = DamageRect{}
	d.taskbar_clock_sampled = false
}

// request_sleep is Sleep chosen from the Start menu.
fn (mut d Desktop) request_sleep() {
	if d.idle.sleep_available {
		d.idle.sleep_requested = true
	}
}

// sleep_now puts the machine to sleep and returns when it is awake again,
// reporting whether it slept. The session is not ended: every window and
// every application is where it was. On the way back the whole screen is
// repainted and the battery read again; a refusal changes nothing and raises
// a notice.
fn (mut d Desktop) sleep_now() bool {
	d.idle.sleep_requested = false
	d.idle.timer.begin_sleep()
	before := d.idle.successes()
	failure := d.idle.sleep()
	mut slept := failure == 0
	if !slept {
		// The write can fail after the machine has slept and woken: a signal
		// that arrives as it wakes interrupts the write. The kernel's count
		// of sleeps it completed says which this was.
		if count := before {
			if after := d.idle.successes() {
				slept = after > count
			}
		}
	}
	if !slept {
		d.idle.timer.sleep_refused()
		eprintln('vinix-desktop: the machine did not go to sleep (error ${failure})')
		d.idle.notice_until = monotonic_millis() + idle_notice_ms
		d.dirty = true
		return false
	}
	d.idle.timer.woke(d.idle.now())
	d.display_turn_on()
	d.repaint_everything()
	d.update_tray_at(monotonic_millis(), true)
	return true
}

// drop_wake_input discards what is waiting on the keyboard and the pointer
// when the machine comes back from sleep. The key or the click that woke it
// did that and nothing else; it is not also typed into the window that had
// the keyboard, and a button still held is swallowed through its release.
fn (mut d Desktop) drop_wake_input(mut pointer PointerDevice, mut keyboard Keyboard) {
	keys := keyboard.poll()
	if keys.len > 0 {
		unsafe { keys.free() }
	}
	packet := pointer.poll() or { return }
	d.idle.pointer_seen = true
	d.idle.pointer_x = packet.x
	d.idle.pointer_y = packet.y
	d.idle.pointer_buttons = packet.buttons
	d.idle.swallow_pointer = packet.buttons != 0
}

// idle_notice_element says that the machine would not sleep, for a moment, in
// the middle of the screen.
fn (d &Desktop) idle_notice_element() ?ui2.Element {
	if d.idle.notice_until == 0 {
		return none
	}
	return ui2.view('power.notice', ui2.rect(f64((d.canvas.width - idle_notice_width) / 2), f64((d.canvas.height - idle_notice_height) / 2), f64(idle_notice_width), f64(idle_notice_height)), ui2.BoxStyle{
		bg:     switcher_bg
		radius: switcher_radius
	}, frame_child(ui2.label('power.notice.text', tr('power.sleep_failed'), ui2.rect(12, 0, f64(idle_notice_width - 24), f64(idle_notice_height)), ui2.TextStyle{
		color: switcher_text
		size:  14
		bold:  true
		align: .center
		lines: 1
	})))
}
