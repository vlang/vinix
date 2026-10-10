// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The power and sleep buttons.
//
// A press is reported by whatever hears it -- ACPI on a PC, a GPIO key on a
// virtual ARM machine -- from a thread or an interrupt, and is acted on by a
// thread of this module's, since the answer may be to stop every device.
//
// The power button asks for the machine to be turned off, and the session
// decides how: init is sent the signal `poweroff` sends it, so that a desktop
// saves what is open and a test program ends its test. An init that has no
// handler for that signal is not asked -- the default action would kill it --
// and the kernel turns the machine off itself, storage flushed and devices
// stopped, which is still better than a button that does nothing.
@[has_globals]
module syspower

import event
import event.eventstruct
import katomic
import psupply
import sched
import wakesrc

pub enum Button {
	power
	sleep
}

// What busybox's poweroff sends init, and what Vinix's inits act on.
const signal_power_off = 12

struct Hooks {
mut:
	signal_init fn (signal int) bool = unsafe { nil }
}

__global (
	syspower_hooks   Hooks
	syspower_wake    eventstruct.Event
	// One bit per Button waiting to be acted on.
	syspower_pending u32
	syspower_presses [2]u64
	syspower_started bool
	// Set when a critical battery woke the machine: it shuts down once awake.
	syspower_critical_wake u32
)

// How init is asked for something: sends it `signal` and returns true if it
// has a handler for it. The signal code sits above this module.
pub fn set_init_signal(send fn (signal int) bool) {
	syspower_hooks.signal_init = send
}

// A button was pressed. Safe from an interrupt. Pressed while the machine
// sleeps, a button wakes it and does nothing else: nobody means "turn off"
// by the press that brings a sleeping laptop back.
pub fn button(kind Button) {
	katomic.inc(mut &syspower_presses[int(kind)])
	if sleeping() {
		wakesrc.report(if kind == .power { wakesrc.Source.power_button } else { wakesrc.Source.sleep_button })
		return
	}
	bit := u32(1) << u32(kind)
	for {
		pending := katomic.load(&syspower_pending)
		if pending & bit != 0 || katomic.cas(mut &syspower_pending, pending, pending | bit) {
			break
		}
	}
	event.trigger(mut syspower_wake, false)
}

pub fn button_presses(kind Button) u64 {
	return katomic.load(&syspower_presses[int(kind)])
}

// Start the thread that acts on buttons, and the platform's sources of them.
// Called once the scheduler runs and init's signals can be delivered.
pub fn start() {
	if syspower_started {
		return
	}
	syspower_started = true
	sched.new_kernel_thread(voidptr(button_thread), unsafe { nil }, true)
	// A battery about to give out asks for what the power button asks for.
	psupply.on_critical(battery_critical)
	psupply.start()
	platform_start()
}

fn take_pending() u32 {
	for {
		pending := katomic.load(&syspower_pending)
		if pending == 0 || katomic.cas(mut &syspower_pending, pending, u32(0)) {
			return pending
		}
	}
	return 0
}

fn button_thread() {
	for {
		generation := event.generation(mut syspower_wake)
		pending := take_pending()
		if pending == 0 {
			event.await_one_from_generation(mut syspower_wake, true, generation) or {}
			continue
		}
		if pending & (u32(1) << u32(Button.power)) != 0 {
			power_button()
		}
		if pending & lid_bit != 0 {
			lid_closed_action()
		}
		if pending & (u32(1) << u32(Button.sleep)) != 0 {
			sleep_button()
		}
	}
}

fn power_button() {
	if syspower_hooks.signal_init != unsafe { nil } && syspower_hooks.signal_init(signal_power_off) {
		return
	}
	print('syspower: power button: nobody to ask, powering off\n')
	transition(.power_off)
}

// The sleep button sleeps the way `mem` in /sys/power/state does.
fn sleep_button() {
	enter_sleep(if mem_is_deep() { SleepDepth.deep } else { SleepDepth.idle })
}

// A battery is about to give out. Awake, that is the power button's request.
// Asleep, the machine is woken first -- a frozen init cannot save anything --
// and the request is made once it is back; see enter_sleep().
fn battery_critical() {
	if sleeping() {
		katomic.store(mut &syspower_critical_wake, u32(1))
		wakesrc.report(.battery)
		return
	}
	request_power_off()
}

// Ask for the machine to be turned off the way the power button does, whether
// or not a sleep is in progress.
fn request_power_off() {
	bit := u32(1) << u32(Button.power)
	for {
		pending := katomic.load(&syspower_pending)
		if pending & bit != 0 || katomic.cas(mut &syspower_pending, pending, pending | bit) {
			break
		}
	}
	event.trigger(mut syspower_wake, false)
}
