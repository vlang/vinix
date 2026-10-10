// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What a VT-d unit refused, and what /sys says about it.
//
// A transfer that the tables do not allow is stopped by the unit and written
// into one of its fault records: which device, which address, read or write,
// and a reason code. The records are few -- QEMU's unit has one, a real one
// eight or so -- and one that is full is not overwritten, so they are read
// and cleared four times a second by a thread here rather than on the unit's
// interrupt, which stays masked. A device that faults faster than that loses
// faults to the overflow bit, which is counted; nothing else depends on the
// records, since the transfer was refused either way.
//
// Each unit has a directory in /sys/class/iommu, named as Linux names it:
//
//	/sys/class/iommu/dmar0/
//	    cap ecap version address   the unit's registers, as Linux prints them
//	    state                      translation on or off, and how it is set up
//	    domains                    how many devices have one, and which
//	    pages                      pages of page table and of context table
//	    faults                     how many transfers were refused, and the last
//
// The files appear a moment after /sys is mounted: the units are switched on
// long before there is a /sys to put them in.
@[has_globals]
module dma

import devcore
import fs
import lib
import sched

const vtd_fsts_overflow = u32(1)
const vtd_fsts_pending = u32(2)
const vtd_frcd_fault = u32(1) << 31
const vtd_frcd_read = u32(1) << 30

const vtd_poll_ms = u64(250)

// Fault lines in the log: this many in any such stretch of time, and a count
// of the rest. A device left running into a wall can fault thousands of times
// a second.
const vtd_log_burst = u32(8)
const vtd_log_window_ns = 5 * devcore.second

struct VtdFault {
mut:
	sid     u32
	address u64
	reason  u32
	read    bool
}

__global (
	vtd_poller_started bool
	vtd_published      bool
)

// Whether one more fault may be logged. The unit's lock is held.
fn vtd_log_allowed(mut unit VtdUnit) bool {
	now := devcore.now_ns()
	if !unit.log_started || now - unit.log_window_start >= vtd_log_window_ns {
		unit.log_started = true
		unit.log_window_start = now
		unit.log_window_lines = 0
	}
	if unit.log_window_lines >= vtd_log_burst {
		unit.log_suppressed++
		return false
	}
	unit.log_window_lines++
	return true
}

// Read and clear the unit's fault records. With `report` they are counted
// and, within the limit above, logged; without, they are only cleared, which
// is what is wanted of faults that predate the kernel's tables. Returns how
// many records there were.
fn vtd_drain_faults(mut unit VtdUnit, report bool) u32 {
	name := unit.name
	// Logged after the lock is dropped: the console is slow, and the lock
	// is held with interrupts off.
	mut lines := [8]VtdFault{}
	mut line_count := 0
	mut suppressed := u64(0)
	mut taken := u32(0)
	unit.lock.acquire()
	status := vtd_read32(unit, vtd_reg_fsts)
	if status == 0xffffffff || status & (vtd_fsts_pending | vtd_fsts_overflow) == 0 {
		unit.lock.release()
		return 0
	}
	// The status says where the oldest record is; the rest follow it, round
	// the end. No more than there are records are read in one go, so a device
	// faulting as fast as its records are cleared cannot keep this loop.
	mut index := (status >> 8) & 0xff
	for n := u32(0); n < unit.fault_records; n++ {
		if index >= unit.fault_records {
			index = 0
		}
		record := unit.fault_reg + u64(index) * 16
		high := vtd_read32(unit, record + 12)
		if high & vtd_frcd_fault == 0 {
			break
		}
		fault := VtdFault{
			sid:     vtd_read32(unit, record + 8) & 0xffff
			address: vtd_read64(unit, record) & ~u64(0xfff)
			reason:  high & 0xff
			read:    high & vtd_frcd_read != 0
		}
		// Writing the bit back is what clears the record.
		vtd_write32(unit, record + 12, vtd_frcd_fault)
		taken++
		index++
		if !report {
			continue
		}
		unit.faults++
		unit.last_fault = fault
		if vtd_log_allowed(mut unit) && line_count < 8 {
			lines[line_count] = fault
			line_count++
		}
	}
	if report && status & vtd_fsts_overflow != 0 {
		unit.fault_overflows++
	}
	vtd_write32(unit, vtd_reg_fsts, vtd_fsts_overflow)
	if line_count != 0 && unit.log_suppressed != 0 {
		suppressed = unit.log_suppressed
		unit.log_suppressed = 0
	}
	unit.lock.release()

	if suppressed != 0 {
		C.kprintf(c'vtd: %.*s: %llu more faults were not logged\n', i32(name.len), name.str,
			suppressed)
	}
	for i := 0; i < line_count; i++ {
		fault := lines[i]
		C.kprintf(c'vtd: %.*s: DMA fault: %02llx:%02llx.%llx %s 0x%llx reason 0x%02llx\n',
			i32(name.len), name.str, u64(fault.sid >> 8), u64((fault.sid >> 3) & 0x1f),
			u64(fault.sid & 7), if fault.read { c'read from' } else { c'write to' }, fault.address,
			u64(fault.reason))
	}
	return taken
}

fn vtd_poller() {
	for {
		for i := u32(0); i < vtd_unit_count; i++ {
			mut unit := vtd_units[i]
			if unit.enabled {
				vtd_drain_faults(mut unit, true)
			}
		}
		// Nothing can be published before the filesystems exist, and nothing
		// here is told when they do.
		if !vtd_published && sysfs_mounted {
			vtd_publish()
		}
		devcore.sleep_ms(vtd_poll_ms)
	}
}

fn vtd_start_poller() {
	if vtd_poller_started {
		return
	}
	vtd_poller_started = true
	sched.new_kernel_thread(voidptr(vtd_poller), unsafe { nil }, true)
}

// ── /sys/class/iommu/dmarN ──────────────────────────────────────────────────

fn vtd_publish_file(unit &VtdUnit, leaf string, show fs.SysfsShow) {
	// On the stack, as every path in devcore/sysfs.v is: a builder made as a
	// local value is moved to the heap and left there.
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

fn vtd_publish() {
	vtd_published = true
	for i := u32(0); i < vtd_unit_count; i++ {
		unit := vtd_units[i]
		vtd_publish_file(unit, 'cap', vtd_show_cap)
		vtd_publish_file(unit, 'ecap', vtd_show_ecap)
		vtd_publish_file(unit, 'version', vtd_show_version)
		vtd_publish_file(unit, 'address', vtd_show_address)
		vtd_publish_file(unit, 'state', vtd_show_state)
		vtd_publish_file(unit, 'domains', vtd_show_domains)
		vtd_publish_file(unit, 'pages', vtd_show_pages)
		vtd_publish_file(unit, 'faults', vtd_show_faults)
		$if vtd_selftest ? {
			vtd_selftest_publish(unit)
		}
	}
}

fn vtd_show_cap(context voidptr, mut text lib.Text) {
	unit := unsafe { &VtdUnit(context) }
	text.add_radix(unit.cap, 16, 0)
	text.add_byte(`\n`)
}

fn vtd_show_ecap(context voidptr, mut text lib.Text) {
	unit := unsafe { &VtdUnit(context) }
	text.add_radix(unit.ecap, 16, 0)
	text.add_byte(`\n`)
}

fn vtd_show_version(context voidptr, mut text lib.Text) {
	unit := unsafe { &VtdUnit(context) }
	text.add_unsigned(u64((unit.version >> 4) & 0xf))
	text.add_byte(`:`)
	text.add_unsigned(u64(unit.version & 0xf))
	text.add_byte(`\n`)
}

fn vtd_show_address(context voidptr, mut text lib.Text) {
	unit := unsafe { &VtdUnit(context) }
	text.add_radix(vtd_firmware.drhds[unit.drhd].address, 16, 0)
	text.add_byte(`\n`)
}

fn vtd_show_state(context voidptr, mut text lib.Text) {
	unit := unsafe { &VtdUnit(context) }
	text.add('translation: ')
	text.add(if unit.enabled { 'on' } else { 'off' })
	text.add('\naddress_bits: ')
	text.add_unsigned(u64(unit.address_bits))
	text.add('\nlevels: ')
	text.add_unsigned(u64(unit.levels))
	text.add('\nsuperpages:')
	if unit.superpages & 1 != 0 {
		text.add(' 2M')
	}
	if unit.superpages & 2 != 0 {
		text.add(' 1G')
	}
	if unit.superpages & 3 == 0 {
		text.add(' none')
	}
	text.add('\ncoherent: ')
	text.add(if unit.coherent { 'yes' } else { 'no' })
	text.add('\ntimeouts: ')
	text.add_unsigned(unit.timeouts)
	text.add_byte(`\n`)
}

fn vtd_add_device(mut text lib.Text, sid u32) {
	text.add_radix(u64(sid >> 8), 16, 2)
	text.add_byte(`:`)
	text.add_radix(u64((sid >> 3) & 0x1f), 16, 2)
	text.add_byte(`.`)
	text.add_radix(u64(sid & 7), 16, 1)
}

struct VtdDomainLine {
mut:
	sid      u32
	did      u32
	tables   u64
	firmware bool
	identity bool
}

// How many domains there are, and the first sixteen of them. They are copied
// out under the unit's lock and written down after it: the text may have to
// grow, and memory is not asked for with a spinlock held.
fn vtd_show_domains(context voidptr, mut text lib.Text) {
	mut unit := unsafe { &VtdUnit(context) }
	mut lines := [16]VtdDomainLine{}
	mut line_count := 0
	mut firmware := u64(0)
	unit.lock.acquire()
	used := u64(unit.domain_count)
	mut domain := unit.domains
	for domain != unsafe { nil } {
		if domain.firmware {
			firmware++
		}
		if line_count < 16 {
			lines[line_count] = VtdDomainLine{
				sid:      domain.sid
				did:      domain.did
				tables:   domain.tables
				firmware: domain.firmware
				identity: domain.identity
			}
			line_count++
		}
		domain = domain.next
	}
	unit.lock.release()
	text.add('used: ')
	text.add_unsigned(used)
	text.add('\nfirmware: ')
	text.add_unsigned(firmware)
	text.add('\nsupported: ')
	text.add_unsigned(u64(unit.domain_limit))
	text.add_byte(`\n`)
	for i := 0; i < line_count; i++ {
		line := lines[i]
		vtd_add_device(mut text, line.sid)
		text.add(' domain ')
		text.add_unsigned(u64(line.did))
		text.add(if line.firmware {
			' firmware'
		} else if line.identity {
			' identity'
		} else {
			' isolated'
		})
		text.add(' tables ')
		text.add_unsigned(line.tables)
		text.add_byte(`\n`)
	}
}

fn vtd_show_pages(context voidptr, mut text lib.Text) {
	unit := unsafe { &VtdUnit(context) }
	text.add('tables: ')
	text.add_unsigned(unit.table_pages)
	text.add('\ncontext: ')
	text.add_unsigned(unit.context_pages)
	text.add_byte(`\n`)
}

fn vtd_show_faults(context voidptr, mut text lib.Text) {
	mut unit := unsafe { &VtdUnit(context) }
	unit.lock.acquire()
	count := unit.faults
	overflows := unit.fault_overflows
	last := unit.last_fault
	unit.lock.release()
	text.add('count: ')
	text.add_unsigned(count)
	text.add('\noverflows: ')
	text.add_unsigned(overflows)
	text.add('\nlast: ')
	if count == 0 {
		text.add('none\n')
		return
	}
	vtd_add_device(mut text, last.sid)
	text.add(if last.read { ' read 0x' } else { ' write 0x' })
	text.add_radix(last.address, 16, 0)
	text.add(' reason 0x')
	text.add_radix(u64(last.reason), 16, 2)
	text.add_byte(`\n`)
}
