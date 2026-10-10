// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The processor's energy counters, read: which models have them and what a
// count is worth. Translated from Linux's drivers/powercap/intel_rapl_msr.c
// and intel_rapl_common.c.
//
// RAPL -- running average power limit -- is Intel's name for a set of
// registers that count the energy the package, its cores, its graphics and
// its memory have used. No CPUID bit says they are there: Linux goes by a
// list of models, and then takes a domain only if its counter reads something
// other than zero. The same is done here. AMD has the unit and the package
// counter under other numbers from family 17h on.
//
// Nothing in this file may import the kernel: tests/thermal runs it on the
// machine the kernel is built on.
module thermal

pub const msr_rapl_power_unit = u32(0x606)
pub const msr_pkg_energy_status = u32(0x611)
pub const msr_dram_energy_status = u32(0x619)
pub const msr_pp0_energy_status = u32(0x639)
pub const msr_pp1_energy_status = u32(0x641)
pub const msr_amd_rapl_power_unit = u32(0xc0010299)
pub const msr_amd_pkg_energy_status = u32(0xc001029b)

// The counters are 32 bits of their registers.
pub const rapl_energy_mask = u64(0xffffffff)

// The largest count's worth this driver takes: 32 bits of counts times this
// many nanojoules must fit 64 bits.
const rapl_unit_limit = u64(1) << 31

pub struct RaplModel {
pub mut:
	supported bool
	// AMD's registers rather than Intel's.
	amd bool
	// The unit register counts as the first Atoms' does.
	atom_units bool
	// The memory domain's unit when it is not the package's: 15.3 uJ on the
	// servers from Haswell on. 0 for the package's.
	dram_unit u64
}

// rapl_ids: the models Linux reads these registers on.
pub fn rapl_model(vendor X86Vendor, family u32, model u32) RaplModel {
	mut found := RaplModel{}
	if vendor == .amd {
		found.supported = family == 0x17 || family == 0x19 || family == 0x1a
		found.amd = true
		return found
	}
	if vendor == .hygon {
		found.supported = family == 0x18
		found.amd = true
		return found
	}
	if vendor != .intel || family != 6 {
		return found
	}
	match model {
		// Sandy Bridge, Ivy Bridge, Haswell, Broadwell and their clients.
		0x2a, 0x2d, 0x3a, 0x3e, 0x3c, 0x45, 0x46, 0x3d, 0x47, 0x56 {
			found.supported = true
		}
		// Sky Lake to Comet Lake.
		0x4e, 0x5e, 0x8e, 0x9e, 0x66, 0x7e, 0x7d, 0x9d, 0xa6, 0xa5 {
			found.supported = true
		}
		// Tiger Lake, Rocket Lake, Alder Lake, Gracemont, Raptor Lake, Meteor
		// Lake, Lakefield.
		0x8c, 0x8d, 0xa7, 0x97, 0x9a, 0xbe, 0xb7, 0xba, 0xbf, 0xac, 0xaa, 0x8a {
			found.supported = true
		}
		// Sapphire Rapids and Emerald Rapids.
		0x8f, 0xcf {
			found.supported = true
		}
		// The servers whose memory domain has a unit of its own: Haswell-X,
		// Broadwell-X, Sky Lake-X, Ice Lake-X and -D, Knights Landing and
		// Knights Mill.
		0x3f, 0x4f, 0x55, 0x6a, 0x6c, 0x57, 0x85 {
			found.supported = true
			found.dram_unit = 15300
		}
		// Silvermont, Airmont and their phone variants.
		0x37, 0x4c, 0x4a, 0x5a {
			found.supported = true
			found.atom_units = true
		}
		// Goldmont, Goldmont Plus, Denverton, Tremont.
		0x5c, 0x7a, 0x5f, 0x96, 0x86, 0x9c {
			found.supported = true
		}
		else {}
	}
	return found
}

// What one count of an energy register is worth, in nanojoules, from the
// unit register: rapl_check_unit_core() and rapl_check_unit_atom(). 0 when
// the register describes no unit this driver can count in.
pub fn rapl_energy_unit(unit_register u64, atom_units bool) u64 {
	exponent := (unit_register & 0x1f00) >> 8
	unit := if atom_units {
		// Microjoules, doubled `exponent` times.
		u64(1000) << exponent
	} else {
		// A joule, halved `exponent` times.
		u64(1000000000) >> exponent
	}
	if unit == 0 || unit >= rapl_unit_limit {
		return 0
	}
	return unit
}
