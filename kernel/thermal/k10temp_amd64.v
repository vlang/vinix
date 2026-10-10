// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// AMD's processor temperature, from family 10h on. Translated from Linux's
// drivers/hwmon/k10temp.c; what the registers mean, and where they are for
// each family, is in k10temp_decode_amd64.v.
//
// Tctl becomes the zone x86_pkg_temp, which thermal management steers by.
// Tdie, on the models whose Tctl is offset from it, and the per-die sensors
// of a Zen processor are its further sensors, which are only shown, under the
// hwmon name k10temp.
//
// There is no CPUID bit for this sensor: Linux finds it by the northbridge's
// PCI identity, and so does this, and then reads the register once. A machine
// whose host bridge is not AMD's -- a virtual one given an AMD processor's
// name -- has none.
//
// Not translated: k10temp's `force` parameter. A processor with erratum 319,
// whose sensor may be wrong, gets no zone.
@[has_globals]
module thermal

import klock
import memory
import pci
import x86.cpu

// Sensors a zone may have beyond Tctl: Tdie and twelve dies.
const k10_extra_sensors = 13

__global (
	thermal_k10_handle u64
	thermal_k10_model  K10Model
	// Tctl is this far above Tdie, where the table knows the model.
	thermal_k10_offset   i64
	thermal_k10_negative bool
	// The host bridge 00:00.0 and the northbridge's function 3, 00:18.3.
	thermal_k10_root &pci.PCIDevice
	thermal_k10_misc &pci.PCIDevice
	// The host bridge's index and data registers are one resource.
	thermal_k10_lock klock.Lock
	// The SMN addresses of the dies that have a sensor: their contexts.
	thermal_k10_dies [12]u32
)

fn k10_is_amd(device &pci.PCIDevice) bool {
	return device.vendor_id == pci_vendor_amd || device.vendor_id == pci_vendor_hygon
}

// A register behind an index and data pair of the host bridge. All ones is a
// register, or a bridge, that is not there.
fn k10_indexed_read(index_register u32, address u32) ?u32 {
	$if thermal_selftest ? {
		// The made-up processor of selftest_d_thermal_selftest.v has no bridge.
		if selftest_fake_kind() == fake_amd {
			mut made_up := u32(0)
			if index_register == 0x60 && selftest_fake_smn(address, unsafe { &made_up }) {
				return made_up
			}
			return none
		}
	}
	mut value := u32(0)
	thermal_k10_lock.acquire()
	wrote := thermal_k10_root.config_write(u64(index_register), 4, address)
	got := thermal_k10_root.config_read(u64(index_register + 4), 4, unsafe { &value })
	thermal_k10_lock.release()
	if wrote != pci.config_ok || got != pci.config_ok || value == 0xffffffff {
		return none
	}
	return value
}

fn k10_misc_read(register u32) ?u32 {
	mut value := u32(0)
	if thermal_k10_misc.config_read(u64(register), 4, unsafe { &value }) != pci.config_ok
		|| value == 0xffffffff {
		return none
	}
	return value
}

fn k10_smn_read(address u32) ?u32 {
	value := k10_indexed_read(0x60, address) or { return none }
	return value
}

// The reported-temperature register, wherever this model keeps it.
fn k10_temperature_register() ?u32 {
	access := thermal_k10_model.access
	if access == .northbridge {
		value := k10_misc_read(k10_reg_reported_temperature) or { return none }
		return value
	}
	if access == .indexed {
		value := k10_indexed_read(0xb8, f15h_m60h_reported_temp_ctrl) or { return none }
		return value
	}
	if access == .smn {
		value := k10_smn_read(zen_reported_temp_ctrl) or { return none }
		return value
	}
	return none
}

// The Hardware Thermal Control register, which only the models before Zen
// have.
fn k10_htc_register() ?u32 {
	access := thermal_k10_model.access
	if access == .northbridge {
		value := k10_misc_read(k10_reg_hardware_thermal_control) or { return none }
		return value
	}
	if access == .indexed {
		value := k10_indexed_read(0xb8, f15h_m60h_hardware_temp_ctrl) or { return none }
		return value
	}
	return none
}

// The northbridge function the register is in, or is found by, and the host
// bridge it is reached through from Zen on: Linux binds to the first by its
// PCI identity. False, with the reason left for x86_probe, when either is
// missing or is not AMD's.
fn k10_find_bridges() bool {
	thermal_k10_misc = pci.get_device_by_coordinates(0, 0x18, 3, 0) or {
		thermal_k10temp_status = 'no northbridge function at 00:18.3'
		return false
	}
	if !k10_is_amd(thermal_k10_misc) {
		thermal_k10temp_status = '00:18.3 is not an AMD northbridge'
		return false
	}
	if thermal_k10_model.access != .northbridge {
		thermal_k10_root = pci.get_device_by_coordinates(0, 0, 0, 0) or {
			thermal_k10temp_status = 'no host bridge at 00:00.0'
			return false
		}
		if !k10_is_amd(thermal_k10_root) {
			thermal_k10temp_status = 'the host bridge is not AMD: no SMN registers'
			return false
		}
	}
	return true
}

fn k10temp_start() {
	identity := thermal_x86
	if identity.vendor != .amd && identity.vendor != .hygon {
		thermal_k10temp_status = 'not an AMD processor'
		return
	}
	thermal_k10_model = k10temp_model(identity.vendor, identity.family, identity.model)
	if thermal_k10_model.access == .unsupported {
		thermal_k10temp_status = 'no temperature register known for this family'
		return
	}
	mut made_up := false
	$if thermal_selftest ? {
		made_up = selftest_fake_kind() == fake_amd
	}
	if !made_up && !k10_find_bridges() {
		return
	}
	if identity.family == 0x10 {
		_, _, package_type, _, _ := cpu.cpuid(0x80000001, 0)
		mut dram_config := u32(0)
		if dram := pci.get_device_by_coordinates(0, 0x18, 2, 0) {
			dram.config_read(u64(k10_reg_dct0_config_high), 4, unsafe { &dram_config })
		}
		if k10temp_erratum_319(identity.family, identity.model, identity.stepping, package_type,
			dram_config) {
			thermal_k10temp_status = 'erratum 319: the sensor of this processor is unreliable'
			return
		}
	}
	// The first read decides. Zero is what a bridge that takes the index and
	// has nothing behind it answers.
	first := k10_temperature_register() or {
		thermal_k10temp_status = 'the temperature register cannot be read'
		return
	}
	if first == 0 {
		thermal_k10temp_status = 'the temperature register reads zero'
		return
	}

	brand := x86_brand()
	offset, has_tdie := k10temp_tctl_offset(identity.family, brand)
	thermal_k10_offset = offset
	thermal_k10_negative = k10temp_shows_negative(identity.family, brand)

	mut htc := u32(0)
	mut htc_enabled := false
	if !thermal_k10_model.is_zen {
		if capabilities := k10_misc_read(k10_reg_northbridge_capabilities) {
			if value := k10_htc_register() {
				htc = value
				htc_enabled = k10temp_htc_enabled(capabilities, value)
			}
		}
	}
	trips := k10temp_trips(thermal_k10_model.is_zen, htc_enabled, htc)

	// The description is the caller's for the call: register_zone() copies it.
	mut sensors := unsafe { &Sensor(memory.malloc(u64(k10_extra_sensors) * sizeof(Sensor))) }
	mut count := 0
	if has_tdie {
		unsafe {
			sensors[count] = Sensor{
				label:   'Tdie'
				read:    k10temp_tdie_read
				context: nil
			}
		}
		count++
	}
	mut dies := 0
	for i in 0 .. thermal_k10_model.ccd_limit {
		address := k10temp_ccd_address(thermal_k10_model.ccd_offset, i)
		register := k10_smn_read(address) or { continue }
		if !k10temp_ccd_valid(register) {
			continue
		}
		thermal_k10_dies[dies] = address
		unsafe {
			sensors[count] = Sensor{
				label:   numbered('Tccd', i + 1, '', -1, '')
				read:    k10temp_die_read
				context: voidptr(&thermal_k10_dies[dies])
			}
		}
		dies++
		count++
	}
	mut zone := Zone{
		name:         'x86_pkg_temp'
		hwmon_name:   'k10temp'
		label:        'Tctl'
		read:         k10temp_tctl_read
		context:      unsafe { nil }
		sensors:      sensors
		sensor_count: count
	}
	zone.add_trip(.passive, trips.passive, 2000)
	zone.add_trip(.critical, trips.critical, trips.critical_hyst)
	thermal_k10_handle = register_zone(zone)
	unsafe {
		for i in 0 .. count {
			sensors[i].label.free()
		}
		memory.free(voidptr(sensors))
	}
	if thermal_k10_handle == 0 {
		thermal_k10temp_status = 'sensor found, but the zone could not be registered'
		return
	}
	thermal_k10temp_status = if htc_enabled {
		'registered; critical trip from Hardware Thermal Control'
	} else {
		'registered'
	}
	C.kprintf(c'thermal: k10temp: family 0x%x, %lld die sensors, passive %lld mC, critical %lld mC\n',
		identity.family, i64(dies), trips.passive, trips.critical)
}

fn k10temp_tctl_read(_ voidptr) ?i64 {
	register := k10_temperature_register() or { return none }
	raw := k10temp_raw_temperature(register, thermal_k10_model.adjust_mask)
	return k10temp_shown(raw, 0, thermal_k10_negative)
}

fn k10temp_tdie_read(_ voidptr) ?i64 {
	register := k10_temperature_register() or { return none }
	raw := k10temp_raw_temperature(register, thermal_k10_model.adjust_mask)
	return k10temp_shown(raw, thermal_k10_offset, thermal_k10_negative)
}

fn k10temp_die_read(context voidptr) ?i64 {
	address := unsafe { *&u32(context) }
	register := k10_smn_read(address) or { return none }
	if !k10temp_ccd_valid(register) {
		return none
	}
	return k10temp_ccd_temperature(register)
}
