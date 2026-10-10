// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What an AMD IOMMU reports, and what the kernel shows of it.
//
// When a unit turns a device away it writes sixteen bytes into its event log:
// which requester, which address, read or write. The log is a ring the unit
// fills at its tail and the kernel empties at its head. It is the only way to
// find out that a device tried to reach memory it was not given -- a driver
// bug, a device gone wrong, or one doing what an IOMMU is there to stop -- so
// every entry is counted, the device's domain is charged with it, and a line
// is logged, a few a second at most: a device that faults once tends to fault
// on every packet.
//
// The log is polled from a thread rather than taken as an interrupt. The
// unit's interrupt is an MSI of its own PCI function, and nothing here needs
// to hear of a fault sooner than a quarter of a second after it happened.
//
// The same thread publishes each unit under /sys/class/iommu, where Linux
// puts them, once /sys exists; units are found long before it is mounted.
@[has_globals]
module dma

import devcore
import fs
import klock
import lib
import sched

const amdvi_event_bytes = u32(16)

// Event codes, from the top four bits of an entry's second word.
const amdvi_event_illegal_entry = u32(1)
const amdvi_event_page_fault = u32(2)
const amdvi_event_kinds = 16

// How often the logs are looked at.
const amdvi_poll_ms = u64(250)
// Lines logged per second at most, over all units.
const amdvi_log_burst = u32(8)
// Entries of one look at a log that are kept to be logged after it.
const amdvi_shown_max = 8

struct AmdviEvent {
mut:
	kind    u32
	devid   u16
	domain  u16
	flags   u16
	address u64
}

__global (
	amdvi_poller_started bool
	amdvi_published      bool
	// The second the current burst of log lines began in, how many lines it
	// has had and how many were left out; under amdvi_log_lock.
	amdvi_log_lock       klock.Lock
	amdvi_log_window     u64
	amdvi_log_lines      u32
	amdvi_log_suppressed u64
)

// Whether one more line may be logged now.
fn amdvi_may_log() bool {
	amdvi_log_lock.acquire()
	defer {
		amdvi_log_lock.release()
	}
	window := devcore.now_ns() / devcore.second
	if window != amdvi_log_window {
		amdvi_log_window = window
		amdvi_log_lines = 0
	}
	if amdvi_log_lines >= amdvi_log_burst {
		amdvi_log_suppressed++
		return false
	}
	amdvi_log_lines++
	return true
}

fn amdvi_log_event(unit &AmdviUnit, event &AmdviEvent) {
	if !amdvi_may_log() {
		return
	}
	bus := u64(event.devid >> 8)
	slot := u64((event.devid >> 3) & 31)
	function := u64(event.devid & 7)
	if event.kind == amdvi_event_page_fault {
		C.kprintf(c'amdvi: I/O page fault: %02llx:%02llx.%llx address 0x%llx flags 0x%llx\n',
			bus, slot, function, event.address, u64(event.flags))
	} else if event.kind == amdvi_event_illegal_entry {
		C.kprintf(c'amdvi: illegal device table entry: %02llx:%02llx.%llx address 0x%llx flags 0x%llx\n',
			bus, slot, function, event.address, u64(event.flags))
	} else {
		C.kprintf(c'amdvi: %.*s: event %llu: device %02llx:%02llx.%llx address 0x%llx flags 0x%llx\n',
			i32(unit.name.len), unit.name.str, u64(event.kind), bus, slot, function, event.address,
			u64(event.flags))
	}
}

// Empty the unit's event log. Returns how many entries there were. Called
// from the poll thread, and by the self-test, which cannot wait for it.
fn amdvi_drain_events(mut unit AmdviUnit) u64 {
	if !unit.on {
		return 0
	}
	// Lines are logged after the lock is dropped: the console is slow.
	mut shown := [amdvi_shown_max]AmdviEvent{}
	mut showing := u32(0)
	mut seen := u64(0)

	unit.event_lock.acquire()
	mut head := amdvi_read32(unit, amdvi_reg_event_head) % amdvi_ring_bytes
	tail := amdvi_read32(unit, amdvi_reg_event_tail) % amdvi_ring_bytes
	for head != tail && seen < u64(amdvi_ring_bytes / amdvi_event_bytes) {
		mut words := unsafe { &u32(unit.events + higher_half + u64(head)) }
		mut event := AmdviEvent{}
		unsafe {
			event.kind = words[1] >> 28
			event.devid = u16(words[0])
			event.domain = u16(words[1])
			event.flags = u16((words[1] >> 16) & 0xfff)
			event.address = u64(words[2]) | (u64(words[3]) << 32)
		}
		if event.kind == 0 && unit.event_stalled != head + 1 {
			// AMD erratum 732: the tail can move before the entry is
			// written. Leave it for the next look, and take it as it is
			// then, so that one empty entry cannot hold the log up.
			unit.event_stalled = head + 1
			break
		}
		unit.event_stalled = 0
		// Cleared, as Linux does, so that an entry not yet written shows.
		unsafe {
			words[0] = 0
			words[1] = 0
			words[2] = 0
			words[3] = 0
		}
		unit.events_seen++
		unit.events_by_kind[event.kind & (amdvi_event_kinds - 1)]++
		if event.kind == amdvi_event_page_fault || event.kind == amdvi_event_illegal_entry {
			unit.last_fault = event
			unit.has_fault = true
			mut domain := amdvi_domain_sending(unit, event.devid)
			if domain != unsafe { nil } {
				domain.faults++
			}
		}
		if showing < u32(amdvi_shown_max) {
			shown[showing] = event
			showing++
		} else {
			unit.events_unshown++
		}
		head = (head + amdvi_event_bytes) % amdvi_ring_bytes
		seen++
	}
	if seen != 0 {
		amdvi_write32(unit, amdvi_reg_event_head, head)
	}
	// A full log stops. Start it again the way Linux does: off, the
	// overflow flag written back to clear it, on.
	if amdvi_read32(unit, amdvi_reg_status) & amdvi_status_event_overflow != 0 {
		unit.event_overflows++
		amdvi_control_clear(unit, amdvi_control_event_log)
		amdvi_write32(unit, amdvi_reg_status, amdvi_status_event_overflow)
		amdvi_control_set(unit, amdvi_control_event_log)
	}
	unit.event_lock.release()

	for i := u32(0); i < showing; i++ {
		amdvi_log_event(unit, unsafe { &shown[i] })
	}
	return seen
}

// The domain of the device that sends as `id`, or nil. Records are only ever
// added, at the head and complete, so the list is read without its lock.
fn amdvi_domain_sending(unit &AmdviUnit, id u16) &AmdviDomain {
	mut domain := unit.domains
	for domain != unsafe { nil } {
		if domain.devid == id || (domain.alias == id && domain.table.root != 0) {
			return domain
		}
		domain = domain.next
	}
	return unsafe { nil }
}

fn amdvi_poll_thread(arg voidptr) {
	for {
		// Until the units are in /sys the thread looks often, so that they
		// are there well before the first program could look for them.
		devcore.sleep_ms(if amdvi_published { amdvi_poll_ms } else { u64(2) })
		if !amdvi_published && sysfs_mounted {
			amdvi_publish()
		}
		for i in 0 .. amdvi_unit_count {
			mut unit := amdvi_units[i]
			amdvi_drain_events(mut unit)
		}
		amdvi_log_lock.acquire()
		suppressed := amdvi_log_suppressed
		if amdvi_log_lines < amdvi_log_burst {
			amdvi_log_suppressed = 0
		}
		amdvi_log_lock.release()
		if suppressed != 0 && amdvi_may_log() {
			C.kprintf(c'amdvi: %llu more events not logged; /sys/class/iommu has the counts\n',
				suppressed)
		}
	}
}

// Start the thread that reads the event logs. Once, when the first unit is on.
fn amdvi_start_poller() {
	if amdvi_poller_started {
		return
	}
	amdvi_poller_started = true
	sched.new_kernel_thread(voidptr(amdvi_poll_thread), unsafe { nil }, true)
}

// ── /sys/class/iommu/ivhdN ──────────────────────────────────────────────────

// "0000:00:02.0", as the PCI bus names its devices.
fn amdvi_add_device(mut text lib.Text, devid u16) {
	text.add('0000:')
	text.add_radix(u64(devid >> 8), 16, 2)
	text.add_byte(`:`)
	text.add_radix(u64((devid >> 3) & 31), 16, 2)
	text.add_byte(`.`)
	text.add_radix(u64(devid & 7), 16, 1)
}

fn amdvi_add_line(mut text lib.Text, name string, value u64) {
	text.add(name)
	text.add(': ')
	text.add_unsigned(value)
	text.add_byte(`\n`)
}

fn amdvi_show_unit(context voidptr, mut text lib.Text) {
	unit := unsafe { &AmdviUnit(context) }
	text.add(if unit.on { 'state: on\n' } else { 'state: off\n' })
	text.add('registers: 0x')
	text.add_radix(unit.mmio_phys, 16, 0)
	text.add('\npci: ')
	amdvi_add_device(mut text, unit.devid)
	text.add('\nivhd_type: 0x')
	text.add_radix(u64(unit.kind), 16, 2)
	text.add_byte(`\n`)
	amdvi_add_line(mut text, 'device_ids', u64(unit.last_devid) + 1)
	amdvi_add_line(mut text, 'ivhd_entries', u64(unit.entries.len))
	amdvi_add_line(mut text, 'unity_ranges', u64(amdvi_ivrs.unity.len))
	amdvi_add_line(mut text, 'levels', u64(unit.levels))
	amdvi_add_line(mut text, 'np_cache', if unit.np_cache { u64(1) } else { u64(0) })
	amdvi_add_line(mut text, 'table_pages', unit.table_pages)
	amdvi_add_line(mut text, 'leaked_pages', unit.leaked_pages)
	amdvi_add_line(mut text, 'commands', unit.commands_queued)
	amdvi_add_line(mut text, 'command_timeouts', unit.command_timeouts)
}

// The extended feature registers, as Linux prints them: "29d3:0".
fn amdvi_show_features(context voidptr, mut text lib.Text) {
	unit := unsafe { &AmdviUnit(context) }
	text.add_radix(unit.features, 16, 0)
	text.add_byte(`:`)
	text.add_radix(unit.features2, 16, 0)
	text.add_byte(`\n`)
}

// The capability header of the unit's PCI function, as Linux prints it.
fn amdvi_show_cap(context voidptr, mut text lib.Text) {
	unit := unsafe { &AmdviUnit(context) }
	text.add_radix(u64(unit.capability), 16, 0)
	text.add_byte(`\n`)
}

fn amdvi_show_events(context voidptr, mut text lib.Text) {
	unit := unsafe { &AmdviUnit(context) }
	amdvi_add_line(mut text, 'total', unit.events_seen)
	amdvi_add_line(mut text, 'io_page_faults', unit.events_by_kind[2])
	amdvi_add_line(mut text, 'illegal_device_table_entries', unit.events_by_kind[1])
	amdvi_add_line(mut text, 'device_table_errors', unit.events_by_kind[3])
	amdvi_add_line(mut text, 'page_table_errors', unit.events_by_kind[4])
	amdvi_add_line(mut text, 'illegal_commands', unit.events_by_kind[5])
	amdvi_add_line(mut text, 'command_errors', unit.events_by_kind[6])
	amdvi_add_line(mut text, 'invalidation_timeouts', unit.events_by_kind[7])
	amdvi_add_line(mut text, 'invalid_device_requests', unit.events_by_kind[8])
	amdvi_add_line(mut text, 'overflows', unit.event_overflows)
	text.add('last_fault: ')
	if unit.has_fault {
		// A copy: the poll thread may be writing the next one.
		fault := unit.last_fault
		amdvi_add_device(mut text, fault.devid)
		text.add(' address 0x')
		text.add_radix(fault.address, 16, 0)
		text.add(' flags 0x')
		text.add_radix(u64(fault.flags), 16, 0)
		text.add(' domain ')
		text.add_unsigned(u64(fault.domain))
		text.add_byte(`\n`)
	} else {
		text.add('none\n')
	}
}

// One line per device that has tables: who, under which number, how much.
fn amdvi_show_domains(context voidptr, mut text lib.Text) {
	unit := unsafe { &AmdviUnit(context) }
	mut domain := unit.domains
	for domain != unsafe { nil } {
		if domain.table.root != 0 {
			amdvi_add_device(mut text, domain.devid)
			if domain.alias != domain.devid {
				text.add(' as ')
				amdvi_add_device(mut text, domain.alias)
			}
			text.add(' id ')
			text.add_unsigned(u64(domain.id))
			text.add(if domain.identity {
				' identity'
			} else if domain.driver {
				' driver'
			} else {
				' firmware'
			})
			text.add(' mapped_kb ')
			text.add_unsigned(domain.table.mapped / 1024)
			text.add(' table_pages ')
			text.add_unsigned(domain.table.pages)
			text.add(' faults ')
			text.add_unsigned(domain.faults)
			text.add(' attaches ')
			text.add_unsigned(domain.attaches)
			text.add_byte(`\n`)
		}
		domain = domain.next
	}
}

fn amdvi_publish_file(unit &AmdviUnit, leaf string, show fs.SysfsShow) {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(48) }
	text.add('class/iommu/')
	text.add(unit.name)
	text.add_byte(`/`)
	text.add(leaf)
	path := text.str()
	fs.sysfs_attribute(path, 0o444, show, unsafe { nil }, voidptr(unit))
	unsafe { path.free() }
}

// Called once, by the poll thread, when /sys has been mounted.
fn amdvi_publish() {
	amdvi_published = true
	for i in 0 .. amdvi_unit_count {
		unit := amdvi_units[i]
		amdvi_publish_file(unit, 'unit', amdvi_show_unit)
		amdvi_publish_file(unit, 'features', amdvi_show_features)
		amdvi_publish_file(unit, 'cap', amdvi_show_cap)
		amdvi_publish_file(unit, 'events', amdvi_show_events)
		amdvi_publish_file(unit, 'domains', amdvi_show_domains)
	}
}
