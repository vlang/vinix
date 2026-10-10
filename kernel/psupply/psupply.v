// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Power supplies: the batteries and chargers a machine runs from.
//
// A driver that can read a battery or tell whether the charger is plugged in
// -- ACPI on a PC, the SMC on an Apple machine -- registers a supply here with
// one function that fills in a Reading. This module does the rest for every
// such driver alike: it keeps the reading fresh without asking firmware more
// than once a second, smooths the rate into an estimate of the time left
// (estimate.v), publishes the lot in /sys/class/power_supply by Linux's names
// (sysfs.v), and acts when a battery runs low.
//
// What happens then is policy, and small: at the low threshold the fact is
// logged and visible in capacity_level for a desktop to show; at the critical
// threshold, while still discharging, the machine is asked to shut down
// through the handler the power management code installs, once per discharge.
// Running flat with files open costs more than turning off a minute early.
@[has_globals]
module psupply

import acpisync
import devcore
import event
import event.eventstruct
import katomic
import sched

pub enum Kind {
	battery
	mains
}

pub const text_bytes = 32

// What a driver reports. Amounts are in micro-watt-hours and rates in
// micro-watts, or micro-ampere-hours and micro-amperes when `in_charge` is
// set: a battery counts one or the other, and the files it is published
// under differ, as on Linux. Zero means "not reported" for everything but
// `amount`.
pub struct Reading {
pub mut:
	present bool
	// A charger: whether it is supplying power.
	online bool
	status Status
	in_charge bool
	amount    u64
	full      u64
	design    u64
	rate      u64
	voltage_uv        u64
	design_voltage_uv u64
	cycles            u64
	// Firmware's own verdict that the battery is about to give out.
	critical bool
	// Firmware's own estimates, in seconds, where it makes them.
	firmware_to_empty_s u64
	firmware_to_full_s  u64
	// Percent the battery stops charging at, when the driver can say; zero
	// when it cannot.
	charge_limit u64
	technology     [text_bytes]u8
	technology_len int
	model          [text_bytes]u8
	model_len      int
	serial         [text_bytes]u8
	serial_len     int
	maker          [text_bytes]u8
	maker_len      int
}

pub struct Supply {
pub mut:
	// "BAT0", "AC": the directory under /sys/class/power_supply.
	name string
	kind Kind
	// Fill in `reading`. False when the supply could not be read at all, which
	// is not the same as a battery that is not there.
	read fn (context voidptr, mut reading Reading) bool = unsafe { nil }
	// Stop charging at `percent`. Nil when the hardware has no such thing.
	set_charge_limit fn (context voidptr, percent u64) bool = unsafe { nil }
	context          voidptr

	used      bool
	reading   Reading
	read_ns   u64
	read_ok   bool
	failures  u64
	estimator Estimator
	percent   int
	to_empty  u64
	to_full   u64
	// The alarm already acted on, so that each is acted on once per discharge.
	alarmed Alarm
	refs    [attribute_count]AttributeRef
}

pub const max_supplies = 8

// A reading is asked for again when it is older than this and somebody wants
// one; otherwise firmware would be asked once per file read.
const fresh_ns = u64(1000000000)
// How often every supply is read whether or not anybody asked.
const poll_ms = u64(30000)

struct Policy {
mut:
	low_percent      int
	critical_percent int
	critical         fn () = unsafe { nil }
	source_changed   fn (on_battery bool) = unsafe { nil }
}

__global (
	psupply_table   [max_supplies]Supply
	// Serializes reads of the supplies: a driver's read waits for firmware.
	psupply_gate    voidptr
	psupply_policy  Policy
	psupply_wake    eventstruct.Event
	psupply_started bool
	psupply_published bool
	// Whether the machine last ran from a battery, and whether that is known.
	psupply_on_battery u32
)

fn gate() voidptr {
	if psupply_gate == unsafe { nil } {
		psupply_gate = acpisync.create(true)
		psupply_policy.low_percent = 10
		psupply_policy.critical_percent = 3
	}
	return psupply_gate
}

// What is called when a battery reaches the critical threshold while
// discharging: the machine's orderly way out.
pub fn on_critical(handler fn ()) {
	gate()
	psupply_policy.critical = handler
}

// What is called when the machine goes onto or off its battery.
pub fn on_source_change(handler fn (on_battery bool)) {
	gate()
	psupply_policy.source_changed = handler
}

pub fn low_percent() int {
	gate()
	return psupply_policy.low_percent
}

pub fn critical_percent() int {
	gate()
	return psupply_policy.critical_percent
}

// Set the two thresholds. False when they are not 0 <= critical < low <= 50.
pub fn set_thresholds(low int, critical int) bool {
	gate()
	if critical < 0 || critical >= low || low > 50 {
		return false
	}
	psupply_policy.low_percent = low
	psupply_policy.critical_percent = critical
	return true
}

// Add a supply. The record is copied; the pointer returned is the module's
// own and stays good until unregister(). None when the table is full or the
// name is taken.
pub fn register(supply Supply) ?&Supply {
	acpisync.acquire(gate(), 0xffff)
	mut slot := &Supply(unsafe { nil })
	for i in 0 .. max_supplies {
		if psupply_table[i].used && psupply_table[i].name == supply.name {
			acpisync.signal(psupply_gate)
			return none
		}
	}
	for i in 0 .. max_supplies {
		if !psupply_table[i].used {
			slot = unsafe { &psupply_table[i] }
			break
		}
	}
	if slot == unsafe { nil } {
		acpisync.signal(psupply_gate)
		return none
	}
	unsafe {
		*slot = supply
	}
	slot.name = supply.name.clone()
	slot.used = true
	slot.read_ns = 0
	slot.read_ok = false
	slot.percent = -1
	slot.alarmed = .none
	slot.estimator = Estimator{}
	acpisync.signal(psupply_gate)
	// Read before publishing: which files a battery has depends on what it
	// counts in.
	refresh(mut slot, true)
	if psupply_published {
		publish_supply(mut slot)
	}
	// Let the policy thread know there is something to watch.
	event.trigger(mut psupply_wake, false)
	return slot
}

// Take a supply away: the battery was pulled, its driver unbound. The files
// go first, since a read of one of them would use the driver.
pub fn unregister(mut supply Supply) {
	if !supply.used {
		return
	}
	unpublish_supply(mut supply)
	acpisync.acquire(gate(), 0xffff)
	supply.used = false
	supply.read = unsafe { nil }
	unsafe { supply.name.free() }
	supply.name = ''
	acpisync.signal(psupply_gate)
}

// The driver heard that something changed: read again now, and let the
// policy look at it.
pub fn changed(mut supply Supply) {
	supply.read_ns = 0
	event.trigger(mut psupply_wake, false)
}

// Bring a supply's reading up to date. With `force`, even if it is fresh.
// Never called with the gate held.
fn refresh(mut supply Supply, force bool) {
	if !supply.used || supply.read == unsafe { nil } {
		return
	}
	now := devcore.now_ns()
	if !force && supply.read_ns != 0 && now - supply.read_ns < fresh_ns {
		return
	}
	acpisync.acquire(gate(), 0xffff)
	defer {
		acpisync.signal(psupply_gate)
	}
	// Somebody else may have read it while this waited.
	if !supply.used || supply.read == unsafe { nil } {
		return
	}
	if !force && supply.read_ns != 0 && devcore.now_ns() - supply.read_ns < fresh_ns {
		return
	}
	mut reading := Reading{}
	if !supply.read(supply.context, mut reading) {
		supply.failures++
		supply.read_ok = false
		supply.read_ns = devcore.now_ns()
		return
	}
	supply.reading = reading
	supply.read_ok = true
	supply.read_ns = devcore.now_ns()
	if supply.kind != .battery || !reading.present {
		supply.percent = -1
		supply.to_empty = 0
		supply.to_full = 0
		return
	}
	supply.percent = percent_of(reading.amount, reading.full)
	supply.estimator.sample(reading.status, reading.amount, reading.rate, supply.read_ns)
	// Firmware that makes its own estimate knows things this cannot: how the
	// cells behave near empty, what the charger will taper to.
	supply.to_empty = if reading.firmware_to_empty_s != 0 {
		reading.firmware_to_empty_s
	} else {
		supply.estimator.seconds_to_empty(reading.amount)
	}
	supply.to_full = if reading.firmware_to_full_s != 0 {
		reading.firmware_to_full_s
	} else {
		supply.estimator.seconds_to_full(reading.amount, reading.full)
	}
}

// Whether the machine is running from a battery: some battery is
// discharging and no charger is supplying power. False when there is no
// battery at all.
pub fn on_battery() bool {
	mut discharging := false
	mut charger := false
	for i in 0 .. max_supplies {
		supply := unsafe { &psupply_table[i] }
		if !supply.used || !supply.read_ok {
			continue
		}
		if supply.kind == .mains && supply.reading.online {
			charger = true
		}
		if supply.kind == .battery && supply.reading.present && supply.reading.status == .discharging {
			discharging = true
		}
	}
	return discharging && !charger
}

// The fullest battery's percentage, or -1 without one.
pub fn battery_percent() int {
	mut best := -1
	for i in 0 .. max_supplies {
		supply := unsafe { &psupply_table[i] }
		if supply.used && supply.read_ok && supply.kind == .battery && supply.reading.present
			&& supply.percent > best {
			best = supply.percent
		}
	}
	return best
}

fn apply_policy() {
	battery := on_battery()
	state := if battery { u32(2) } else { u32(1) }
	if katomic.load(&psupply_on_battery) != state {
		katomic.store(mut &psupply_on_battery, state)
		if psupply_policy.source_changed != unsafe { nil } {
			psupply_policy.source_changed(battery)
		}
	}
	for i in 0 .. max_supplies {
		mut supply := unsafe { &psupply_table[i] }
		if !supply.used || !supply.read_ok || supply.kind != .battery || !supply.reading.present {
			continue
		}
		alarm := alarm_of(supply.percent, supply.reading.status, supply.reading.critical,
			psupply_policy.low_percent, psupply_policy.critical_percent)
		if alarm == .none {
			// Charging again, or above the thresholds: the next discharge
			// starts with a clean slate.
			supply.alarmed = .none
			continue
		}
		if alarm == supply.alarmed || (alarm == .low && supply.alarmed == .critical) {
			continue
		}
		supply.alarmed = alarm
		if alarm == .low {
			C.kprintf(c'psupply: %.*s is low: %lld%%\n', i32(supply.name.len), supply.name.str,
				i64(supply.percent))
			continue
		}
		C.kprintf(c'psupply: %.*s is critical at %lld%%; shutting down\n', i32(supply.name.len),
			supply.name.str, i64(supply.percent))
		if psupply_policy.critical != unsafe { nil } {
			psupply_policy.critical()
		}
	}
}

fn poll_thread() {
	for {
		generation := event.generation(mut psupply_wake)
		mut any := false
		for i in 0 .. max_supplies {
			mut supply := unsafe { &psupply_table[i] }
			if supply.used {
				any = true
				refresh(mut supply, true)
			}
		}
		if any {
			apply_policy()
			// Until changed() says otherwise, or poll_ms have passed.
			devcore.wait_event(mut psupply_wake, generation, poll_ms)
		} else {
			// A machine with no battery and no charger to read: nothing to
			// do until a driver registers one.
			event.await_one_from_generation(mut psupply_wake, true, generation) or {}
		}
	}
}

// Start the thread that keeps readings fresh and applies the policy. Called
// once the scheduler runs.
pub fn start() {
	if psupply_started {
		return
	}
	gate()
	psupply_started = true
	sched.new_kernel_thread(voidptr(poll_thread), unsafe { nil }, true)
}
