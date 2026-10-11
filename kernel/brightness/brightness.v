// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The class a panel's backlight registers with, as Linux shows one:
//
//	/sys/class/backlight/<name>/
//	    brightness          the level asked for, 0 to max_brightness; write it
//	    max_brightness      the highest level
//	    actual_brightness   the level the panel says it is at
//	    bl_power            0 lit, 4 off; write it
//	    type                firmware, platform or raw: who drives it
//
// A driver gives a way to set a level and, where the panel can say, a way to
// ask for it. Level 0 is the dimmest the driver has, which for a panel driven
// through firmware is rarely dark; "off" is that level unless the driver can
// do better.
//
// The level asked for is kept apart from what the panel is given. A panel is
// put down for a sleep by its driver's suspend (put_down()) and when a
// program writes 4 to bl_power, and in either case is given level 0 while
// the level asked for stays what it was, to be given back (bring_back(), or
// 0 to bl_power). Brightness keys step the level asked for (step()).
//
// Setting a level may run firmware's code, which may wait, so one mutex
// covers every panel: a write, a key and a sleep take turns.
@[has_globals]
module brightness

import acpisync
import errno
import fs
import lib

pub const max_panels = 4
// bl_power, by Linux's numbers.
const power_on = u32(0)
const power_off = u32(4)

pub struct Panel {
pub mut:
	// A literal, or the registrant's to keep.
	name string
	kind string
	// The highest level; the lowest is 0.
	max     u32
	context voidptr
	set     fn (context voidptr, level u32) bool = unsafe { nil }
	// None where the panel cannot say.
	get fn (context voidptr) ?u32 = unsafe { nil }
mut:
	used bool
	// Asked for, and last given to the panel.
	level u32
	given u32
	power u32
	// Whether the level asked for is one the panel was at or was given: a
	// panel that cannot say where it is, and has not been set, is not
	// touched for a sleep, since nothing knows what to give it back.
	known bool
	// Down for a sleep.
	asleep bool
	// How often it was put down for a sleep, and how often a level did not
	// take.
	downs    u64
	failures u64
}

__global (
	brightness_panels [max_panels]Panel
	brightness_gate   voidptr
)

fn enter() {
	if brightness_gate == unsafe { nil } {
		brightness_gate = acpisync.create(true)
	}
	acpisync.acquire(brightness_gate, 0xffff)
}

fn leave() {
	acpisync.signal(brightness_gate)
}

// Give the panel what it should have now. Call with the gate held.
fn (mut panel Panel) apply() bool {
	wanted := if panel.asleep || panel.power != power_on { u32(0) } else { panel.level }
	if !panel.set(panel.context, wanted) {
		panel.failures++
		return false
	}
	panel.given = wanted
	return true
}

// Add a panel, lit at `level` if `known`, and otherwise at a level nobody
// knows. None when there is no room, or it has no way to be set.
pub fn register(panel Panel, level u32, known bool) ?&Panel {
	if panel.set == unsafe { nil } || panel.max == 0 {
		return none
	}
	enter()
	for i in 0 .. max_panels {
		mut slot := unsafe { &brightness_panels[i] }
		if slot.used {
			continue
		}
		unsafe {
			*slot = panel
		}
		slot.used = true
		slot.level = if level > panel.max { panel.max } else { level }
		slot.given = slot.level
		slot.power = power_on
		slot.known = known
		leave()
		publish(mut slot)
		return slot
	}
	leave()
	return none
}

// The level asked for.
pub fn (panel &Panel) asked() u32 {
	return panel.level
}

// Ask for `level`. False when the panel would not take it.
pub fn (mut panel Panel) ask(level u32) bool {
	enter()
	panel.level = if level > panel.max { panel.max } else { level }
	panel.known = true
	done := panel.apply()
	leave()
	return done
}

// A brightness key: `by` levels up or down, staying within what there is.
pub fn (mut panel Panel) step(by int) bool {
	enter()
	mut level := i64(panel.level) + i64(by)
	if level < 0 {
		level = 0
	}
	if level > i64(panel.max) {
		level = i64(panel.max)
	}
	panel.level = u32(level)
	panel.known = true
	done := panel.apply()
	leave()
	return done
}

// For a sleep: the panel is given its lowest level, and the level asked for
// is kept. A panel at a level nobody knows is left as it is.
pub fn (mut panel Panel) put_down() bool {
	enter()
	mut done := true
	if panel.known {
		panel.asleep = true
		panel.downs++
		done = panel.apply()
	}
	leave()
	return done
}

// After a sleep: the panel is given what was asked for again, whatever it
// came back with.
pub fn (mut panel Panel) bring_back() bool {
	enter()
	mut done := true
	if panel.asleep {
		panel.asleep = false
		done = panel.apply()
	}
	leave()
	return done
}

// ── /sys/class/backlight ────────────────────────────────────────────────────

fn panel_path(panel &Panel, file string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(64) }
	text.add('class/backlight/')
	text.add(panel.name)
	if file.len != 0 {
		text.add_byte(`/`)
		text.add(file)
	}
	return text.str()
}

fn number(mut text lib.Text, value u64) {
	text.add_unsigned(value)
	text.add_byte(`\n`)
}

fn show_brightness(context voidptr, mut text lib.Text) {
	panel := unsafe { &Panel(context) }
	number(mut text, u64(panel.level))
}

fn show_max(context voidptr, mut text lib.Text) {
	panel := unsafe { &Panel(context) }
	number(mut text, u64(panel.max))
}

// What the panel says; where it cannot, what it was last given.
fn show_actual(context voidptr, mut text lib.Text) {
	mut panel := unsafe { &Panel(context) }
	mut level := panel.given
	if panel.get != unsafe { nil } {
		enter()
		if found := panel.get(panel.context) {
			level = found
		}
		leave()
	}
	number(mut text, u64(level))
}

fn show_power(context voidptr, mut text lib.Text) {
	panel := unsafe { &Panel(context) }
	number(mut text, u64(panel.power))
}

fn show_type(context voidptr, mut text lib.Text) {
	panel := unsafe { &Panel(context) }
	text.add(panel.kind)
	text.add_byte(`\n`)
}

// Vinix's: how often the panel went down for a sleep and how often it would
// not take a level.
fn show_stats(context voidptr, mut text lib.Text) {
	panel := unsafe { &Panel(context) }
	text.add('sleeps: ')
	number(mut text, panel.downs)
	text.add('failures: ')
	number(mut text, panel.failures)
}

fn store_brightness(context voidptr, data &u8, length u64) u64 {
	mut panel := unsafe { &Panel(context) }
	level := fs.sysfs_unsigned(data, length) or { return errno.einval }
	if level > u64(panel.max) {
		return errno.einval
	}
	return if panel.ask(u32(level)) { u64(0) } else { u64(errno.eio) }
}

// Linux takes any of its blanking numbers and treats all but 0 as off.
fn store_power(context voidptr, data &u8, length u64) u64 {
	mut panel := unsafe { &Panel(context) }
	value := fs.sysfs_unsigned(data, length) or { return errno.einval }
	if value > u64(power_off) {
		return errno.einval
	}
	enter()
	panel.power = u32(value)
	done := panel.apply()
	leave()
	return if done { u64(0) } else { u64(errno.eio) }
}

fn publish(mut panel Panel) {
	fs.sysfs_directory('class/backlight')
	files := ['brightness', 'max_brightness', 'actual_brightness', 'bl_power', 'type', 'stats']!
	for i in 0 .. files.len {
		path := panel_path(panel, files[i])
		match i {
			0 { fs.sysfs_attribute(path, 0o644, show_brightness, store_brightness, voidptr(panel)) }
			1 { fs.sysfs_attribute(path, 0o444, show_max, unsafe { nil }, voidptr(panel)) }
			2 { fs.sysfs_attribute(path, 0o444, show_actual, unsafe { nil }, voidptr(panel)) }
			3 { fs.sysfs_attribute(path, 0o644, show_power, store_power, voidptr(panel)) }
			4 { fs.sysfs_attribute(path, 0o444, show_type, unsafe { nil }, voidptr(panel)) }
			else { fs.sysfs_attribute(path, 0o444, show_stats, unsafe { nil }, voidptr(panel)) }
		}
		unsafe { path.free() }
	}
}
