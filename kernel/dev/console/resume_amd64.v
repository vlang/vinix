// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The keyboard controller after a suspend to RAM.
//
// The 8042 loses its command byte with the power. What comes back is
// firmware's or the chip's default: scancodes are no longer translated to the
// set the keyboard thread reads, and interrupts may be off. So the controller
// is told again what keyboard_handler() told it at boot -- both ports off
// while it is talked to, the buffer emptied, the command byte, the ports on
// again -- with every wait bounded, since this runs on the way out of a sleep
// and a controller that does not answer must not keep the machine there.
//
// The command byte is written from the copy kept when it was last set, not
// read back first: the controller's answer to a read arrives like a key, with
// the keyboard's interrupt, and the keyboard thread would take it for one.
//
// The pointer's interrupt is left off here. The mouse on the second port has
// lost its settings too, and the answers to the commands that restore them
// must not reach its handler as movement; dev.mouse switches the interrupt
// back on when it is done (pointer_interrupt()).
//
// After a suspend to idle nothing was lost and nothing is done: the
// controller is what woke the machine, and is left as it is.
@[has_globals]
module console

import devcore
import x86.kio

// Reads of the status port a healthy controller answers well within.
const ps2_spins = 200000

const ps2_keyboard_interrupt = u8(1) << 0
const ps2_pointer_interrupt = u8(1) << 1
const ps2_keyboard_clock_off = u8(1) << 4
const ps2_pointer_clock_off = u8(1) << 5
const ps2_translate = u8(1) << 6

__global (
	// The command byte as the kernel last set it, with both ports on; 0 until
	// it has.
	console_ps2_config u8
	// Whether the controller has a second port.
	console_ps2_pointer bool
)

fn ps2_can_write() bool {
	for _ in 0 .. ps2_spins {
		if kio.port_in[u8](0x64) & 2 == 0 {
			return true
		}
	}
	return false
}

fn ps2_command(value u8) bool {
	if !ps2_can_write() {
		return false
	}
	kio.port_out[u8](0x64, value)
	return true
}

fn ps2_set_config(value u8) bool {
	if !ps2_command(0x60) || !ps2_can_write() {
		return false
	}
	kio.port_out[u8](0x60, value)
	return true
}

fn ps2_flush() {
	for _ in 0 .. 64 {
		if kio.port_in[u8](0x64) & 1 == 0 {
			return
		}
		kio.port_in[u8](0x60)
	}
}

// What keyboard_handler() has just written to the controller, to be written
// again after a loss of power.
fn remember_ps2_config(config u8) {
	console_ps2_pointer = config & ps2_pointer_clock_off != 0
	console_ps2_config = config & ~(ps2_keyboard_clock_off | ps2_pointer_clock_off)
}

// Switch the pointer's interrupt on or off in the controller. For dev.mouse,
// around the commands it sets the mouse up with. False when the controller's
// command byte is not known or the controller does not take it.
pub fn pointer_interrupt(on bool) bool {
	if console_ps2_config == 0 || !console_ps2_pointer {
		return false
	}
	config := if on {
		console_ps2_config | ps2_pointer_interrupt
	} else {
		console_ps2_config & ~ps2_pointer_interrupt
	}
	if !ps2_set_config(config) {
		return false
	}
	console_ps2_config = config
	return true
}

fn keyboard_suspend(mut _ devcore.Device) bool {
	return true
}

fn keyboard_resume(mut _ devcore.Device) bool {
	if !devcore.power_lost() || console_ps2_config == 0 {
		return true
	}
	// All ones is a machine with no such controller.
	if kio.port_in[u8](0x64) == 0xff {
		return true
	}
	if !ps2_command(0xad) || !ps2_command(0xa7) {
		return false
	}
	ps2_flush()
	config := (console_ps2_config | ps2_keyboard_interrupt | ps2_translate) & ~ps2_pointer_interrupt
	if !ps2_set_config(config) {
		return false
	}
	console_ps2_config = config
	if !ps2_command(0xae) {
		return false
	}
	if console_ps2_pointer {
		ps2_command(0xa8)
	}
	// No key is down as far as the kernel knows: whatever was held when the
	// machine went to sleep was let go while it slept.
	console_shift_active = false
	console_ctrl_active = false
	console_alt_active = false
	console_alt_keys = 0
	console_alt_tab_chorded = false
	console_meta_active = false
	console_meta_chorded = false
	console_extra_scancodes = false
	return true
}

// Put the keyboard controller in the device core's list, so that it is
// resumed with the other devices. Called once, when the console starts.
fn register_keyboard_controller() {
	devcore.register_driver(devcore.Driver{
		name:    'i8042'
		bus:     .platform
		suspend: keyboard_suspend
		resume:  keyboard_resume
	}) or { return }
	devcore.claim_platform('i8042', 'pnp0303', 'i8042')
}
