// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Intel's digital thermal sensors: one in every core, and on processors since
// Sandy Bridge one for the package. Translated from Linux's
// drivers/hwmon/coretemp.c; what the registers mean is in
// coretemp_decode_amd64.v.
//
// The package becomes the zone x86_pkg_temp, which thermal management steers
// by, and the cores its further sensors, which are only shown: temp1 is the
// package and temp2 onwards the cores, under the hwmon name coretemp. A
// processor with no package sensor is steered by its hottest core.
//
// A core's register is read on that core, through read_msr_on(). Only the
// package of the boot CPU is looked at: a second socket's sensors are not
// published.
//
// Not translated: coretemp.c's check for errata AE18, which is of the Core
// Duo, a processor that cannot run a 64-bit kernel; and CPU hotplug, which
// this kernel does not have.
@[has_globals]
module thermal

import devcore
import memory
import pci

struct CoretempCore {
mut:
	// The logical CPU its register is read on, and its number in the package.
	cpu  u64
	core u32
}

__global (
	thermal_coretemp_handle u64
	thermal_coretemp_tjmax  Tjmax
	// The zone's critical trip: see dts_zone_temperature().
	thermal_coretemp_critical i64
	// The package has a sensor of its own.
	thermal_coretemp_package bool
	thermal_coretemp_cores   &CoretempCore
	thermal_coretemp_count   int
)

// TjMax forced on the command line, as coretemp's tjmax= parameter: degrees
// Celsius, used only where the processor does not say. 0 for none.
fn coretemp_forced_tjmax() i64 {
	word := devcore.boot_option('vinix.tjmax=') or { return 0 }
	degrees := parse_signed(word) or { return 0 }
	if degrees <= 0 || degrees > 150 {
		return 0
	}
	return degrees * 1000
}

fn coretemp_start() {
	if thermal_x86.vendor != .intel {
		thermal_coretemp_status = 'not an Intel processor'
		return
	}
	features := x86_thermal_features()
	if features & cpuid6_dtherm == 0 {
		thermal_coretemp_status = 'CPUID.6:EAX names no digital thermal sensor'
		return
	}
	// The register itself decides: see platform_amd64.v.
	if !msr_readable_on(0, msr_ia32_therm_status) {
		thermal_coretemp_status = 'CPUID names the sensor, but IA32_THERM_STATUS faults'
		return
	}
	thermal_coretemp_package = false
	if features & cpuid6_pts != 0 && msr_readable_on(0, msr_ia32_package_therm_status) {
		thermal_coretemp_package = true
	}

	// TjMax: get_tjmax().
	mut target := u64(0)
	mut target_ok := false
	if value := read_msr_on(0, msr_ia32_temperature_target) {
		target = value
		target_ok = true
	}
	mut facts := TjmaxFacts{
		model:    thermal_x86.model
		stepping: thermal_x86.stepping
		brand:    x86_brand()
	}
	if !target_ok || coretemp_target_tjmax(target) == 0 {
		// The tables and the guess need these; a processor that says its
		// TjMax is not asked.
		if bridge := pci.get_device_by_coordinates(0, 0, 0, 0) {
			facts.bridge_vendor = bridge.vendor_id
			facts.bridge_device = bridge.device_id
		}
		if value := read_msr_on(0, msr_ia32_platform_id) {
			facts.platform = value
			facts.platform_ok = true
		}
		if value := read_msr_on(0, msr_ia32_ext_config) {
			facts.ee = value
			facts.ee_ok = true
		}
	}
	thermal_coretemp_tjmax = coretemp_tjmax(target_ok, target, coretemp_forced_tjmax(), facts)
	tjmax := thermal_coretemp_tjmax.millicelsius
	thermal_coretemp_critical = coretemp_critical_trip(thermal_coretemp_tjmax)

	// One sensor for each core of the boot CPU's package whose register can
	// be read: its first logical CPU does the reading.
	home := x86_package_of(cpu_locals[0].lapic_id, thermal_x86_topology)
	// For the life of the machine, or until the registration below fails.
	thermal_coretemp_cores = unsafe { &CoretempCore(memory.malloc(u64(cpu_locals.len) * sizeof(CoretempCore))) }
	mut count := 0
	for i in 0 .. cpu_locals.len {
		apic_id := cpu_locals[i].lapic_id
		if x86_package_of(apic_id, thermal_x86_topology) != home {
			continue
		}
		core := x86_core_of(apic_id, thermal_x86_topology)
		mut seen := false
		for j in 0 .. count {
			if unsafe { thermal_coretemp_cores[j].core } == core {
				seen = true
			}
		}
		if seen {
			continue
		}
		if !msr_readable_on(u64(i), msr_ia32_therm_status) {
			continue
		}
		unsafe {
			thermal_coretemp_cores[count] = CoretempCore{
				cpu:  u64(i)
				core: core
			}
		}
		count++
	}
	thermal_coretemp_count = count

	// The description is the caller's for the call: register_zone() copies it.
	mut sensors := unsafe { &Sensor(memory.malloc(u64(count + 1) * sizeof(Sensor))) }
	for i in 0 .. count {
		unsafe {
			sensors[i] = Sensor{
				label:        numbered('Core ', int(thermal_coretemp_cores[i].core), '', -1, '')
				read:         coretemp_core_read
				alarm:        coretemp_core_alarm
				context:      voidptr(&thermal_coretemp_cores[i])
				has_maximum:  thermal_coretemp_tjmax.from_register
				maximum:      coretemp_target_ttarget(target)
				has_critical: true
				critical:     tjmax
			}
		}
	}
	mut zone := Zone{
		name:         'x86_pkg_temp'
		hwmon_name:   'coretemp'
		label:        'Package id 0'
		read:         coretemp_zone_read
		alarm:        coretemp_zone_alarm
		context:      unsafe { nil }
		sensors:      sensors
		sensor_count: count
	}
	zone.add_trip(.passive, coretemp_passive_trip(thermal_coretemp_tjmax, target), 2000)
	zone.add_trip(.critical, thermal_coretemp_critical, 2000)
	thermal_coretemp_handle = register_zone(zone)
	unsafe {
		for i in 0 .. count {
			sensors[i].label.free()
		}
		memory.free(voidptr(sensors))
	}
	if thermal_coretemp_handle == 0 {
		thermal_coretemp_count = 0
		memory.free(voidptr(thermal_coretemp_cores))
		thermal_coretemp_cores = unsafe { nil }
		thermal_coretemp_status = 'sensors found, but the zone could not be registered'
		return
	}
	thermal_coretemp_status = if thermal_coretemp_tjmax.from_register {
		'registered; TjMax from IA32_TEMPERATURE_TARGET'
	} else {
		'registered; TjMax from the tables, so temperatures may be off by a constant'
	}
	C.kprintf(c'thermal: coretemp: %lld cores, package sensor %s, TjMax %lld mC\n', i64(count),
		if thermal_coretemp_package { c'present' } else { c'absent' }, tjmax)
}

// The hottest core, for a processor with no package sensor.
fn coretemp_hottest_core() ?i64 {
	mut hottest := i64(0)
	mut any := false
	for i in 0 .. thermal_coretemp_count {
		core := unsafe { &thermal_coretemp_cores[i] }
		status := read_msr_on(core.cpu, msr_ia32_therm_status) or { continue }
		value := dts_zone_temperature(status, thermal_coretemp_tjmax.millicelsius, thermal_coretemp_critical) or {
			continue
		}
		if !any || value > hottest {
			hottest = value
			any = true
		}
	}
	if !any {
		return none
	}
	return hottest
}

fn coretemp_zone_read(_ voidptr) ?i64 {
	if !thermal_coretemp_package {
		hottest := coretemp_hottest_core() or { return none }
		return hottest
	}
	status := read_package_msr(msr_ia32_package_therm_status) or { return none }
	value := dts_zone_temperature(status, thermal_coretemp_tjmax.millicelsius, thermal_coretemp_critical) or {
		return none
	}
	return value
}

// coretemp's tempN_crit_alarm: the critical temperature has been reached.
fn coretemp_zone_alarm(_ voidptr) ?bool {
	if !thermal_coretemp_package {
		mut raised := false
		mut any := false
		for i in 0 .. thermal_coretemp_count {
			core := unsafe { &thermal_coretemp_cores[i] }
			status := read_msr_on(core.cpu, msr_ia32_therm_status) or { continue }
			any = true
			if dts_decode(status).critical_log {
				raised = true
			}
		}
		if !any {
			return none
		}
		return raised
	}
	status := read_package_msr(msr_ia32_package_therm_status) or { return none }
	return dts_decode(status).critical_log
}

fn coretemp_core_read(context voidptr) ?i64 {
	core := unsafe { &CoretempCore(context) }
	status := read_msr_on(core.cpu, msr_ia32_therm_status) or { return none }
	return coretemp_temperature(status, thermal_coretemp_tjmax.millicelsius)
}

fn coretemp_core_alarm(context voidptr) ?bool {
	core := unsafe { &CoretempCore(context) }
	status := read_msr_on(core.cpu, msr_ia32_therm_status) or { return none }
	return dts_decode(status).critical_log
}
