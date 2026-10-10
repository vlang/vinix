// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The processor's energy counters, as /sys/class/powercap shows them.
// Translated from Linux's drivers/powercap/intel_rapl_msr.c and
// intel_rapl_common.c; which models have the counters and what a count is
// worth is in rapl_decode_amd64.v, and the arithmetic of a counter that
// wraps in energy.v.
//
//	/sys/class/powercap/intel-rapl:0/
//	    name                  package-0
//	    energy_uj             microjoules, read now
//	    max_energy_range_uj   where energy_uj wraps
//	    intel-rapl:0:N/       the same three for core, uncore and dram
//	/sys/class/powercap/intel-rapl:0:N -> intel-rapl:0/intel-rapl:0:N
//
// The registers are 32 bits wide and wrap in under an hour on a busy
// machine. The polling thread reads them every pass and adds the differences
// up in 64 bits, so energy_uj does not wrap where Linux's does:
// max_energy_range_uj is the range of the sum, 2^63 microjoules, and a
// program that handles Linux's wrap handles a counter that never gets there.
//
// Only the limits are left out: this reads the counters and sets nothing.
// Only the package of the boot CPU is read, and on AMD only the package
// counter: its other register counts one core, not the cores.
@[has_globals]
module thermal

import devcore
import fs
import katomic
import klock
import lib

struct RaplDomain {
mut:
	present bool
	name    string
	// The status register, and what one count of it is worth in nanojoules.
	index   u32
	unit    u64
	counter EnergyCounter
	// Someone is reading the register: two readers must not both add.
	updating u32
}

const rapl_domains = 4
const rapl_package = 0

// energy_uj counts up to here and starts again.
const rapl_shown_mask = u64(0x7fffffffffffffff)

// A sample the polling thread has not renewed for this long says nothing
// about the power now.
const rapl_stale_ns = 5 * devcore.second

__global (
	thermal_rapl_domains [rapl_domains]RaplDomain
	thermal_rapl_count   int
	// Guards the counters and the two samples.
	thermal_rapl_lock klock.Lock
	// The package's energy at the polling thread's last two passes.
	thermal_rapl_before EnergySample
	thermal_rapl_after  EnergySample
)

// Take a domain if its counter can be read and has counted anything, which
// is how rapl_check_domain() tells a domain that is there from one that is
// not.
fn rapl_add(slot int, name string, index u32, unit u64) bool {
	raw := probe_package_msr(index) or { return false }
	if raw & rapl_energy_mask == 0 {
		return false
	}
	mut domain := unsafe { &thermal_rapl_domains[slot] }
	domain.name = name
	domain.index = index
	domain.unit = unit
	fresh := EnergyCounter{}
	domain.counter = fresh.advanced(raw, rapl_energy_mask, unit)
	domain.updating = 0
	domain.present = true
	thermal_rapl_count++
	return true
}

fn rapl_start() {
	model := rapl_model(thermal_x86.vendor, thermal_x86.family, thermal_x86.model)
	if !model.supported {
		thermal_rapl_status = 'no energy counters known for this model'
		return
	}
	unit_index := if model.amd { msr_amd_rapl_power_unit } else { msr_rapl_power_unit }
	unit_register := probe_package_msr(unit_index) or {
		thermal_rapl_status = 'the model has energy counters, but the unit register faults'
		return
	}
	unit := rapl_energy_unit(unit_register, model.atom_units)
	if unit == 0 {
		thermal_rapl_status = 'the unit register names no unit'
		return
	}
	package_index := if model.amd { msr_amd_pkg_energy_status } else { msr_pkg_energy_status }
	if !rapl_add(rapl_package, 'package-0', package_index, unit) {
		thermal_rapl_status = 'the package counter faults or reads zero'
		return
	}
	if !model.amd {
		rapl_add(1, 'core', msr_pp0_energy_status, unit)
		rapl_add(2, 'uncore', msr_pp1_energy_status, unit)
		rapl_add(3, 'dram', msr_dram_energy_status, if model.dram_unit != 0 {
			model.dram_unit
		} else {
			unit
		})
	}

	base := 'class/powercap/intel-rapl:0'
	rapl_publish(base, unsafe { &thermal_rapl_domains[rapl_package] })
	mut sub := 0
	for slot in 1 .. rapl_domains {
		domain := unsafe { &thermal_rapl_domains[slot] }
		if !domain.present {
			continue
		}
		// Subzones are numbered in the order they were found, as Linux's are.
		directory := numbered('class/powercap/intel-rapl:0/intel-rapl:0:', sub, '', -1, '')
		rapl_publish(directory, domain)
		link := numbered('class/powercap/intel-rapl:0:', sub, '', -1, '')
		target := numbered('intel-rapl:0/intel-rapl:0:', sub, '', -1, '')
		fs.sysfs_link(link, target)
		unsafe {
			directory.free()
			link.free()
			target.free()
		}
		sub++
	}
	thermal_rapl_status = 'registered'
	C.kprintf(c'thermal: rapl: %lld energy domains, %llu nJ a count\n', i64(thermal_rapl_count),
		unit)
}

fn rapl_publish(directory string, domain &RaplDomain) {
	attribute(numbered(directory, -1, '/name', -1, ''), 0o444, show_rapl_name, unsafe { nil },
		voidptr(domain))
	attribute(numbered(directory, -1, '/energy_uj', -1, ''), 0o444, show_rapl_energy, unsafe { nil },
		voidptr(domain))
	attribute(numbered(directory, -1, '/max_energy_range_uj', -1, ''), 0o444, show_rapl_range,
		unsafe { nil }, voidptr(domain))
}

// Read the domain's register and add what it has counted since it was last
// read. False when the register could not be read. Whoever finds another
// reader at it leaves the adding to that one: what the two would read is the
// same to within the time it takes to say so.
fn rapl_advance(mut domain RaplDomain) bool {
	if !katomic.cas(mut &domain.updating, u32(0), u32(1)) {
		return true
	}
	mut good := false
	if raw := read_package_msr(domain.index) {
		thermal_rapl_lock.acquire()
		domain.counter = domain.counter.advanced(raw, rapl_energy_mask, domain.unit)
		thermal_rapl_lock.release()
		good = true
	}
	katomic.store(mut &domain.updating, u32(0))
	return good
}

// Called by the polling thread on every pass: often enough that no counter
// wraps unseen.
fn rapl_poll() {
	for slot in 0 .. rapl_domains {
		mut domain := unsafe { &thermal_rapl_domains[slot] }
		if !domain.present {
			continue
		}
		good := rapl_advance(mut domain)
		if slot == rapl_package && good {
			now := devcore.now_ns()
			thermal_rapl_lock.acquire()
			thermal_rapl_before = thermal_rapl_after
			thermal_rapl_after = EnergySample{
				valid:       true
				microjoules: domain.counter.microjoules
				nanoseconds: now
			}
			thermal_rapl_lock.release()
		}
	}
}

// The power the processor package drew over the polling thread's last
// interval, in milliwatts. None when the processor has no energy counter,
// before there have been two passes, and when the last pass is long ago.
pub fn package_power_mw() ?u64 {
	if thermal_rapl_count == 0 {
		return none
	}
	thermal_rapl_lock.acquire()
	before := thermal_rapl_before
	after := thermal_rapl_after
	thermal_rapl_lock.release()
	if !after.valid || devcore.now_ns() - after.nanoseconds > rapl_stale_ns {
		return none
	}
	power := average_milliwatts(before, after) or { return none }
	return power
}

fn show_rapl_name(context voidptr, mut text lib.Text) {
	domain := unsafe { &RaplDomain(context) }
	text.add(domain.name)
	text.add_byte(`\n`)
}

fn show_rapl_energy(context voidptr, mut text lib.Text) {
	mut domain := unsafe { &RaplDomain(context) }
	// A file that cannot say what the energy is now says nothing.
	if !rapl_advance(mut domain) {
		return
	}
	thermal_rapl_lock.acquire()
	energy := domain.counter.microjoules
	thermal_rapl_lock.release()
	text.add_unsigned(energy & rapl_shown_mask)
	text.add_byte(`\n`)
}

fn show_rapl_range(_ voidptr, mut text lib.Text) {
	text.add_unsigned(rapl_shown_mask)
	text.add_byte(`\n`)
}
