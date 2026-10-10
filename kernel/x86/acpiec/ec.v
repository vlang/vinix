// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The ACPI embedded controller of a PC: finding it, answering for its
// address space, and hearing its events.
//
// On a laptop the battery, the charger, the lid, the thermal zones and the
// hotkeys are all behind the controller. Firmware's methods for them (_BST,
// _PSR, _LID, _TMP) read fields of an EmbeddedControl operation region,
// which the interpreter cannot reach by itself, and the controller says that
// something changed by raising a general purpose event and then naming, when
// asked, the method to run (_Qxx). Without this driver every such method
// fails and no such event arrives. The protocol itself is in protocol.v;
// this file is the machine around it.
//
// Finding it, in three steps, each where kmain puts it:
//
//   early()     before the namespace is loaded. If firmware has an ECDT,
//               the table whose purpose is to describe the controller before
//               the namespace can, its handler goes on the root now: tables
//               that touch the controller while they load, and the _INI
//               methods after them, then find it there.
//   discover()  after the namespace is initialised. The PNP0C09 device gives
//               the ports (_CRS), the event (_GPE, a number or a package
//               naming a block device), whether the global lock is needed
//               (_GLK) and the device's _UID; a machine with no ECDT gets
//               its handler here. Then _REG runs, which is how firmware
//               learns that the region may be used. This is Linux's order
//               and Windows': with no ECDT, _INI runs before the controller
//               is there, and firmware is written to expect that. It is
//               before the general purpose events are switched on, whose
//               methods use the controller too.
//   start()     once ACPI's event threads run. The controller becomes a
//               device, its event gets a handler, and whatever it has been
//               waiting to say is asked for.
//
// The handler is installed on the root of the namespace, not on the device:
// firmware does declare EmbeddedControl regions outside the device's scope,
// which is why Linux moved its handler there. A second PNP0C09 device is not
// driven; its own regions get a handler that refuses them, so that they do
// not reach the first controller's ports.
//
// Locking. An exchange takes milliseconds and is entered from the boot
// thread, from the event work thread (a query, and the methods it runs) and
// from system calls (a read in /sys evaluates _BST). It is never entered
// from an interrupt. What keeps exchanges apart is therefore a mutex that
// sleeps, of the kind uACPI's own are (acpisync), which also works before
// the scheduler does. It is the innermost lock: it is held across port I/O
// and waiting and nothing else, and released before any method is run, so a
// method the controller asked for can use the controller.
//
// Where _GLK is 1 the ACPI global lock is taken first, outside the mutex --
// unless the calling thread has it already, as it does in a field declared
// Lock (uacpi/globallock.v). uACPI calls a region handler with its own
// operation region lock held, so a thread in here waiting for the global
// lock can face one that has the global lock and wants that; the wait for
// the global lock is therefore bounded, and an access that runs into it
// fails instead.
//
// Events. The general purpose event's handler runs on the thread the SCI
// wakes and does one thing: it queues a query on ACPI's work queue, where
// Notify handlers run too. The work asks the controller for events until it
// has none, runs _Qxx for each with nothing held, and stops at a limit. One
// more thing can queue it: an exchange that sees the event bit up. And where
// the event cannot be used -- no _GPE, one in a block this kernel does not
// drive, or a line that turned out to be stuck -- a thread looks at the
// event bit four times a second instead.
//
// A controller that stops answering is given up on by the protocol, and
// reported to the device core, which marks the device failed; writing 1 to
// the device's `reset` file asks it one question, and if it answers it is in
// use again.
//
// Sleep. Suspend to idle leaves the controller alone: its event stays on,
// the threads above keep running, and a lid that opens or a battery that
// runs out is attributed by the driver that hears the Notify. What the
// controller itself reports is counted under its own wake source, which is
// off unless asked for. With wakeup disabled for the device its event is
// switched off for the sleep and whatever it raised is asked for on resume.
//
// Boot options, in vinix.ec= as a comma-separated list:
//
//	off        do not drive the controller
//	clear      on start and on resume, query the controller until it says it
//	           has nothing, whatever its event bit says: for controllers that
//	           stop raising the bit once their queue is full (Linux's
//	           EC_FLAGS_CLEAR_ON_RESUME, which it sets for Samsung laptops)
//	dsdt-gpe   where the ECDT and _GPE disagree, believe _GPE (Linux's
//	           EC_FLAGS_TRUST_DSDT_GPE)
@[has_globals]
module acpiec

import acpi
import acpisync
import devcore
import event
import event.eventstruct
import katomic
import klock
import sched
import uacpi
import wakesrc
import x86.kio

// Where things are in an ECDT, after the 36 bytes every table starts with:
// two generic addresses of twelve bytes -- command, then data -- each with
// its address space in the first byte and its address in the last eight,
// the _UID, the event's number, and the device's path.
const ecdt_command = 36
const ecdt_data = 48
const ecdt_uid = 60
const ecdt_gpe = 64
const ecdt_path = 65
// A generic address's code for I/O ports.
const gas_io = u8(1)

// How long an exchange waits for another thread to let go of the global
// lock: Linux's ACPI_EC_UDELAY_GLK.
const global_lock_ms = u16(1000)
// How often the event bit is looked at where no event can be used.
const poll_ms = u64(250)

const max_candidates = 4

struct Candidate {
mut:
	node      uacpi.Node
	gpe_block uacpi.Node
	found     Description
}

struct Wiring {
mut:
	set_up   bool
	disabled bool
	// Options.
	clear            bool
	trust_device_gpe bool

	// What firmware said, and what was made of it.
	table        Description
	table_path   [64]u8
	candidates   [max_candidates]Candidate
	ports        uacpi.IoPorts
	candidate_n  int
	portless     int
	present      bool
	source       Source
	data_port    u16
	command_port u16
	has_gpe      bool
	gpe          u16
	// The device of the block the event is in; nil for the FADT's blocks.
	gpe_block   uacpi.Node
	node        uacpi.Node
	uid         u64
	global_lock bool
	// Other PNP0C09 devices, which are not driven.
	others int

	handler_installed bool
	early             bool

	// What keeps exchanges apart, and what is known only while it is held:
	// whether this exchange took the global lock, and uACPI's number for it.
	mutex         voidptr
	lock_taken    bool
	lock_sequence u32
	lock_failures u64

	started bool
	// Events may be asked for; and are being kept for later.
	events_on u32
	held      u32
	// A query is queued or running; and it is to ask whatever the bit says.
	pending       u32
	clear_pending u32
	gpe_installed bool
	gpe_suspended bool
	// The event's line was stuck and has been left off.
	gpe_parked u32
	gpe_lock   klock.Lock
	poll_wake  eventstruct.Event

	device &devcore.Device = unsafe { nil }
	// The controller's failure has been announced, and the device core has
	// not yet been told what to do about it.
	reported u32
	fresh    u32

	methods         u64
	methods_missing u64
	methods_failed  u64
	// Queries that could not be queued.
	dropped      u64
	sleep_events u64
}

__global (
	acpiec_controller Controller
	acpiec_wiring     Wiring
)

// ── The ports ───────────────────────────────────────────────────────────────

fn ec_port_read(_ voidptr, command bool) u8 {
	return kio.port_in[u8](if command { acpiec_wiring.command_port } else { acpiec_wiring.data_port })
}

fn ec_port_write(_ voidptr, command bool, value u8) {
	kio.port_out[u8](if command { acpiec_wiring.command_port } else { acpiec_wiring.data_port },
		value)
}

fn ec_now(_ voidptr) u64 {
	return devcore.now_ns()
}

// The short waits spin, since a controller that works is done in less time
// than giving up the CPU takes; the long ones sleep where there is a
// scheduler to sleep in.
fn ec_pause(_ voidptr, ns u64) {
	if ns < devcore.millisecond {
		devcore.stall(ns)
	} else {
		devcore.sleep_ms(ns / devcore.millisecond)
	}
}

// ── The lock ────────────────────────────────────────────────────────────────

fn ec_enter(_ voidptr) bool {
	mut taken := false
	mut sequence := u32(0)
	if acpiec_wiring.global_lock && !uacpi.global_lock_held() {
		taken, sequence = uacpi.acquire_global_lock(global_lock_ms)
		if !taken {
			katomic.inc(mut &acpiec_wiring.lock_failures)
			return false
		}
	}
	if acpisync.wait(acpiec_wiring.mutex, 0xffff) != 0 {
		if taken {
			uacpi.release_global_lock(sequence)
		}
		katomic.inc(mut &acpiec_wiring.lock_failures)
		return false
	}
	acpiec_wiring.lock_taken = taken
	acpiec_wiring.lock_sequence = sequence
	return true
}

fn ec_leave(_ voidptr) {
	// Both are the protocol's, and only safe to read with the mutex held.
	hint := acpiec_controller.take_hint()
	failed := acpiec_controller.failed
	taken := acpiec_wiring.lock_taken
	sequence := acpiec_wiring.lock_sequence
	acpiec_wiring.lock_taken = false
	acpisync.signal(acpiec_wiring.mutex)
	if taken && !uacpi.release_global_lock(sequence) {
		katomic.inc(mut &acpiec_wiring.lock_failures)
	}
	if failed {
		announce_failure()
	} else if hint {
		submit_query()
	}
}

// Say once that the controller has been given up on, and hand it to the
// device core's recovery.
fn announce_failure() {
	if !katomic.cas(mut &acpiec_wiring.reported, u32(0), u32(1)) {
		return
	}
	katomic.store(mut &acpiec_wiring.fresh, u32(1))
	reason := outcome_name(acpiec_controller.failure)
	C.kprintf(c'acpiec: the controller at ports 0x%llx/0x%llx does not answer (%.*s); given up on\n',
		u64(acpiec_wiring.data_port), u64(acpiec_wiring.command_port), i32(reason.len),
		reason.str)
	if acpiec_wiring.device != unsafe { nil } {
		mut dev := acpiec_wiring.device
		devcore.report_failure(mut dev, 'no answer')
	}
}

// ── Setting up ──────────────────────────────────────────────────────────────

// Whether the comma-separated `list` has `word` in it.
fn listed(list string, word string) bool {
	mut from := 0
	for from <= list.len {
		mut end := from
		for end < list.len && list[end] != `,` {
			end++
		}
		if end - from == word.len {
			mut same := true
			for i in 0 .. word.len {
				if list[from + i] != word[i] {
					same = false
					break
				}
			}
			if same {
				return true
			}
		}
		from = end + 1
	}
	return false
}

fn setup() {
	if acpiec_wiring.set_up {
		return
	}
	acpiec_wiring.set_up = true
	if options := devcore.boot_option('vinix.ec=') {
		acpiec_wiring.disabled = listed(options, 'off')
		acpiec_wiring.clear = listed(options, 'clear')
		acpiec_wiring.trust_device_gpe = listed(options, 'dsdt-gpe')
	}
	if acpiec_wiring.disabled {
		return
	}
	acpiec_wiring.mutex = acpisync.create(true)
	if acpiec_wiring.mutex == unsafe { nil } {
		acpiec_wiring.disabled = true
		return
	}
	acpiec_controller.port.context = unsafe { nil }
	acpiec_controller.port.read = ec_port_read
	acpiec_controller.port.write = ec_port_write
	acpiec_controller.port.now = ec_now
	acpiec_controller.port.pause = ec_pause
	acpiec_controller.port.enter = ec_enter
	acpiec_controller.port.leave = ec_leave
	$if acpiec_selftest ? {
		selftest_take_ports()
	}
}

fn table_u32(base &u8, offset int) u64 {
	mut value := u64(0)
	for i in 0 .. 4 {
		value |= u64(unsafe { base[offset + i] }) << (u32(i) * 8)
	}
	return value
}

fn table_u64(base &u8, offset int) u64 {
	return table_u32(base, offset) | (table_u32(base, offset + 4) << 32)
}

// What an ECDT says. Not valid when it is too short, names anything but I/O
// ports, or names no device: Linux ignores a table with an empty path, which
// some firmware ships together with other nonsense in it.
fn read_table(table voidptr) Description {
	base := unsafe { &u8(table) }
	length := int(table_u32(base, 4))
	if length <= ecdt_path || unsafe { base[ecdt_path] } == 0 {
		return Description{}
	}
	if unsafe { base[ecdt_command] } != gas_io || unsafe { base[ecdt_data] } != gas_io {
		return Description{}
	}
	mut n := 0
	for ecdt_path + n < length && n < 63 && unsafe { base[ecdt_path + n] } != 0 {
		acpiec_wiring.table_path[n] = unsafe { base[ecdt_path + n] }
		n++
	}
	acpiec_wiring.table_path[n] = 0
	acpiec_wiring.uid = table_u32(base, ecdt_uid)
	return Description{
		valid:   true
		data:    table_u64(base, ecdt_data + 4)
		command: table_u64(base, ecdt_command + 4)
		has_gpe: true
		gpe:     u64(unsafe { base[ecdt_gpe] })
	}
}

fn adopt(choice Choice) {
	acpiec_wiring.source = choice.source
	acpiec_wiring.data_port = u16(choice.found.data)
	acpiec_wiring.command_port = u16(choice.found.command)
	acpiec_wiring.has_gpe = choice.found.has_gpe && choice.found.gpe <= 0xffff
	acpiec_wiring.gpe = u16(choice.found.gpe)
	acpiec_wiring.present = true
}

fn status_of(outcome Outcome) uacpi.UACPIStatus {
	return match outcome {
		.ok { uacpi.UACPIStatus.ok }
		.invalid { uacpi.UACPIStatus.invalid_argument }
		.busy { uacpi.UACPIStatus.timeout }
		else { uacpi.UACPIStatus.hardware_timeout }
	}
}

// uACPI's call for a field of an EmbeddedControl region.
fn region_handler(op u32, data voidptr) uacpi.UACPIStatus {
	if op == uacpi.region_attach || op == uacpi.region_detach {
		return .ok
	}
	if data == unsafe { nil } || (op != uacpi.region_read && op != uacpi.region_write) {
		return .invalid_argument
	}
	mut access := unsafe { &uacpi.RegionAccess(data) }
	if op == uacpi.region_read {
		outcome, value := acpiec_controller.region_read(access.offset, access.byte_width)
		access.value = value
		return status_of(outcome)
	}
	outcome := acpiec_controller.region_write(access.offset, access.byte_width, access.value)
	return status_of(outcome)
}

// For the regions of a controller that is not driven.
fn refusing_handler(op u32, _data voidptr) uacpi.UACPIStatus {
	if op == uacpi.region_attach || op == uacpi.region_detach {
		return .ok
	}
	return .no_handler
}

fn install_handler() bool {
	if acpiec_wiring.handler_installed {
		return true
	}
	status := uacpi.install_region_handler(uacpi.root(), uacpi.space_embedded_controller,
		region_handler, unsafe { nil })
	if status != .ok {
		C.kprintf(c'acpiec: no handler for the controller region: %s\n', C.uacpi_status_to_string(status))
		return false
	}
	acpiec_wiring.handler_installed = true
	return true
}

// Before the namespace is loaded: the controller an ECDT describes.
pub fn early() {
	setup()
	if acpiec_wiring.disabled {
		return
	}
	table := acpi.find_sdt('ECDT', 0) or { return }
	description := read_table(table)
	if !usable(description) {
		print('acpiec: the ECDT describes no controller that can be used; ignored\n')
		return
	}
	acpiec_wiring.table = description
	adopt(Choice{
		source: .table
		found:  description
	})
	if install_handler() {
		acpiec_wiring.early = true
	}
}

// One PNP0C09 device: its ports and its event.
fn controller_found(_ voidptr, node uacpi.Node) {
	// Not a local: one handed to the interpreter would be moved to the heap
	// and left there.
	mut ports := unsafe { &acpiec_wiring.ports }
	if !uacpi.io_ports(node, mut ports) || ports.count < 2 {
		// A controller reached some other way, as on hardware-reduced
		// machines, where it is on an I2C bus or in memory.
		acpiec_wiring.portless++
		return
	}
	if acpiec_wiring.candidate_n >= max_candidates {
		return
	}
	mut candidate := unsafe { &acpiec_wiring.candidates[acpiec_wiring.candidate_n] }
	acpiec_wiring.candidate_n++
	candidate.node = node
	candidate.gpe_block = unsafe { nil }
	// The data port is listed first and the command port second.
	candidate.found = Description{
		valid:   true
		data:    u64(ports.port[0])
		command: u64(ports.port[1])
	}
	if number := uacpi.evaluate_integer(node, '_GPE') {
		candidate.found.has_gpe = true
		candidate.found.gpe = number
		return
	}
	// The other form: the device of a block of events, and a number in it.
	mut package := uacpi.evaluate_package(node, '_GPE') or { return }
	if package.len() == 2 {
		if block := package.node(0, node) {
			if number := package.integer(1) {
				candidate.gpe_block = block
				candidate.found.has_gpe = true
				candidate.found.gpe = number
			}
		}
	}
	package.release()
}

// After the namespace is initialised: the controller's device, and _REG.
pub fn discover() {
	setup()
	if acpiec_wiring.disabled {
		return
	}
	uacpi.for_each_device('PNP0C09', controller_found, unsafe { nil })
	// The device the table means is the one at the table's ports.
	mut chosen := -1
	for i in 0 .. acpiec_wiring.candidate_n {
		found := acpiec_wiring.candidates[i].found
		if usable(acpiec_wiring.table) && found.data == acpiec_wiring.table.data
			&& found.command == acpiec_wiring.table.command {
			chosen = i
			break
		}
	}
	if chosen < 0 && acpiec_wiring.candidate_n > 0 {
		chosen = 0
	}
	mut device := Description{}
	if chosen >= 0 {
		device = acpiec_wiring.candidates[chosen].found
	}
	choice := choose(acpiec_wiring.table, device, acpiec_wiring.trust_device_gpe)
	if choice.source == .none {
		if acpiec_wiring.portless != 0 || acpiec_wiring.candidate_n != 0 {
			print('acpiec: firmware describes a controller this driver cannot reach; not driven\n')
		}
		return
	}
	if choice.conflict {
		C.kprintf(c'acpiec: the ECDT says ports 0x%llx/0x%llx and the namespace 0x%llx/0x%llx; using the namespace\n',
			acpiec_wiring.table.data, acpiec_wiring.table.command, device.data, device.command)
	}
	adopt(choice)
	if chosen >= 0 {
		acpiec_wiring.node = acpiec_wiring.candidates[chosen].node
		// The block the event is in comes with the number, from whichever
		// of the two descriptions the number was taken.
		if !usable(acpiec_wiring.table) || acpiec_wiring.gpe == u16(device.gpe) {
			acpiec_wiring.gpe_block = acpiec_wiring.candidates[chosen].gpe_block
		}
	} else if node := uacpi.find_node(&acpiec_wiring.table_path[0]) {
		acpiec_wiring.node = node
	}
	if acpiec_wiring.node != unsafe { nil } {
		if needed := uacpi.evaluate_integer(acpiec_wiring.node, '_GLK') {
			if needed == 1 {
				if uacpi.learn_global_lock() {
					acpiec_wiring.global_lock = true
				} else {
					print('acpiec: _GLK asks for the global lock, which cannot be taken; going without\n')
				}
			}
		}
		if uid := uacpi.evaluate_integer(acpiec_wiring.node, '_UID') {
			acpiec_wiring.uid = uid
		}
	}
	// Regions of the controllers that are not driven must not come to this
	// one's ports.
	for i in 0 .. acpiec_wiring.candidate_n {
		if i == chosen {
			continue
		}
		acpiec_wiring.others++
		uacpi.install_region_handler(acpiec_wiring.candidates[i].node, uacpi.space_embedded_controller,
			refusing_handler, unsafe { nil })
	}
	if acpiec_wiring.others != 0 {
		C.kprintf(c'acpiec: %lld more embedded controllers are not driven\n', i64(acpiec_wiring.others))
	}
	if acpiec_wiring.early {
		// Installed before there were methods to run: _REG is still owed.
		uacpi.connect_regions(uacpi.root(), uacpi.space_embedded_controller)
	} else {
		// Installing it now runs _REG.
		install_handler()
	}
}

// ── Events ──────────────────────────────────────────────────────────────────

// Run the method firmware gives event `number`. Called with nothing held.
fn run_method(_ voidptr, number u8) {
	if acpiec_wiring.node == unsafe { nil } {
		katomic.inc(mut &acpiec_wiring.methods_missing)
		return
	}
	mut name := [8]u8{}
	for i in 0 .. 4 {
		name[i] = query_method_char(number, u32(i))
	}
	status := uacpi.execute_by_name(acpiec_wiring.node, &name[0])
	if status == .ok {
		katomic.inc(mut &acpiec_wiring.methods)
	} else if status == .not_found {
		katomic.inc(mut &acpiec_wiring.methods_missing)
	} else {
		katomic.inc(mut &acpiec_wiring.methods_failed)
	}
}

// Queued behind the Notify handlers of the methods a query ran, so that a
// lid or a battery has claimed the wake-up before the controller does.
fn attribute_work(_ voidptr) {
	wakesrc.report(.ec)
}

// The work a query is: on ACPI's work thread.
fn query_work(_ voidptr) {
	blind := katomic.cas(mut &acpiec_wiring.clear_pending, u32(1), u32(0))
	limit := if blind { clear_limit } else { drain_limit }
	report := acpiec_controller.drain(blind, limit, run_method, unsafe { nil })
	if report.events != 0 {
		acpiec_wiring.gpe_lock.acquire()
		acpiec_controller.calm()
		acpiec_wiring.gpe_lock.release()
		if wakesrc.sleeping() {
			katomic.inc(mut &acpiec_wiring.sleep_events)
			if acpiec_wiring.device != unsafe { nil } {
				mut dev := acpiec_wiring.device
				katomic.inc(mut &dev.wakeups)
			}
		}
		uacpi.defer_work(attribute_work, unsafe { nil })
	}
	if report.limited {
		C.kprintf(c'acpiec: the controller still had events after %llu; left until it raises its line again\n',
			u64(report.events))
	}
	katomic.store(mut &acpiec_wiring.pending, u32(0))
	// An event raised while that ran found the work still marked pending and
	// queued nothing. If the bit is up it goes to the back of the queue,
	// behind the Notify handlers the methods queued.
	if !report.error && !report.limited && acpiec_controller.event_waiting() {
		submit_query()
	}
}

// Have the controller asked for its events, unless it already is being.
// From any thread.
fn submit_query() {
	if katomic.load(&acpiec_wiring.events_on) == 0 || katomic.load(&acpiec_wiring.held) != 0 {
		return
	}
	if !katomic.cas(mut &acpiec_wiring.pending, u32(0), u32(1)) {
		return
	}
	if !uacpi.defer_work(query_work, unsafe { nil }) {
		katomic.store(mut &acpiec_wiring.pending, u32(0))
		katomic.inc(mut &acpiec_wiring.dropped)
	}
}

// The controller's general purpose event was raised. Called by uACPI from
// the thread the SCI wakes, with the event switched off and cleared; what is
// returned says whether to switch it on again. A self-test kernel also calls
// this itself.
fn gpe_raised() u32 {
	acpiec_wiring.gpe_lock.acquire()
	working := acpiec_controller.note_gpe(devcore.now_ns())
	acpiec_wiring.gpe_lock.release()
	submit_query()
	if !working {
		// Raised over and over with nothing behind it. Left off, the event
		// bit is looked at by the polling thread instead.
		if katomic.cas(mut &acpiec_wiring.gpe_parked, u32(0), u32(1)) {
			print('acpiec: the event line is stuck; switched off, polling instead\n')
			event.trigger(mut acpiec_wiring.poll_wake, false)
		}
		return uacpi.gpe_handled
	}
	return uacpi.gpe_handled | uacpi.gpe_reenable
}

fn gpe_handler(_context voidptr, _device voidptr, _index u16) u32 {
	return gpe_raised()
}

fn polling() bool {
	return katomic.load(&acpiec_wiring.events_on) != 0 && (!acpiec_wiring.gpe_installed
		|| katomic.load(&acpiec_wiring.gpe_parked) != 0)
}

// Looks at the event bit where no event says when to: asleep unless that is
// so.
fn poll_thread() {
	for {
		generation := event.generation(mut acpiec_wiring.poll_wake)
		if !polling() {
			event.await_one_from_generation(mut acpiec_wiring.poll_wake, true, generation) or {}
			continue
		}
		if acpiec_controller.event_waiting() {
			submit_query()
		}
		devcore.wait_event(mut acpiec_wiring.poll_wake, generation, poll_ms)
	}
}

// Ask for whatever the controller raised while nobody listened: it raises
// its line when the event bit goes up, and will not raise it again for a
// bit that is up already.
fn catch_up() {
	if acpiec_controller.failed {
		return
	}
	if acpiec_wiring.clear {
		katomic.store(mut &acpiec_wiring.clear_pending, u32(1))
		submit_query()
	} else if acpiec_controller.event_waiting() {
		submit_query()
	}
}

// ── The device ──────────────────────────────────────────────────────────────

fn ec_suspend(mut dev devcore.Device) bool {
	if dev.wakeup_enabled {
		return true
	}
	// Not to end the sleep: what it raises waits until the machine is awake.
	katomic.store(mut &acpiec_wiring.held, u32(1))
	if acpiec_wiring.gpe_installed && katomic.load(&acpiec_wiring.gpe_parked) == 0 {
		uacpi.suspend_gpe(acpiec_wiring.gpe_block, acpiec_wiring.gpe)
		acpiec_wiring.gpe_suspended = true
	}
	return true
}

fn ec_resume(mut _dev devcore.Device) bool {
	if acpiec_wiring.gpe_suspended {
		uacpi.resume_gpe(acpiec_wiring.gpe_block, acpiec_wiring.gpe)
		acpiec_wiring.gpe_suspended = false
	}
	katomic.store(mut &acpiec_wiring.held, u32(0))
	// A line that was stuck before the sleep is given another chance.
	if acpiec_wiring.gpe_installed && katomic.cas(mut &acpiec_wiring.gpe_parked, u32(1), u32(0)) {
		uacpi.finish_gpe(acpiec_wiring.gpe_block, acpiec_wiring.gpe)
	}
	catch_up()
	return true
}

// The machine is going down. Firmware's own last method (_PTS) may still
// use the controller, so exchanges go on working; only events stop.
fn ec_shutdown(mut _dev devcore.Device) {
	katomic.store(mut &acpiec_wiring.events_on, u32(0))
}

// The device core's way of trying a failed device again. Its first call
// after a failure is its own, made at once, and is declined: the exchanges
// that have just run out of time were the try, and another one now would
// hold the lock, and the global lock with it, for as long again. Declined,
// the device is marked failed. After that a call is somebody asking, through
// the device's `reset` file.
fn ec_reset(mut _dev devcore.Device) bool {
	if katomic.cas(mut &acpiec_wiring.fresh, u32(1), u32(0)) {
		return false
	}
	outcome, number := acpiec_controller.probe()
	if outcome != .ok {
		return false
	}
	katomic.store(mut &acpiec_wiring.reported, u32(0))
	print('acpiec: the controller answers again\n')
	if number != 0 {
		run_method(unsafe { nil }, number)
	}
	catch_up()
	return true
}

fn register_device() {
	mut driver := devcore.register_driver(devcore.Driver{
		name:     'ec'
		bus:      .acpi
		suspend:  ec_suspend
		resume:   ec_resume
		shutdown: ec_shutdown
		reset:    ec_reset
	}) or { return }
	mut dev := devcore.new_device(.acpi, 'PNP0C09:00')
	dev.compatible = 'PNP0C09'
	dev.bus_data = voidptr(acpiec_wiring.node)
	dev.wakeup_capable = true
	dev.wakeup_enabled = true
	if !devcore.add(mut dev) {
		unsafe {
			dev.name.free()
			free(dev)
		}
		return
	}
	devcore.claim(mut dev, mut driver)
	acpiec_wiring.device = dev
}

// Once ACPI's event threads run and /sys is there: the device, the event,
// and what the controller has been waiting to say.
pub fn start() {
	if !acpiec_wiring.present || acpiec_wiring.started {
		return
	}
	acpiec_wiring.started = true
	register_device()
	publish_status()
	katomic.store(mut &acpiec_wiring.events_on, u32(1))
	mut how := c'polled'
	if acpiec_wiring.has_gpe {
		status := uacpi.install_gpe_handler(acpiec_wiring.gpe_block, acpiec_wiring.gpe,
			uacpi.gpe_edge, gpe_handler, unsafe { nil })
		if status == .ok {
			// Before it is switched on: one already raised is handled there.
			acpiec_wiring.gpe_installed = true
			uacpi.mark_gpe_for_wake(acpiec_wiring.gpe_block, acpiec_wiring.gpe)
			enabled := uacpi.enable_gpe(acpiec_wiring.gpe_block, acpiec_wiring.gpe)
			if enabled == .ok {
				how = c'by its general purpose event'
			} else {
				acpiec_wiring.gpe_installed = false
				C.kprintf(c'acpiec: event 0x%llx cannot be switched on: %s\n', u64(acpiec_wiring.gpe),
					C.uacpi_status_to_string(enabled))
			}
		} else {
			C.kprintf(c'acpiec: event 0x%llx cannot be handled: %s\n', u64(acpiec_wiring.gpe),
				C.uacpi_status_to_string(status))
		}
	}
	sched.new_kernel_thread(voidptr(poll_thread), unsafe { nil }, true)
	$if acpiec_selftest ? {
		selftest_start()
	}
	source := source_name(acpiec_wiring.source)
	C.kprintf(c'acpiec: controller at ports 0x%llx/0x%llx (%.*s), events %s\n', u64(acpiec_wiring.data_port),
		u64(acpiec_wiring.command_port), i32(source.len), source.str, how)
	if acpiec_controller.failed {
		// Given up on before there was a device to say so of.
		if acpiec_wiring.device != unsafe { nil } {
			mut dev := acpiec_wiring.device
			devcore.report_failure(mut dev, 'no answer')
		}
		return
	}
	catch_up()
}
