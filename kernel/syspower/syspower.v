// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Turning the machine off, and restarting it.
//
// reboot(2) used to flush the page cache and call firmware. The devices were
// never told: a disk kept the last writes in its own cache when the power
// went, a network card carried on writing received frames into memory the
// next kernel was already using, and a restart handed firmware controllers
// that were still running. The order here is the one every transition takes:
//
//  1. the filesystems' cached writes go to their devices, and a failure
//     refuses the transition rather than completing it with data lost;
//  2. every device is shut down through the device core, last added first:
//     a disk's cache is flushed and the disk told to stop, DMA and interrupts
//     are switched off;
//  3. firmware is asked for the transition, and if it does not take the
//     machine away, the platform's fallbacks are tried in turn.
//
// A halt stops at step 2: the machine is left quiet, with nothing more to
// lose, for whoever is going to cut the power.
@[has_globals]
module syspower

import devcore
import katomic
import pagecache

pub enum Action {
	power_off
	restart
	halt
}

__global (
	// Set by the first transition to get past its flush. A second caller --
	// init and a power button, say -- waits for the first rather than
	// shutting the devices down twice.
	syspower_transition u32
)

pub fn action_name(action Action) string {
	return match action {
		.power_off { 'power off' }
		.restart { 'restart' }
		.halt { 'halt' }
	}
}

// Carry out `action`. Returns only if it could not be done: false with
// nothing changed when cached writes could not be flushed, false with the
// devices already stopped when firmware would not let go of the machine.
pub fn transition(action Action) bool {
	// Not in the middle of a sleep. Whoever is carrying one out has the
	// devices down and the bindings frozen, and for a suspend to disk ends
	// it by switching the machine off itself: a second thread that set off
	// now would take the right to do that and then wait, for good, on what
	// the first is holding. It waits here instead, holding nothing.
	for sleeping() {
		devcore.sleep_ms(100)
	}
	// Nothing leaves the machine with unwritten data: a failed flush refuses
	// the transition rather than completing it.
	if !pagecache.sync_all() {
		return false
	}
	return carry_out(action)
}

// The transition without the flush: steps 2 and 3. For transition(), and for
// a suspend to disk, which has flushed the filesystems before it took its
// image of memory and must not have them written to after.
fn carry_out(action Action) bool {
	if !platform_prepare() {
		return false
	}
	if !katomic.cas(mut &syspower_transition, u32(0), u32(1)) {
		for {
			devcore.sleep_ms(1000)
		}
	}
	name := action_name(action)
	C.kprintf(c'syspower: %.*s: stopping devices\n', i32(name.len), name.str)
	devcore.shutdown_all()
	match action {
		.power_off { platform_power_off() }
		.restart { platform_restart() }
		.halt {}
	}
	if action == .halt {
		print('syspower: halted; it is now safe to turn the machine off\n')
	} else {
		C.kprintf(c'syspower: firmware did not %.*s the machine; halted with devices stopped\n',
			i32(name.len), name.str)
	}
	platform_halt()
	return false
}
