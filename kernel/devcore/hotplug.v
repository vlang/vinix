// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// PCI devices that come and go while the machine runs.
//
// A PCI Express port with a slot says in its registers whether a card is in
// the slot, and has a switch for the slot's power, lights, and a button the
// person at the machine presses to ask for the card back. One thread looks at
// every such port twice a second and does what Linux's pciehp does in its
// polling mode:
//
//	a card appears    the slot is given power, the link is waited for, the
//	                  card's functions are found, given addresses out of the
//	                  port's windows (pci/hotadd.v) and handed to the device
//	                  core, whose drivers bind to them as they do at boot;
//	the button        the power light blinks for five seconds, in which a
//	                  second press calls it off; then each function's driver
//	                  is told to let go, the functions are removed and the
//	                  slot's power is cut, and only then is the card safe to
//	                  pull;
//	a card vanishes   pulled without asking: its drivers are told the same,
//	                  with the device already gone, and must cope with
//	                  registers that read all ones.
//
// The ports are polled, not listened to: a port's hot-plug interrupt needs an
// interrupt route this kernel does not set up for bridges. A press or a card
// is noticed within half a second, and a machine with no such port has no
// polling.
//
// The same thread does the bus rescan /sys/bus/pci/rescan asks for, so that
// only one thread ever changes which PCI functions exist: every address on
// every known bus is tried, and a function nobody has is treated as an
// arrival. That is how a device removed through its own `remove` file comes
// back.
//
// Whose ports they are is firmware's to say. A PC's firmware may keep its
// ports and do the watching itself, telling the system through ACPI that a
// device at some address should be looked for or is wanted back
// (x86/acpihp); those two requests are carried out here as well, by the same
// thread, and then no port's registers are touched. start_pci_hotplug() is
// told which it is.
//
// Each slot is in /sys as Linux has it:
//
//	/sys/bus/pci/slots/<number>/address   the bus and device behind the port
//	/sys/bus/pci/slots/<number>/adapter   1 while a card is in the slot
//	/sys/bus/pci/slots/<number>/power     1 while the slot is powered; write
//	                                      0 to take the card out of use as
//	                                      the button does, without the wait,
//	                                      and 1 to bring it back
//	/sys/bus/pci/slots/<number>/state     empty, occupied, leaving or off
//	/sys/bus/pci/slots/<number>/events    arrivals, departures and failures
//
// Not done: a bridge that arrives is listed but nothing behind it is found
// (no bus numbers or windows are made for it); ports are not asked for more
// room than firmware gave them, so a card that needs more than its port's
// window gets no address for the registers that did not fit; and a device
// that arrives on the root bus, which no bridge's windows describe, is found
// but given no addresses.
@[has_globals]
module devcore

import errno
import event
import event.eventstruct
import fs
import katomic
import klock
import lib
import pci
import sched

enum SlotState {
	// Nothing in the slot.
	empty
	// A card in use.
	occupied
	// The button was pressed; the card is in use until the wait is over.
	leaving
	// A card is in the slot and is not in use: taken out of use and not
	// pulled yet, or never answered.
	off
}

struct Slot {
mut:
	port &pci.PCIDevice = unsafe { nil }
	// Where the port's Express capability starts.
	express      u32
	capabilities u32
	number       u32
	label        string
	state        SlotState
	leave_at     Deadline
	// What /sys asked for: slot_want_on or slot_want_off.
	want u32

	arrivals   u64
	departures u64
	failures   u64
}

const max_slots = 32
const slot_want_on = u32(1)
const slot_want_off = u32(2)

// How often the ports are looked at.
const slot_poll_ms = u64(500)
// How long a press of the button can be called off by a second one; the
// time the PCI Express specification gives.
const slot_leave_ns = 5 * second
// How long a port may take over a command, and a link to come up.
const slot_command_ns = second
const slot_link_ns = second
// What a card needs between its link coming up and its first configuration
// access.
const slot_settle_ms = u64(100)
// How long a slot's power takes to drain once cut.
const slot_drain_ms = u64(1000)
// A thread with no port to poll still wakes for a rescan; otherwise it has
// nothing to wake for.
const idle_wait_ms = u64(3_600_000)

__global (
	devcore_slots          [max_slots]Slot
	devcore_slot_count     int
	devcore_hotplug_event  eventstruct.Event
	devcore_hotplug_alive  bool
	devcore_rescan_wanted  u32
	devcore_rescans        u64
)

fn (slot &Slot) status() u16 {
	return slot.port.read[u16](slot.express + pci.express_slot_status)
}

// Clear what the port latched; a one clears a bit and a zero leaves it.
fn (slot &Slot) acknowledge(bits u16) {
	slot.port.write[u16](slot.express + pci.express_slot_status, bits)
}

fn command_completed(context voidptr) bool {
	slot := unsafe { &Slot(context) }
	return slot.status() & pci.status_command_completed != 0
}

// Change bits of the slot's control register. A port that reports when a
// command has taken effect is waited for, since it may ignore a second
// command sent before the first is done.
fn (mut slot Slot) command(mask u16, value u16) {
	register := slot.express + pci.express_slot_control
	old := slot.port.read[u16](register)
	updated := (old & ~mask) | (value & mask)
	if updated == old {
		return
	}
	slot.acknowledge(pci.status_command_completed)
	slot.port.write[u16](register, updated)
	if slot.capabilities & pci.slot_no_completion == 0 {
		sleep_until(command_completed, voidptr(slot), slot_command_ns, 10)
		slot.acknowledge(pci.status_command_completed)
	}
}

fn (mut slot Slot) power_light(light u16) {
	if slot.capabilities & pci.slot_has_power_light != 0 {
		slot.command(pci.control_light_mask << pci.control_power_light_shift, light << pci.control_power_light_shift)
	}
}

fn (mut slot Slot) attention_light(light u16) {
	if slot.capabilities & pci.slot_has_attention_light != 0 {
		slot.command(pci.control_light_mask << pci.control_attention_light_shift, light << pci.control_attention_light_shift)
	}
}

fn (mut slot Slot) set_power(on bool) {
	if slot.capabilities & pci.slot_has_power_switch != 0 {
		slot.command(pci.control_power_off, if on { u16(0) } else { pci.control_power_off })
	}
}

fn link_is_up(context voidptr) bool {
	slot := unsafe { &Slot(context) }
	return slot.port.read[u16](slot.express + pci.express_link_status) & pci.link_active != 0
}

fn card_answers(context voidptr) bool {
	slot := unsafe { &Slot(context) }
	return pci.function_answers(slot.port.secondary_bus(), 0, 0)
}

fn slot_state_name(state SlotState) string {
	return match state {
		.empty { 'empty' }
		.occupied { 'occupied' }
		.leaving { 'leaving' }
		.off { 'off' }
	}
}

fn pci_address(p &pci.PCIDevice) i64 {
	return (i64(p.bus) << 8) | (i64(p.slot) << 3) | i64(p.function)
}

// Find the functions of the device at one place on a bus that nobody has
// yet, give them addresses if they need any, and hand them to the core.
// `bridge` is what the bus hangs off, nil for the root bus, where a function
// can be found again but not given addresses. Returns how many were added.
fn scan_place(bus u8, place u8, bridge &pci.PCIDevice) int {
	if !pci.function_answers(bus, place, 0) {
		return 0
	}
	parent := if bridge == unsafe { nil } { i64(-1) } else { pci_address(bridge) }
	mut arrivals := unsafe { [8]&pci.PCIDevice{} }
	mut count := 0
	multi := pci.function_is_multi(bus, place, 0)
	for function := u8(0); function < 8; function++ {
		if function > 0 && !multi {
			break
		}
		if !pci.function_answers(bus, place, function) {
			continue
		}
		known := pci.record_at(bus, place, function)
		if known != unsafe { nil } && known.present() && of_pci(known) != unsafe { nil } {
			continue
		}
		record := pci.adopt_function(bus, place, function, parent)
		if record == unsafe { nil } {
			continue
		}
		arrivals[count] = record
		count++
	}
	if count == 0 {
		return 0
	}
	if bridge != unsafe { nil } {
		pci.configure_arrivals(bridge, arrivals, count)
	}
	mut added := 0
	for i in 0 .. count {
		if arrivals[i].header_type == 1 {
			C.kprintf(c'devcore: the bridge that arrived at %llx:%llx.%llx is not set up; nothing behind it will be found\n',
				u64(bus), u64(place), u64(arrivals[i].function))
		}
		if add_pci(arrivals[i]) != unsafe { nil } {
			added++
		}
	}
	return added
}

// Take every function on the slot's bus away from its driver and out of the
// machine's lists. `orderly` says the card is still there to be told.
fn (mut slot Slot) empty_bus(orderly bool) int {
	secondary := slot.port.secondary_bus()
	if secondary == 0 {
		return 0
	}
	mut gone := 0
	for {
		// One at a time, looking again each time: removing a device removes
		// what hangs off it as well.
		mut record := &pci.PCIDevice(unsafe { nil })
		for candidate in scanned_devices {
			if candidate.bus == secondary && candidate.present() {
				record = unsafe { candidate }
				break
			}
		}
		if record == unsafe { nil } {
			break
		}
		drop_function(mut record, orderly)
		gone++
	}
	return gone
}

// Take one function away from its driver and out of the machine's lists,
// and mark its record as left. `quiet` says the function is still there to
// be told to decode nothing and send nothing while its power goes.
//
// The device is looked up and removed without letting go of the gate in
// between: the other thread that removes devices, the worker carrying out a
// write to a `remove` file, cannot then free it under this one.
fn drop_function(mut record pci.PCIDevice, quiet bool) {
	gate_enter()
	mut dev := of_pci(record)
	mut released := true
	if dev != unsafe { nil } {
		released = remove(mut dev)
	}
	gate_leave()
	if quiet {
		record.update_command(0x7, 0)
	}
	// A record a driver could not let go of is never used again.
	if released {
		record.forget()
	} else {
		record.retire()
	}
}

// A card is in the slot: power, link, functions.
fn (mut slot Slot) bring_in() {
	C.kprintf(c'devcore: slot %.*s: a card is present\n', i32(slot.label.len), slot.label.str)
	slot.acknowledge(pci.status_power_fault)
	slot.set_power(true)
	slot.power_light(pci.light_blink)
	// A port that can say its link is up is waited for; one that cannot is
	// given the time a link is allowed.
	if slot.port.read[u32](slot.express + pci.express_link_capabilities) & pci.link_reports_active != 0 {
		sleep_until(link_is_up, voidptr(slot), slot_link_ns, 10)
	}
	sleep_ms(slot_settle_ms)
	mut added := 0
	if slot.status() & pci.status_power_fault != 0 {
		C.kprintf(c'devcore: slot %.*s: power fault\n', i32(slot.label.len), slot.label.str)
	} else if slot.port.secondary_bus() == 0 {
		C.kprintf(c'devcore: slot %.*s: its port was given no bus\n', i32(slot.label.len), slot.label.str)
	} else {
		// A card may answer "try again" for a second after its reset.
		sleep_until(card_answers, voidptr(slot), second, 20)
		added = scan_place(slot.port.secondary_bus(), 0, slot.port)
	}
	if added == 0 {
		// Whatever is in the slot is not a card this machine can use.
		// Without power it can at least be pulled.
		C.kprintf(c'devcore: slot %.*s: nothing usable answered; power off\n', i32(slot.label.len),
			slot.label.str)
		slot.failures++
		slot.set_power(false)
		slot.power_light(pci.light_off)
		slot.attention_light(pci.light_on)
		slot.state = .off
		return
	}
	slot.arrivals++
	slot.power_light(pci.light_on)
	slot.attention_light(pci.light_off)
	slot.state = .occupied
	C.kprintf(c'devcore: slot %.*s: %lld function(s) added\n', i32(slot.label.len), slot.label.str,
		i64(added))
}

// The card goes out of use. `present` says whether it is still in the slot.
fn (mut slot Slot) take_out(present bool) {
	gone := slot.empty_bus(present)
	slot.set_power(false)
	if present {
		sleep_ms(slot_drain_ms)
	}
	slot.power_light(pci.light_off)
	C.kprintf(c'devcore: slot %.*s: %lld function(s) removed%s\n', i32(slot.label.len), slot.label.str,
		i64(gone), if present { c'' } else { c' (the card was pulled)' })
	slot.departures++
	// A card taken out of use and still in the slot waits there, off, for
	// the button, for /sys, or to be pulled. The port is asked again: taking
	// the power away is what lets some slots release their card. The state
	// is the last thing to change, after the line above is out: a program
	// waiting for it shares the console.
	slot.state = if slot.status() & pci.status_present != 0 { SlotState.off } else { SlotState.empty }
}

// What /sys last asked of the slot, taken so that it is acted on once.
fn (mut slot Slot) take_request() u32 {
	if katomic.cas(mut &slot.want, slot_want_on, u32(0)) {
		return slot_want_on
	}
	if katomic.cas(mut &slot.want, slot_want_off, u32(0)) {
		return slot_want_off
	}
	return 0
}

// Look at one port and act on what it shows.
fn (mut slot Slot) service() {
	status := slot.status()
	if status == 0xffff {
		// The port itself does not answer.
		return
	}
	events := status & pci.status_events
	if events != 0 {
		slot.acknowledge(events)
	}
	present := status & pci.status_present != 0
	pressed := events & pci.status_button_pressed != 0
	want := slot.take_request()
	match slot.state {
		.empty {
			if present {
				slot.bring_in()
			}
		}
		.off {
			if !present {
				slot.attention_light(pci.light_off)
				slot.state = .empty
			} else if pressed || want == slot_want_on {
				slot.bring_in()
			}
		}
		.occupied {
			if !present {
				slot.take_out(false)
			} else if want == slot_want_off {
				slot.take_out(true)
			} else if pressed {
				slot.state = .leaving
				slot.leave_at = deadline(slot_leave_ns)
				slot.power_light(pci.light_blink)
				C.kprintf(c'devcore: slot %.*s: button pressed; the card goes out of use in 5 s\n',
					i32(slot.label.len), slot.label.str)
			}
		}
		.leaving {
			if !present {
				slot.take_out(false)
			} else if pressed {
				slot.state = .occupied
				slot.power_light(pci.light_on)
				C.kprintf(c'devcore: slot %.*s: button pressed again; the card stays\n', i32(slot.label.len),
					slot.label.str)
			} else if want == slot_want_off || slot.leave_at.expired() {
				slot.take_out(true)
			}
		}
	}
}

// Try every address on a bus.
fn scan_bus(bus u8, bridge &pci.PCIDevice) int {
	mut added := 0
	for place := u8(0); place < 32; place++ {
		added += scan_place(bus, place, bridge)
	}
	return added
}

// Whether the bus is behind a slot whose card is not in use: one taken out
// of use and not yet pulled, which a rescan must not bring back.
fn bus_is_resting(bus u8) bool {
	for i in 0 .. devcore_slot_count {
		slot := &devcore_slots[i]
		if slot.port.secondary_bus() == bus && (slot.state == .off || slot.state == .empty) {
			return true
		}
	}
	return false
}

fn rescan_buses() {
	mut added := scan_bus(0, unsafe { nil })
	// The list grows while it is walked when a bridge is found; what is
	// behind a bridge that has just arrived is not looked for.
	known := scanned_devices.len
	for i in 0 .. known {
		p := scanned_devices[i]
		if !p.present() || p.header_type != 1 {
			continue
		}
		secondary := p.secondary_bus()
		if secondary == 0 || bus_is_resting(secondary) {
			continue
		}
		added += scan_bus(secondary, p)
	}
	devcore_rescans++
	C.kprintf(c'devcore: PCI rescan found %lld new function(s)\n', i64(added))
}

// ── What firmware asks for ──────────────────────────────────────────────────

// One request about the device at a place on a bus: look for it, or let go
// of it and say when that is done.
struct PlaceRequest {
mut:
	eject   bool
	bus     u8
	place   u8
	done    fn (context voidptr) = unsafe { nil }
	context voidptr
}

const max_place_requests = 16

__global (
	devcore_place_requests      [max_place_requests]PlaceRequest
	devcore_place_request_count int
	devcore_place_lock          klock.Lock
)

fn queue_place(request PlaceRequest) bool {
	devcore_place_lock.acquire()
	if !devcore_hotplug_alive || devcore_place_request_count >= max_place_requests {
		devcore_place_lock.release()
		return false
	}
	devcore_place_requests[devcore_place_request_count] = request
	devcore_place_request_count++
	devcore_place_lock.release()
	event.trigger(mut devcore_hotplug_event, false)
	return true
}

// Firmware says a device may have appeared at this place: look, and add what
// is found. False if the request could not be taken.
pub fn pci_arrival(bus u8, place u8) bool {
	return queue_place(PlaceRequest{
		bus:   bus
		place: place
	})
}

// Firmware wants the device at this place back. Its functions are taken from
// their drivers and removed, and then `done(context)` is called, on the
// hotplug thread, for the caller to tell firmware the device can go. False
// if the request could not be taken; `done` is then never called.
pub fn pci_eject(bus u8, place u8, done fn (context voidptr), context voidptr) bool {
	return queue_place(PlaceRequest{
		eject:   true
		bus:     bus
		place:   place
		done:    done
		context: context
	})
}

// The bridge a bus hangs off; nil for the root bus, or if nobody knows.
fn bridge_of(bus u8) &pci.PCIDevice {
	if bus == 0 {
		return unsafe { nil }
	}
	for p in scanned_devices {
		if p.present() && p.header_type == 1 && p.secondary_bus() == bus {
			return unsafe { p }
		}
	}
	return unsafe { nil }
}

// Remove every function of the device at a place. Returns how many went.
fn empty_place(bus u8, place u8) int {
	mut gone := 0
	for {
		mut record := &pci.PCIDevice(unsafe { nil })
		for candidate in scanned_devices {
			if candidate.bus == bus && candidate.slot == place && candidate.present() {
				record = unsafe { candidate }
				break
			}
		}
		if record == unsafe { nil } {
			break
		}
		drop_function(mut record, true)
		gone++
	}
	return gone
}

fn serve_places() {
	for {
		devcore_place_lock.acquire()
		if devcore_place_request_count == 0 {
			devcore_place_lock.release()
			return
		}
		request := devcore_place_requests[0]
		for i := 1; i < devcore_place_request_count; i++ {
			devcore_place_requests[i - 1] = devcore_place_requests[i]
		}
		devcore_place_request_count--
		devcore_place_lock.release()
		if request.eject {
			gone := empty_place(request.bus, request.place)
			C.kprintf(c'devcore: %02llx:%02llx asked back by firmware: %lld function(s) removed\n',
				u64(request.bus), u64(request.place), i64(gone))
			if request.done != unsafe { nil } {
				request.done(request.context)
			}
			continue
		}
		// A device firmware has only just let onto the bus may need a
		// moment before it answers.
		for _ in 0 .. 50 {
			if pci.function_answers(request.bus, request.place, 0) {
				break
			}
			sleep_ms(20)
		}
		added := scan_place(request.bus, request.place, bridge_of(request.bus))
		C.kprintf(c'devcore: %02llx:%02llx announced by firmware: %lld function(s) added\n',
			u64(request.bus), u64(request.place), i64(added))
	}
}

fn hotplug_thread() {
	for {
		generation := event.generation(mut devcore_hotplug_event)
		if katomic.cas(mut &devcore_rescan_wanted, u32(1), u32(0)) {
			rescan_buses()
		}
		serve_places()
		for i in 0 .. devcore_slot_count {
			mut slot := &devcore_slots[i]
			slot.service()
		}
		wait_event(mut devcore_hotplug_event, generation, if devcore_slot_count > 0 {
			slot_poll_ms
		} else {
			idle_wait_ms
		})
	}
}

// What the recovery worker calls for a rescan: pass it on.
fn ask_for_rescan() {
	katomic.store(mut &devcore_rescan_wanted, u32(1))
	event.trigger(mut devcore_hotplug_event, false)
}

// A slot's name in /sys: its number, and for a second slot with the same
// number -- firmware does not always number them -- "-1", "-2" as Linux
// names them.
fn slot_label(number u32, index int) string {
	mut same := 0
	for i in 0 .. index {
		if devcore_slots[i].number == number {
			same++
		}
	}
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(16) }
	text.add_unsigned(u64(number))
	if same > 0 {
		text.add_byte(`-`)
		text.add_unsigned(u64(same))
	}
	return text.str()
}

// Find the ports with slots and start watching them. Called once, after the
// boot scan has been handed to the core and its worker is running. `own`
// says whether the ports are this system's to run: false where firmware
// keeps them, or where nothing is known about what a port's slot power
// feeds. `vinix.pci_hotplug=1` and `=0` override it either way; the rescan,
// and what firmware asks for, work regardless.
pub fn start_pci_hotplug(own bool) {
	if devcore_hotplug_alive {
		return
	}
	devcore_hotplug_alive = true
	if boot_flag('vinix.pci_hotplug=', own) {
		for p in scanned_devices {
			if devcore_slot_count >= max_slots || !p.present() || p.header_type != 1 {
				continue
			}
			express := p.capability(pci.capability_express)
			if express == 0 {
				continue
			}
			flags := p.read[u16](u32(express) + pci.express_flags)
			kind := (flags >> 4) & 0xf
			if flags & pci.express_flag_slot == 0
				|| (kind != pci.express_type_root_port && kind != pci.express_type_downstream) {
				continue
			}
			capabilities := p.read[u32](u32(express) + pci.express_slot_capabilities)
			if capabilities & pci.slot_hotplug == 0 {
				continue
			}
			mut slot := &devcore_slots[devcore_slot_count]
			slot.port = unsafe { p }
			slot.express = u32(express)
			slot.capabilities = capabilities
			slot.number = capabilities >> 19
			// Kept for as long as the machine runs, like the slot.
			slot.label = slot_label(slot.number, devcore_slot_count)
			// What firmware found in a slot is in use already; anything
			// else the first look at the port sorts out.
			slot.state = .empty
			secondary := p.secondary_bus()
			for other in scanned_devices {
				if secondary != 0 && other.bus == secondary && other.present() {
					slot.state = .occupied
					break
				}
			}
			devcore_slot_count++
			C.kprintf(c'devcore: hot-plug slot %.*s behind %llx:%llx.%llx, %.*s\n', i32(slot.label.len),
				slot.label.str, u64(p.bus), u64(p.slot), u64(p.function),
				i32(slot_state_name(slot.state).len), slot_state_name(slot.state).str)
		}
	}
	register_rescan(.pci, ask_for_rescan)
	sched.new_kernel_thread(voidptr(hotplug_thread), unsafe { nil }, true)
	publish_slots()
}

// ── /sys/bus/pci/slots ──────────────────────────────────────────────────────

fn show_slot_address(context voidptr, mut text lib.Text) {
	slot := unsafe { &Slot(context) }
	text.add('0000:')
	text.add_radix(u64(slot.port.secondary_bus()), 16, 2)
	text.add(':00\n')
}

fn show_slot_adapter(context voidptr, mut text lib.Text) {
	slot := unsafe { &Slot(context) }
	status := slot.status()
	text.add(if status != 0xffff && status & pci.status_present != 0 { '1\n' } else { '0\n' })
}

fn show_slot_power(context voidptr, mut text lib.Text) {
	slot := unsafe { &Slot(context) }
	text.add(if slot.state == .occupied || slot.state == .leaving { '1\n' } else { '0\n' })
}

// The request is carried out by the slot's thread, within its next look at
// the port; `state` and `power` show when it has been.
fn store_slot_power(context voidptr, data &u8, length u64) u64 {
	mut slot := unsafe { &Slot(context) }
	value := fs.sysfs_unsigned(data, length) or { return errno.einval }
	if value > 1 {
		return errno.einval
	}
	katomic.store(mut &slot.want, if value == 1 { slot_want_on } else { slot_want_off })
	event.trigger(mut devcore_hotplug_event, false)
	return 0
}

fn show_slot_state(context voidptr, mut text lib.Text) {
	slot := unsafe { &Slot(context) }
	text.add(slot_state_name(slot.state))
	text.add_byte(`\n`)
}

fn show_slot_events(context voidptr, mut text lib.Text) {
	slot := unsafe { &Slot(context) }
	text.add('arrivals: ')
	text.add_unsigned(slot.arrivals)
	text.add('\ndepartures: ')
	text.add_unsigned(slot.departures)
	text.add('\nfailures: ')
	text.add_unsigned(slot.failures)
	text.add_byte(`\n`)
}

fn slot_file(slot &Slot, name string, mode u32, show fs.SysfsShow, store fs.SysfsStore) {
	mut path := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *path = lib.new_text(64) }
	path.add('bus/pci/slots/')
	path.add(slot.label)
	path.add_byte(`/`)
	path.add(name)
	full := path.str()
	fs.sysfs_attribute(full, mode, show, store, voidptr(slot))
	unsafe { full.free() }
}

// The slots' files. Called when the slots are found and again when /sys is
// mounted, whichever comes last.
fn publish_slots() {
	if !devcore_published || !devcore_hotplug_alive {
		return
	}
	fs.sysfs_directory('bus/pci/slots')
	for i in 0 .. devcore_slot_count {
		slot := &devcore_slots[i]
		slot_file(slot, 'address', 0o444, show_slot_address, unsafe { nil })
		slot_file(slot, 'adapter', 0o444, show_slot_adapter, unsafe { nil })
		slot_file(slot, 'power', 0o644, show_slot_power, store_slot_power)
		slot_file(slot, 'state', 0o444, show_slot_state, unsafe { nil })
		slot_file(slot, 'events', 0o444, show_slot_events, unsafe { nil })
	}
}
