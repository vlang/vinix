// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What may end a sleep.
//
// A sleeping machine is woken by something happening: a key, the lid, the
// power button, an alarm. The code that notices such a thing -- a keyboard
// driver, the ACPI event thread -- reports it here whether or not the machine
// is asleep, and this module decides what it means: while awake it is only
// counted; while the machine sleeps and that source is allowed to wake it,
// the sleeper is woken and told which source it was.
//
// This is a leaf: drivers report to it and the suspend code waits on it, and
// it knows about neither.
@[has_globals]
module wakesrc

import event
import event.eventstruct
import katomic

pub enum Source {
	power_button
	sleep_button
	lid
	keyboard
	pointer
	alarm
	network
	usb
	// A battery about to give out: the machine wakes to shut down properly.
	battery
	// Something the embedded controller reported that nothing above claimed:
	// a hotkey, the charger. A lid or a battery reports itself.
	ec
}

pub const source_count = 10

__global (
	// One bit per source that may end a sleep.
	wakesrc_allowed u32
	// How often each has been reported, and how often it ended a sleep.
	wakesrc_events  [source_count]u64
	wakesrc_wakeups [source_count]u64
	// Set while a sleeper waits.
	wakesrc_armed u32
	// The source that ended the last sleep, plus one; zero for none.
	wakesrc_last  u32
	wakesrc_event eventstruct.Event
	wakesrc_ready bool
)

pub fn name(source Source) string {
	return match source {
		.power_button { 'power-button' }
		.sleep_button { 'sleep-button' }
		.lid { 'lid' }
		.keyboard { 'keyboard' }
		.pointer { 'pointer' }
		.alarm { 'alarm' }
		.network { 'network' }
		.usb { 'usb' }
		.battery { 'battery' }
		.ec { 'embedded-controller' }
	}
}

// What wakes a machine nobody has configured: what its user would reach for.
// A pointer is left out, since a mouse nudged on a desk should not light the
// room at night; the network, since being woken by it is asked for; and the
// embedded controller, which reports every tick of the battery gauge.
fn defaults() u32 {
	return (u32(1) << u32(Source.power_button)) | (u32(1) << u32(Source.sleep_button)) | (u32(1) << u32(Source.lid)) | (u32(1) << u32(Source.keyboard)) | (u32(1) << u32(Source.alarm)) | (u32(1) << u32(Source.battery))
}

fn ensure() {
	if !wakesrc_ready {
		wakesrc_allowed = defaults()
		wakesrc_ready = true
	}
}

pub fn allowed(source Source) bool {
	ensure()
	return katomic.load(&wakesrc_allowed) & (u32(1) << u32(source)) != 0
}

pub fn allow(source Source, yes bool) {
	ensure()
	bit := u32(1) << u32(source)
	for {
		before := katomic.load(&wakesrc_allowed)
		after := if yes { before | bit } else { before & ~bit }
		if before == after || katomic.cas(mut &wakesrc_allowed, before, after) {
			return
		}
	}
}

pub fn events(source Source) u64 {
	return katomic.load(&wakesrc_events[int(source)])
}

pub fn wakeups(source Source) u64 {
	return katomic.load(&wakesrc_wakeups[int(source)])
}

// `source` happened. Safe from an interrupt, and cheap when nothing sleeps.
pub fn report(source Source) {
	katomic.inc(mut &wakesrc_events[int(source)])
	if katomic.load(&wakesrc_armed) == 0 || !allowed(source) {
		return
	}
	// The first report since the sleeper armed is the one that woke it.
	if katomic.cas(mut &wakesrc_last, u32(0), u32(source) + 1) {
		katomic.inc(mut &wakesrc_wakeups[int(source)])
	}
	event.trigger(mut wakesrc_event, false)
}

// `source` is what ended a sleep the platform carried out by itself -- a
// suspend to RAM, where no code of the kernel's was running to see the event
// arrive. It is recorded as the wakeup whatever is allowed: the machine did
// wake, and saying what woke it is not the place to enforce what should.
// Replaces anything reported while the machine was coming back.
pub fn woke(source Source) {
	katomic.inc(mut &wakesrc_events[int(source)])
	if katomic.load(&wakesrc_armed) == 0 {
		return
	}
	katomic.store(mut &wakesrc_last, u32(source) + 1)
	katomic.inc(mut &wakesrc_wakeups[int(source)])
	event.trigger(mut wakesrc_event, false)
}

// Whether a sleeper is waiting: for a driver that has to do something extra
// to notice its event at all while the machine sleeps.
pub fn sleeping() bool {
	return katomic.load(&wakesrc_armed) != 0
}

// Start listening: from here on an allowed report counts as a wakeup. Called
// before the devices are suspended, so that an event arriving while they go
// down is not lost.
pub fn arm() {
	ensure()
	katomic.store(mut &wakesrc_last, u32(0))
	katomic.store(mut &wakesrc_armed, u32(1))
}

// Whether something has asked for a wakeup since arm().
pub fn pending() bool {
	return katomic.load(&wakesrc_last) != 0
}

// Block until an allowed source reports. Returns at once if one already has.
pub fn wait() {
	for {
		generation := event.generation(mut wakesrc_event)
		if pending() {
			return
		}
		event.await_one_from_generation(mut wakesrc_event, true, generation) or {}
	}
}

// Stop listening. The source that ended the sleep, or none.
pub fn disarm() ?Source {
	katomic.store(mut &wakesrc_armed, u32(0))
	last := katomic.load(&wakesrc_last)
	if last == 0 {
		return none
	}
	return unsafe { Source(int(last - 1)) }
}

// The source that ended the last sleep, or none.
pub fn last() ?Source {
	value := katomic.load(&wakesrc_last)
	if value == 0 {
		return none
	}
	return unsafe { Source(int(value - 1)) }
}
