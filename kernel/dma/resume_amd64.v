// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The IOMMUs after a sleep that cut their power.
//
// A unit comes back from a suspend to RAM as it is after power-on:
// translating nothing, pointing at no tables. Everything the kernel built --
// the root, context and device tables, each device's page tables, the command
// and event rings -- is memory and is still there, so a unit is brought back
// by writing its registers again and having it forget what it cached, which
// is the second half of bringing it up at boot.
//
// It has to happen before a device behind the unit may use the bus again.
// The addresses a driver gave its device are addresses in the device's
// domain; with the unit off they would be taken as physical addresses, and
// with it on they reach only what the domain holds. So resume_units() is
// called before PCI configuration space, and with it bus mastering, is
// restored, and long before a driver resumes.
//
// A unit that does not come back cannot be worked around: the devices behind
// it would run unconfined. That is not survivable silently, and stops the
// machine, as losing a CPU's protections across a sleep does.
@[has_globals]
module dma

import devcore

__global (
	// Units the kernel had switched on and found not translating on the way
	// back from a sleep, and units it brought back, over the machine's life.
	dma_resume_found_off u64
	dma_resume_restored  u64
)

fn vtd_translating(unit &VtdUnit) bool {
	status := vtd_read32(unit, vtd_reg_gsts)
	wanted := vtd_g_translation | vtd_g_root_pointer
	// All ones is a unit that is not there; and it must be translating
	// through the kernel's table, not one firmware left.
	return status != 0xffffffff && status & wanted == wanted
		&& vtd_read64(unit, vtd_reg_rtaddr) & ~u64(0xfff) == unit.root
}

fn amdvi_translating(unit &AmdviUnit) bool {
	control := amdvi_read64(unit, amdvi_reg_control)
	return control != ~u64(0) && control & amdvi_control_enable != 0
		&& amdvi_read64(unit, amdvi_reg_device_table) & ~u64(0xfff) == unit.device_table
}

fn vtd_unit_resume(mut unit VtdUnit) bool {
	if !vtd_translating(unit) {
		dma_resume_found_off++
	}
	unit.lock.acquire()
	// Firmware that guards memory on the way back hands the unit over
	// translating through tables of its own, as it may at boot; the root
	// pointer may only change while translation is off.
	if vtd_read32(unit, vtd_reg_gsts) & vtd_g_translation != 0 {
		if !vtd_global_command(mut unit, 0, vtd_g_translation, vtd_g_translation, false) {
			unit.lock.release()
			return false
		}
	}
	vtd_write32(unit, vtd_reg_fectl, vtd_fectl_masked)
	unit.lock.release()
	// Whatever faulted while firmware had the machine is firmware's business.
	vtd_drain_faults(mut unit, false)
	return vtd_unit_enable(mut unit)
}

fn amdvi_unit_resume(mut unit AmdviUnit) bool {
	// Registers that are not decoded read as all ones.
	if amdvi_read64(unit, amdvi_reg_control) == ~u64(0) {
		return false
	}
	if !amdvi_translating(unit) {
		dma_resume_found_off++
	}
	// Both rings start again from their first entry, under the locks their
	// users take: the thread that reads the event log is running.
	unit.event_lock.acquire()
	unit.lock.acquire()
	amdvi_program(mut unit)
	unit.event_stalled = 0
	unit.lock.release()
	unit.event_lock.release()
	devcore.spin_until(amdvi_rings_running, voidptr(unit), amdvi_register_timeout_ns)
	return amdvi_flush_everything(mut unit)
}

// How many of the units the kernel switched on say, in their own registers,
// that they are translating through the kernel's tables now.
pub fn units_translating() int {
	mut translating := 0
	for i in 0 .. vtd_unit_count {
		if vtd_units[i].enabled && vtd_translating(vtd_units[i]) {
			translating++
		}
	}
	for i in 0 .. amdvi_unit_count {
		if amdvi_units[i].on && amdvi_translating(amdvi_units[i]) {
			translating++
		}
	}
	return translating
}

// How many units have been found off on the way back from a sleep, and how
// many brought back, since the machine started.
pub fn resume_report() (u64, u64) {
	return dma_resume_found_off, dma_resume_restored
}

// How many units the kernel has switched on.
pub fn units_on() int {
	mut on := 0
	for i in 0 .. vtd_unit_count {
		if vtd_units[i].enabled {
			on++
		}
	}
	for i in 0 .. amdvi_unit_count {
		if amdvi_units[i].on {
			on++
		}
	}
	return on
}

// Switch every unit that was translating before the sleep back on, with the
// tables it had. Called on the way back from a suspend to RAM, before any
// device may use the bus. Does not return if one will not come back.
pub fn resume_units() {
	for i in 0 .. vtd_unit_count {
		mut unit := vtd_units[i]
		if !unit.enabled {
			continue
		}
		if !vtd_unit_resume(mut unit) {
			C.kprintf(c'vtd: %.*s did not come back from the sleep\n', i32(unit.name.len), unit.name.str)
			panic('dma: an IOMMU did not come back from a sleep; the devices behind it are no longer confined')
		}
		dma_resume_restored++
	}
	for i in 0 .. amdvi_unit_count {
		mut unit := amdvi_units[i]
		if !unit.on {
			continue
		}
		if !amdvi_unit_resume(mut unit) {
			C.kprintf(c'amdvi: %.*s did not come back from the sleep\n', i32(unit.name.len), unit.name.str)
			panic('dma: an IOMMU did not come back from a sleep; the devices behind it are no longer confined')
		}
		dma_resume_restored++
	}
}

// Switch every unit off, for good as far as this kernel goes: it is about
// to be replaced by another whose image has just been loaded from a disk
// (hibernate/resume_amd64.v), and whose own tables the units are to
// translate through next. Those tables are in memory already, but so are
// this kernel's, in frames about to be overwritten; a unit left translating
// through them would be translating through whatever lands there. The
// devices have been stopped, so nothing is asking for a translation, and the
// kernel that takes over switches the units on again as it does after a
// suspend to RAM. Interrupts off, one processor running.
pub fn hand_over_units() {
	for i in 0 .. vtd_unit_count {
		mut unit := vtd_units[i]
		if unit.enabled {
			vtd_unit_disable(mut unit)
		}
	}
	for i in 0 .. amdvi_unit_count {
		unit := amdvi_units[i]
		if unit.on {
			amdvi_quiesce(unit)
		}
	}
}
