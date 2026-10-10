// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Telling an AMD IOMMU that its tables changed.
//
// The unit keeps copies of what it has read: a device's table entry, and the
// translations of the pages a device has touched. Changing memory does not
// change the copies. A command does -- "forget this device's entry", "forget
// this domain's pages" -- and commands are carried out in the order they are
// queued, some time after the tail register is written.
//
// COMPLETION_WAIT is how the kernel learns that the time has passed: the unit
// writes the number the command carries into a word of memory when it reaches
// it. Every such command carries the next number, so once the word holds a
// given number or a later one, everything queued before that command is done.
// Nothing here waits without an end: a unit that stops answering is reported
// and the caller told, never spun on.
module dma

import devcore
import x86.kio

// The command's number goes in the top four bits of its second word.
const amdvi_command_completion_wait = u32(0x1) << 28
const amdvi_command_invalidate_device = u32(0x2) << 28
const amdvi_command_invalidate_pages = u32(0x3) << 28
const amdvi_command_invalidate_all = u32(0x8) << 28

const amdvi_command_bytes = u32(16)
// COMPLETION_WAIT: store the number at the address given.
const amdvi_completion_store = u32(1)
// INVALIDATE_IOMMU_PAGES: the address covers more than one page, and the
// tables above the last level are to be forgotten as well.
const amdvi_pages_size = u32(1)
const amdvi_pages_tables = u32(2)
// With the size bit, this address means every page of the domain.
const amdvi_pages_everything = u64(0x7ffffffffffff000)

// Put one command in the ring and tell the unit. False when the ring stayed
// full for as long as a working unit never takes; the command is then not
// queued. `unit.lock` is held.
fn amdvi_queue_locked(mut unit AmdviUnit, w0 u32, w1 u32, w2 u32, w3 u32) bool {
	next := (unit.command_tail + amdvi_command_bytes) % amdvi_ring_bytes
	if next == unit.command_head {
		// Full as far as we know. The unit moves the head as it works.
		limit := devcore.deadline(amdvi_register_timeout_ns)
		for {
			unit.command_head = amdvi_read32(unit, amdvi_reg_command_head) % amdvi_ring_bytes
			if next != unit.command_head {
				break
			}
			if limit.expired() {
				return false
			}
			devcore.relax()
		}
	}
	mut words := unsafe { &u32(unit.commands + higher_half + u64(unit.command_tail)) }
	unsafe {
		words[0] = w0
		words[1] = w1
		words[2] = w2
		words[3] = w3
	}
	unit.command_tail = next
	unit.commands_queued++
	amdvi_write32(unit, amdvi_reg_command_tail, next)
	return true
}

fn amdvi_queue(mut unit AmdviUnit, w0 u32, w1 u32, w2 u32, w3 u32) bool {
	unit.lock.acquire()
	queued := amdvi_queue_locked(mut unit, w0, w1, w2, w3)
	unit.lock.release()
	return queued
}

// Forget the device table entry of `devid`.
fn amdvi_forget_device(mut unit AmdviUnit, devid u16) bool {
	return amdvi_queue(mut unit, u32(devid), amdvi_command_invalidate_device, 0, 0)
}

// Forget the translation of the page at `address` in domain `domain`.
fn amdvi_forget_page(mut unit AmdviUnit, domain u16, address u64) bool {
	page := address & ~(amdvi_page_bytes - 1)
	return amdvi_queue(mut unit, 0, amdvi_command_invalidate_pages | u32(domain), u32(page),
		u32(page >> 32))
}

// Forget every translation of domain `domain`, and with `tables` what the
// unit remembers of the levels above the pages.
fn amdvi_forget_domain(mut unit AmdviUnit, domain u16, tables bool) bool {
	mut low := u32(amdvi_pages_everything) | amdvi_pages_size
	if tables {
		low |= amdvi_pages_tables
	}
	return amdvi_queue(mut unit, 0, amdvi_command_invalidate_pages | u32(domain), low,
		u32(amdvi_pages_everything >> 32))
}

// Return once the unit has carried out everything queued so far. False if it
// has not within the time a working unit needs a thousand times over: the
// caller must then not rely on the unit having forgotten anything.
fn amdvi_sync(mut unit AmdviUnit) bool {
	unit.lock.acquire()
	unit.command_sequence++
	sequence := unit.command_sequence
	queued := amdvi_queue_locked(mut unit, u32(unit.semaphore) | amdvi_completion_store,
		u32(unit.semaphore >> 32) | amdvi_command_completion_wait, u32(sequence), u32(sequence >> 32))
	unit.lock.release()

	mut done := false
	if queued {
		// The unit writes the word, so it is read as a device's memory is:
		// afresh every time, whatever the compiler thinks it knows.
		word := unsafe { &u64(unit.semaphore + higher_half) }
		limit := devcore.deadline(amdvi_register_timeout_ns)
		for {
			if i64(kio.mmin[u64](word) - sequence) >= 0 {
				done = true
				break
			}
			if limit.expired() {
				done = i64(kio.mmin[u64](word) - sequence) >= 0
				break
			}
			devcore.relax()
		}
	}
	if !done {
		unit.lock.acquire()
		unit.command_timeouts++
		first := unit.command_timeouts == 1
		unit.lock.release()
		// Once: a unit that has stopped will fail every command after this.
		if first {
			C.kprintf(c'amdvi: %.*s: a command was not carried out in time (head 0x%llx, tail 0x%llx, status 0x%llx)\n',
				i32(unit.name.len), unit.name.str, u64(amdvi_read32(unit, amdvi_reg_command_head)),
				u64(unit.command_tail), u64(amdvi_read32(unit, amdvi_reg_status)))
		}
	}
	return done
}

// Have the unit forget everything it remembers, when it is switched on.
//
// Every device table entry is named to it one by one, even for a unit that
// has INVALIDATE_ALL. Hardware needs no more than that one command; QEMU's
// unit only starts translating for a device when it is told to forget that
// device's entry, and until then lets the device through whatever its entry
// says. It is at most 65536 commands, once, and milliseconds.
fn amdvi_flush_everything(mut unit AmdviUnit) bool {
	if !amdvi_forget_devices(mut unit) {
		return false
	}
	if unit.features & amdvi_feature_invalidate_all != 0 {
		if !amdvi_queue(mut unit, 0, amdvi_command_invalidate_all, 0, 0) {
			return false
		}
		return amdvi_sync(mut unit)
	}
	return amdvi_forget_domains(mut unit)
}

// Forget every device table entry.
fn amdvi_forget_devices(mut unit AmdviUnit) bool {
	for devid := u32(0); devid <= unit.last_devid; devid++ {
		if !amdvi_forget_device(mut unit, u16(devid)) {
			return false
		}
	}
	return amdvi_sync(mut unit)
}

// Forget the translations of every domain there could be: for a unit without
// INVALIDATE_ALL. The ring holds 512 commands; the unit empties it as fast
// as it is filled.
fn amdvi_forget_domains(mut unit AmdviUnit) bool {
	for domain := u32(0); domain <= 0xffff; domain++ {
		if !amdvi_forget_domain(mut unit, u16(domain), true) {
			return false
		}
	}
	return amdvi_sync(mut unit)
}
