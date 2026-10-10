// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Which idle states are offered for which processor, on the host.
// mwait_table.v beside this file is the kernel's mwait_table_amd64.v.
module cpuidle

// CPUID.5:EDX of a Skylake or a Haswell-ULT: C1 has two sub-states, and
// every MWAIT C-state up to the one for C10 is there.
const all_states = u32(0x11142120)

// The same of a desktop Haswell: nothing past C7s.
const up_to_c7 = u32(0x00042120)

fn intel(model u32, substates u32) MwaitCpu {
	return MwaitCpu{
		intel:       true
		family:      6
		model:       model
		monitor:     true
		leaf5:       true
		extensions:  3
		substates:   substates
		arat:        true
		nonstop_tsc: true
	}
}

// What `qemu-system-x86_64 -accel tcg -cpu max` reports (QEMU 11.1).
fn tcg_max() MwaitCpu {
	return MwaitCpu{
		amd:        true
		family:     6
		model:      6
		monitor:    true
		leaf5:      true
		extensions: 3
		substates:  0
		arat:       true
	}
}

fn names(t MwaitTable) string {
	mut all := ''
	for i in 0 .. t.count {
		if i > 0 {
			all += ' '
		}
		all += t.states[i].name
	}
	return all
}

fn test_no_monitor_is_halt() {
	t := mwait_table(MwaitCpu{ amd: true, family: 15, leaf5: true })
	assert t.driver == 'halt'
	assert t.count == 1
	assert t.states[0].name == 'C1'
	assert t.states[0].desc == 'HLT'
	assert t.states[0].flags == 0
	assert t.states[0].exit_latency_us == 1
}

fn test_emulated_mwait_with_no_c1_substate_is_halt() {
	// MONITOR is advertised, the extensions too, and no state has a
	// sub-state. There MWAIT is a pause and an idle CPU would spin.
	t := mwait_table(tcg_max())
	assert t.driver == 'halt'
	assert names(t) == 'C1'
	assert t.states[0].desc == 'HLT'
}

fn test_forced_mwait_on_that_emulator_is_plain_mwait() {
	mut c := tcg_max()
	c.forced = true
	t := mwait_table(c)
	assert t.driver == 'mwait'
	assert t.count == 1
	assert t.states[0].desc == 'MWAIT 0x00'
	assert t.states[0].hint == 0
	// Entered like HLT. ECX[0] is never set for a processor whose CPUID
	// leaf 5 does not describe it, whatever its interrupt-break bit says.
	assert t.states[0].flags == state_mwait
}

fn test_mwait_without_extensions_is_plain_mwait() {
	// A Pentium 4 with MONITOR: leaf 5, no extension bits.
	t := mwait_table(MwaitCpu{ intel: true, family: 15, model: 3, monitor: true, leaf5: true })
	assert t.driver == 'mwait'
	assert names(t) == 'C1'
	assert t.states[0].flags == state_mwait
}

fn test_mwait_without_interrupt_break_is_plain_mwait() {
	mut c := intel(0x5e, all_states)
	c.extensions = 1
	t := mwait_table(c)
	assert t.driver == 'mwait'
	assert names(t) == 'C1'
	assert t.states[0].flags == state_mwait
}

fn test_skylake_table() {
	t := mwait_table(intel(0x5e, all_states))
	assert t.driver == 'mwait'
	assert names(t) == 'C1 C1E C3 C6 C7s'
	// skl_cstates, drivers/idle/intel_idle.c.
	assert t.states[0].hint == 0x00 && t.states[0].exit_latency_us == 2 && t.states[0].target_residency_us == 2
	assert t.states[1].hint == 0x01 && t.states[1].exit_latency_us == 10 && t.states[1].target_residency_us == 20
	assert t.states[2].hint == 0x10 && t.states[2].exit_latency_us == 70 && t.states[2].target_residency_us == 100
	assert t.states[3].hint == 0x20 && t.states[3].exit_latency_us == 85 && t.states[3].target_residency_us == 200
	assert t.states[4].hint == 0x33 && t.states[4].exit_latency_us == 124 && t.states[4].target_residency_us == 800
	for i in 0 .. t.count {
		assert t.states[i].flags == state_mwait | state_masked
	}
	// Kaby Lake uses the same table.
	assert names(mwait_table(intel(0x9e, all_states))) == 'C1 C1E C3 C6 C7s'
}

fn test_states_cpuid_does_not_enumerate_are_left_out() {
	// hsw_cstates on a desktop Haswell and on a Haswell-ULT.
	assert names(mwait_table(intel(0x3c, up_to_c7))) == 'C1 C1E C3 C6 C7s'
	assert names(mwait_table(intel(0x45, all_states))) == 'C1 C1E C3 C6 C7s C8 C9 C10'
	// A Sandy Bridge whose firmware hid C7.
	assert names(mwait_table(intel(0x2a, 0x00001120))) == 'C1 C1E C3 C6'
	assert names(mwait_table(intel(0x2a, 0x00011120))) == 'C1 C1E C3 C6 C7'
}

fn test_tables_are_ordered_shallow_to_deep() {
	for model in [u32(0x1e), 0x2a, 0x3a, 0x3c, 0x3d, 0x5e, 0x97] {
		t := mwait_table(intel(model, all_states))
		for i in 1 .. t.count {
			assert t.states[i].exit_latency_us >= t.states[i - 1].exit_latency_us
			assert t.states[i].target_residency_us >= t.states[i - 1].target_residency_us
		}
	}
}

fn test_no_arat_no_deeper_state() {
	// The APIC timer ends the idle; where it stops, only C1 is safe.
	mut c := intel(0x1e, 0x00001120)
	c.arat = false
	t := mwait_table(c)
	assert t.driver == 'mwait'
	assert names(t) == 'C1'
	assert t.states[0].flags == state_mwait | state_masked
	c.arat = true
	assert names(mwait_table(c)) == 'C1 C1E C3 C6'
}

fn test_no_nonstop_tsc_no_deeper_state() {
	mut c := intel(0x5e, all_states)
	c.nonstop_tsc = false
	assert names(mwait_table(c)) == 'C1'
}

fn test_unknown_intel_model_gets_the_generic_states() {
	// Alder Lake, which has no table here: C1, C1E and C6 are enumerated,
	// the C-state for C3 is not, and nothing deeper is touched.
	t := mwait_table(intel(0x97, 0x10102020))
	assert t.driver == 'mwait'
	assert names(t) == 'C1 C1E C6'
	// The slowest figures of the tables: nehalem's C1 and C6.
	assert t.states[0].exit_latency_us == 3 && t.states[0].target_residency_us == 6
	assert t.states[2].hint == 0x20 && t.states[2].exit_latency_us == 200 && t.states[2].target_residency_us == 800
	assert names(mwait_table(intel(0x97, all_states))) == 'C1 C1E C3 C6'
	// One C1 sub-state: no C1E without a table to say so.
	assert names(mwait_table(intel(0x97, 0x00000110))) == 'C1 C3'
}

fn test_server_models_get_the_generic_states() {
	// SKYLAKE_X is use_acpi in intel_idle.c; its own table is not taken.
	assert names(mwait_table(intel(0x55, 0x00002020))) == 'C1 C1E C6'
}

fn test_amd_gets_c1() {
	// A Zen: C0 and C1 each have one sub-state.
	t := mwait_table(MwaitCpu{
		amd:         true
		family:      0x17
		model:       0x71
		monitor:     true
		leaf5:       true
		extensions:  3
		substates:   0x11
		arat:        true
		nonstop_tsc: true
	})
	assert t.driver == 'mwait'
	assert names(t) == 'C1'
	assert t.states[0].flags == state_mwait | state_masked
	assert t.reason.contains('_CST')
}

fn test_max_cstate_keeps_the_first_states() {
	mut c := intel(0x45, all_states)
	c.limit = 2
	assert names(mwait_table(c)) == 'C1 C1E'
	c.limit = 1
	assert names(mwait_table(c)) == 'C1'
	c.limit = 99
	assert mwait_table(c).count == 8
}

fn test_substate_counts() {
	assert mwait_substates(all_states, 0x00) == 2
	assert mwait_substates(all_states, 0x01) == 2
	assert mwait_substates(all_states, 0x10) == 1
	assert mwait_substates(all_states, 0x20) == 2
	assert mwait_substates(all_states, 0x33) == 4
	assert mwait_substates(all_states, 0x60) == 1
	assert mwait_substates(up_to_c7, 0x40) == 0
}
