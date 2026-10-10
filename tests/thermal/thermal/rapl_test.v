// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// kernel/thermal/rapl_decode_amd64.v against Linux's intel_rapl_common.c:
// which models have energy counters, and what the unit register says a count
// is worth. The adding up of a counter that wraps is in energy_test.v; the
// last test here does it with a real unit.
module thermal

fn test_intel_models() {
	// rapl_ids, by the names intel-family.h gives the numbers.
	plain := [u32(0x2a), 0x2d, 0x3a, 0x3e, 0x3c, 0x45, 0x46, 0x3d, 0x47, 0x56, 0x4e, 0x5e, 0x8e,
		0x9e, 0x66, 0x7e, 0x7d, 0x9d, 0xa6, 0xa5, 0x8c, 0x8d, 0xa7, 0x97, 0x9a, 0xbe, 0xb7, 0xba,
		0xbf, 0xac, 0xaa, 0x8f, 0xcf, 0x8a, 0x5c, 0x7a, 0x5f, 0x96, 0x86, 0x9c]
	for model in plain {
		found := rapl_model(.intel, 6, model)
		assert found.supported && !found.amd && !found.atom_units && found.dram_unit == 0, 'model ${model:x}'
	}
	// The servers whose memory counts in units of 15.3 uJ.
	for model in [u32(0x3f), 0x4f, 0x55, 0x6a, 0x6c, 0x57, 0x85] {
		found := rapl_model(.intel, 6, model)
		assert found.supported && !found.atom_units && found.dram_unit == 15300, 'model ${model:x}'
	}
	// The Atoms whose unit register counts the other way.
	for model in [u32(0x37), 0x4c, 0x4a, 0x5a] {
		found := rapl_model(.intel, 6, model)
		assert found.supported && found.atom_units && found.dram_unit == 0, 'model ${model:x}'
	}
	assert plain.len + 7 + 4 == 51
}

fn test_models_without_counters() {
	// Core 2, Nehalem, the first Atoms, an Atom server Linux does not list.
	for model in [u32(0x0f), 0x17, 0x1a, 0x1c, 0x36, 0x4d, 0x75] {
		assert !rapl_model(.intel, 6, model).supported, 'model ${model:x}'
	}
	// The number alone is not enough: the family has to be 6.
	assert !rapl_model(.intel, 15, 0x5e).supported
	assert !rapl_model(.other, 6, 0x5e).supported
}

fn test_amd_models() {
	for family in [u32(0x17), 0x19, 0x1a] {
		found := rapl_model(.amd, family, 0x1)
		assert found.supported && found.amd && !found.atom_units
	}
	assert !rapl_model(.amd, 0x15, 0x2).supported
	assert !rapl_model(.amd, 0x18, 0x0).supported
	assert rapl_model(.hygon, 0x18, 0x0).supported && rapl_model(.hygon, 0x18, 0x0).amd
	assert !rapl_model(.hygon, 0x17, 0x1).supported
}

fn test_energy_unit() {
	// The usual register: power 2^-3 W, energy 2^-14 J, time 2^-10 s.
	assert rapl_energy_unit(0x000a0e03, false) == 61035
	// 2^-16 J, and a whole joule.
	assert rapl_energy_unit(0x00001000, false) == 15258
	assert rapl_energy_unit(0, false) == 1000000000
	// Only bits 12:8 are the energy unit.
	assert rapl_energy_unit(0xffffe0ff | (u64(14) << 8), false) == 61035
	// An exponent that leaves less than a nanojoule is no unit.
	assert rapl_energy_unit(u64(30) << 8, false) == 0
	assert rapl_energy_unit(u64(31) << 8, false) == 0
}

fn test_energy_unit_of_the_first_atoms() {
	// Microjoules, doubled: 2^5 of them.
	assert rapl_energy_unit(u64(5) << 8, true) == 32000
	assert rapl_energy_unit(0, true) == 1000
	// More than two joules a count would overflow the sum.
	assert rapl_energy_unit(u64(21) << 8, true) == 2097152000
	assert rapl_energy_unit(u64(22) << 8, true) == 0
	assert rapl_energy_unit(u64(31) << 8, true) == 0
}

fn test_a_day_at_sixty_watts_with_a_real_unit() {
	// 60 W for a day, read once a second: 983 040 counts a second, and the
	// register wraps every 73 minutes.
	unit := rapl_energy_unit(0x000a0e03, false)
	mut raw := u64(0xfff00000)
	mut counter := EnergyCounter{}.advanced(raw, rapl_energy_mask, unit)
	start := counter.microjoules
	mut wraps := 0
	for _ in 0 .. 86400 {
		next := (raw + 983040) & rapl_energy_mask
		if next < raw {
			wraps++
		}
		raw = next
		counter = counter.advanced(raw, rapl_energy_mask, unit)
	}
	assert wraps == 20
	used := counter.microjoules - start
	// 86 400 s of 983 040 counts of 61 035 nJ, to the microjoule.
	assert used == u64(86400) * 983040 * 61035 / 1000
	// Which is a day at very nearly 60 W.
	assert used / 86400 >= 59999000 && used / 86400 <= 60001000
}
