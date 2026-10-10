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
module dma

import devcore

fn vtd_unit_resume(mut unit VtdUnit) bool {
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

// How many units are translating.
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
	}
}
