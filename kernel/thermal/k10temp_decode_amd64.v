// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// AMD's processor temperature, read: what the registers mean. Translated from
// Linux's drivers/hwmon/k10temp.c.
//
// What an AMD processor reports is Tctl, the "control temperature": not the
// temperature of the die but a number on a scale that puts every model's
// limit at the same place, which is what a fan or a throttle is meant to be
// steered by. On a handful of models it is the die's temperature plus a fixed
// offset, and k10temp.c's table of those is repeated here so that Tdie can be
// shown beside it.
//
// Where the register is depends on the family: in the configuration space of
// the northbridge's function 3 up to family 16h, behind an index register of
// the host bridge on two models of family 15h, and behind the host bridge's
// SMN index and data registers from family 17h (Zen) on.
//
// Nothing in this file may import the kernel: tests/thermal runs it on the
// machine the kernel is built on.
module thermal

pub const pci_vendor_amd = u16(0x1022)
pub const pci_vendor_hygon = u16(0x1d94)

// Function 3 of the northbridge at 00:18.
pub const k10_reg_hardware_thermal_control = u32(0x64)
pub const k10_reg_reported_temperature = u32(0xa4)
pub const k10_reg_northbridge_capabilities = u32(0xe8)
// Function 2: the DRAM controller.
pub const k10_reg_dct0_config_high = u32(0x94)

// Family 15h models 60h and 70h: the same two registers, through the host
// bridge's index 0xb8 and data 0xbc.
pub const f15h_m60h_hardware_temp_ctrl = u32(0xd8200c64)
pub const f15h_m60h_reported_temp_ctrl = u32(0xd8200ca4)

// Zen: through the host bridge's SMN index 0x60 and data 0x64.
pub const zen_reported_temp_ctrl = u32(0x00059800)
pub const zen_cur_temp_range_sel = u32(1) << 19
const zen_cur_temp_tj_sel = u32(3) << 16
const zen_ccd_temp_valid = u32(1) << 11
const zen_ccd_temp_mask = u32(0x7ff)

// How the temperature register is reached.
pub enum K10Access {
	unsupported
	// Configuration space of 00:18.3.
	northbridge
	// The index and data registers 0xb8 and 0xbc of 00:00.0.
	indexed
	// The SMN registers 0x60 and 0x64 of 00:00.0.
	smn
}

pub struct K10Model {
pub mut:
	access K10Access
	// Set in the register when its range starts 49 degrees lower.
	adjust_mask u32
	is_zen      bool
	// Where the per-die sensors are, past zen_reported_temp_ctrl, and how
	// many there may be; none when the count is 0.
	ccd_offset u32
	ccd_limit  int
}

// k10temp_probe()'s choice by family and model.
pub fn k10temp_model(vendor X86Vendor, family u32, model u32) K10Model {
	mut found := K10Model{}
	if vendor != .amd && vendor != .hygon {
		return found
	}
	if family == 0x15 && (model & 0xf0 == 0x60 || model & 0xf0 == 0x70) {
		found.access = .indexed
	} else if family == 0x17 || family == 0x18 {
		found.access = .smn
		found.adjust_mask = zen_cur_temp_range_sel
		found.is_zen = true
		if model == 0x1 || model == 0x8 || model == 0x11 || model == 0x18 {
			// Zen, Zen+, and their APUs.
			found.ccd_offset = 0x154
			found.ccd_limit = 4
		} else if model == 0x31 || model == 0x60 || model == 0x68 || model == 0x71 {
			// Zen 2: Threadripper, Renoir, Lucienne, desktop.
			found.ccd_offset = 0x154
			found.ccd_limit = 8
		} else if model >= 0xa0 && model <= 0xaf {
			found.ccd_offset = 0x300
			found.ccd_limit = 8
		}
	} else if family == 0x19 {
		found.access = .smn
		found.adjust_mask = zen_cur_temp_range_sel
		found.is_zen = true
		if model <= 0x1 || model == 0x21 || (model >= 0x50 && model <= 0x5f) {
			// Zen 3: SP3 and Threadripper, desktop, Green Sardine.
			found.ccd_offset = 0x154
			found.ccd_limit = 8
		} else if model >= 0x40 && model <= 0x4f {
			// Yellow Carp.
			found.ccd_offset = 0x300
			found.ccd_limit = 8
		} else if model >= 0x60 && model <= 0x7f {
			found.ccd_offset = 0x308
			found.ccd_limit = 8
		} else if (model >= 0x10 && model <= 0x1f) || (model >= 0xa0 && model <= 0xaf) {
			found.ccd_offset = 0x300
			found.ccd_limit = 12
		}
	} else if family == 0x1a {
		found.access = .smn
		found.adjust_mask = zen_cur_temp_range_sel
		found.is_zen = true
	} else if family >= 0x10 && family <= 0x16 && family != 0x13 {
		// The families k10temp's table of northbridges covers.
		found.access = .northbridge
	}
	return found
}

// get_raw_temp(): the register's eleven bits of eighths of a degree, on the
// lower of the two ranges when the register says so.
pub fn k10temp_raw_temperature(register u32, adjust_mask u32) i64 {
	mut temperature := i64(register >> 21) * 125
	if register & adjust_mask != 0 || register & zen_cur_temp_tj_sel == zen_cur_temp_tj_sel {
		temperature -= 49000
	}
	return temperature
}

struct TctlOffset {
	family u32
	id     string
	offset i64
}

// tctl_offset_table of k10temp.c.
const tctl_offsets = [
	TctlOffset{0x17, 'AMD Ryzen 5 1600X', 20000},
	TctlOffset{0x17, 'AMD Ryzen 7 1700X', 20000},
	TctlOffset{0x17, 'AMD Ryzen 7 1800X', 20000},
	TctlOffset{0x17, 'AMD Ryzen 7 2700X', 10000},
	TctlOffset{0x17, 'AMD Ryzen Threadripper 19', 27000}, // 19{00,20,50}X
	TctlOffset{0x17, 'AMD Ryzen Threadripper 29', 27000}, // 29{20,50,70,90}[W]X
]!

// How far Tctl is above the die's temperature on this model, in millidegrees,
// and whether the table knows the model at all: Tdie is shown only if so.
pub fn k10temp_tctl_offset(family u32, brand string) (i64, bool) {
	for entry in tctl_offsets {
		if family == entry.family && brand.contains(entry.id) {
			return entry.offset, true
		}
	}
	return 0, false
}

// The industrial 3255 goes down to -40 C; every other model's negative
// readings are noise and shown as zero.
pub fn k10temp_shows_negative(family u32, brand string) bool {
	return family == 0x17 && brand.contains('3255')
}

// Tctl, and Tdie for `offset`, as k10temp_read_temp() shows them.
pub fn k10temp_shown(raw i64, offset i64, shows_negative bool) i64 {
	value := raw - offset
	if value < 0 && !shows_negative {
		return 0
	}
	return value
}

// A per-die sensor of a Zen processor: whether it is there, and what it reads.
pub fn k10temp_ccd_valid(register u32) bool {
	// All ones is a register that is not there, which would pass the test.
	return register != 0xffffffff && register & zen_ccd_temp_valid != 0
}

pub fn k10temp_ccd_temperature(register u32) i64 {
	return i64(register & zen_ccd_temp_mask) * 125 - 49000
}

pub fn k10temp_ccd_address(ccd_offset u32, index int) u32 {
	return zen_reported_temp_ctrl + ccd_offset + u32(index) * 4
}

// The Hardware Thermal Control register: the temperature at which the
// processor throttles itself, which the firmware programs. tempN_crit.
pub fn k10temp_htc_enabled(capabilities u32, htc u32) bool {
	return capabilities & (u32(1) << 10) != 0 && htc & 1 != 0
}

pub fn k10temp_htc_critical(htc u32) i64 {
	return i64((htc >> 16) & 0x7f) * 500 + 52000
}

pub fn k10temp_htc_hysteresis(htc u32) i64 {
	return i64((htc >> 24) & 0xf) * 500
}

// Erratum 319: the sensor of socket F and AM2+ processors of family 10h may
// be wrong. `package_type` is CPUID 0x80000001's EBX and `dram_config`
// register 0x94 of 00:18.2.
pub fn k10temp_erratum_319(family u32, model u32, stepping u32, package_type u32, dram_config u32) bool {
	if family != 0x10 {
		return false
	}
	kind := package_type & 0xf0000000
	if kind == 0x00000000 {
		// Socket F.
		return true
	}
	if kind != 0x10000000 {
		return false
	}
	// AM2r2 or AM3. DDR3 memory means socket AM3, which is good.
	if dram_config & (u32(1) << 8) != 0 {
		return false
	}
	// An AM3 processor can run DDR2 memory in an AM2+ board; the cores that
	// exist in AM2+ form are refused.
	return model < 4 || (model == 4 && stepping <= 2)
}

pub struct K10Trips {
pub mut:
	passive       i64
	critical      i64
	critical_hyst i64
	// tempN_max, where k10temp has one.
	has_maximum bool
	maximum     i64
}

// The zone's trips. Tctl's scale puts the limit at 95 C on Zen and at 70 C
// before it, which is k10temp's tempN_max there; the passive trip is ten
// degrees below. The critical trip is the firmware's, where Hardware Thermal
// Control is on, and five degrees above the limit where it is not.
pub fn k10temp_trips(is_zen bool, htc_enabled bool, htc u32) K10Trips {
	limit := if is_zen { i64(95000) } else { i64(70000) }
	mut trips := K10Trips{
		passive:       limit - 10000
		critical:      limit + 5000
		critical_hyst: 2000
		has_maximum:   !is_zen
		maximum:       70000
	}
	if htc_enabled {
		trips.critical = k10temp_htc_critical(htc)
		trips.critical_hyst = k10temp_htc_hysteresis(htc)
		if trips.passive >= trips.critical {
			trips.passive = trips.critical - 10000
		}
	}
	return trips
}
