// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The embedded controller as /sys shows it: what it is and how it has been
// behaving, in a directory of the device's own.
//
//	/sys/bus/acpi/devices/PNP0C09:00/ec/
//	    data_port command_port   the two I/O ports, in hexadecimal
//	    source                   who described it: ECDT, namespace, both
//	    uid                      its _UID
//	    gpe                      its general purpose event, or `none`
//	    events                   how events are heard: gpe, polled, off
//	    global_lock              1 when exchanges take the ACPI global lock
//	    failed                   1 once it has been given up on
//	    failure                  why, or `none`
//	    transactions             exchanges begun
//	    timeouts                 exchanges that got no answer in time
//	    restarts                 attempts after the first, over all of them
//	    stale_bytes              bytes found in the output buffer unasked
//	    refused                  callers told at once that it has failed
//	    queries                  events the controller named
//	    methods                  _Qxx methods run for them
//	    methods_missing          events firmware has no method for
//	    gpe_count                times its general purpose event was raised
//	    sleep_events             queries that found events while asleep
//
// Everything is read-only. There is no file that reads or writes the
// controller's memory: its bytes are battery charge limits, fan curves and
// keyboard matrices, laid out differently on every model, and a write to the
// wrong one can damage the machine. The device's own `state`, `health` and
// `reset` files, which the device core gives every device, say whether it is
// in use and try a failed one again.
module acpiec

import fs
import katomic
import lib

enum Status {
	data_port
	command_port
	source
	uid
	gpe
	events
	global_lock
	failed
	failure
	transactions
	timeouts
	restarts
	stale_bytes
	refused
	queries
	methods
	methods_missing
	gpe_count
	sleep_events
}

const status_count = 19

fn status_file(status Status) string {
	return match status {
		.data_port { 'data_port' }
		.command_port { 'command_port' }
		.source { 'source' }
		.uid { 'uid' }
		.gpe { 'gpe' }
		.events { 'events' }
		.global_lock { 'global_lock' }
		.failed { 'failed' }
		.failure { 'failure' }
		.transactions { 'transactions' }
		.timeouts { 'timeouts' }
		.restarts { 'restarts' }
		.stale_bytes { 'stale_bytes' }
		.refused { 'refused' }
		.queries { 'queries' }
		.methods { 'methods' }
		.methods_missing { 'methods_missing' }
		.gpe_count { 'gpe_count' }
		.sleep_events { 'sleep_events' }
	}
}

fn add_hex(mut text lib.Text, value u64) {
	text.add('0x')
	text.add_radix(value, 16, 0)
}

// How events reach the driver now.
fn events_name() string {
	if katomic.load(&acpiec_wiring.events_on) == 0 {
		return 'off'
	}
	if acpiec_wiring.gpe_installed && katomic.load(&acpiec_wiring.gpe_parked) == 0 {
		return 'gpe'
	}
	return 'polled'
}

// The file's context is its Status plus one, so that the first is not the
// nil a file with no context has.
fn show_status(context voidptr, mut text lib.Text) {
	status := unsafe { Status(int(u64(context) - 1)) }
	controller := &acpiec_controller
	match status {
		.data_port { add_hex(mut text, u64(acpiec_wiring.data_port)) }
		.command_port { add_hex(mut text, u64(acpiec_wiring.command_port)) }
		.source { text.add(source_name(acpiec_wiring.source)) }
		.uid { text.add_unsigned(acpiec_wiring.uid) }
		.gpe {
			if acpiec_wiring.has_gpe {
				add_hex(mut text, u64(acpiec_wiring.gpe))
			} else {
				text.add('none')
			}
		}
		.events { text.add(events_name()) }
		.global_lock { text.add_unsigned(if acpiec_wiring.global_lock { u64(1) } else { u64(0) }) }
		.failed { text.add_unsigned(if controller.failed { u64(1) } else { u64(0) }) }
		.failure {
			text.add(if controller.failed { outcome_name(controller.failure) } else { 'none' })
		}
		.transactions { text.add_unsigned(controller.transactions) }
		// Every exchange that failed, whichever way.
		.timeouts { text.add_unsigned(controller.timeouts + controller.stuck_outputs) }
		.restarts { text.add_unsigned(controller.restarts) }
		.stale_bytes { text.add_unsigned(controller.stale_bytes) }
		.refused { text.add_unsigned(controller.refused) }
		.queries { text.add_unsigned(controller.queries) }
		.methods { text.add_unsigned(katomic.load(&acpiec_wiring.methods)) }
		.methods_missing { text.add_unsigned(katomic.load(&acpiec_wiring.methods_missing)) }
		.gpe_count { text.add_unsigned(controller.gpes) }
		.sleep_events { text.add_unsigned(katomic.load(&acpiec_wiring.sleep_events)) }
	}
	text.add_byte(`\n`)
}

// The path of `name` in the controller's own directory, relative to /sys.
// The caller frees it.
fn status_path(name string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(96) }
	text.add(acpiec_wiring.device.sysfs_path)
	text.add('/ec/')
	text.add(name)
	return text.str()
}

// Publish the files. Called once the device is in /sys.
fn publish_status() {
	if acpiec_wiring.device == unsafe { nil } || acpiec_wiring.device.sysfs_path.len == 0 {
		return
	}
	for index in 0 .. status_count {
		path := status_path(status_file(unsafe { Status(index) }))
		fs.sysfs_attribute(path, 0o444, show_status, unsafe { nil }, voidptr(u64(index) + 1))
		unsafe { path.free() }
	}
}
