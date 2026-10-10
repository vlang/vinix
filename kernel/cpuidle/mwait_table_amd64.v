// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The idle states of an x86-64 processor, worked out from what CPUID says.
//
// MONITOR/MWAIT is how a processor is asked for a particular idle state: the
// hint in EAX names it, C-state in the high nibble and sub-state in the low.
// CPUID leaf 5 says how many sub-states each C-state has, and whether MWAIT
// can be told to treat an interrupt as a reason to wake even while interrupts
// are masked, which is what lets the idle loop be woken and still finish its
// bookkeeping before the handler runs.
//
// What CPUID does not say is how long a state takes to leave. Linux's
// intel_idle (drivers/idle/intel_idle.c) carries a table of measured figures
// per processor model, and falls back on the firmware's ACPI _CST for a model
// it has no table for. This kernel does not evaluate _CST yet, so:
//
//   - A model whose table is copied here from intel_idle.c gets that table,
//     each state checked against CPUID leaf 5 as intel_idle_verify_cstate()
//     checks it.
//   - Any other Intel family 6 processor gets C1, C1E, and the C3 and C6 that
//     CPUID enumerates, with the slowest figures any of those tables has for
//     them. Deeper states are left alone without a table: they are where the
//     per-model exceptions are.
//   - An AMD processor gets C1. Its deeper states are entered through I/O
//     ports or MWAIT hints that only _CST names.
//
// A state deeper than C1 is offered only when the local APIC timer keeps
// running in it (CPUID.6:EAX[2], ARAT), since that timer is what ends the
// idle, and only when the TSC does too (CPUID.80000007:EDX[8]), since the
// residency is measured with it.
//
// A function of plain values with no kernel imports: tests/cpu-power runs it
// on the host against the CPUID words of real and emulated processors.
module cpuidle

// State.flags: entered with MWAIT rather than HLT.
pub const state_mwait = u32(1)

// State.flags: MWAIT is executed with interrupts masked and ECX[0] set, so
// that a masked interrupt ends it.
pub const state_masked = u32(2)

// CPUID.5:ECX. Hints and extensions in MWAIT's registers mean something.
const leaf5_extensions = u32(1)

// CPUID.5:ECX. MWAIT's ECX[0] makes a masked interrupt a wake-up.
const leaf5_interrupt_break = u32(2)

// What the driver read from CPUID and the command line.
pub struct MwaitCpu {
pub mut:
	intel  bool
	amd    bool
	family u32
	model  u32
	// CPUID.1:ECX[3].
	monitor bool
	// CPUID leaf 5 exists; its ECX and EDX.
	leaf5      bool
	extensions u32
	substates  u32
	// CPUID.6:EAX[2] and CPUID.80000007:EDX[8].
	arat        bool
	nonstop_tsc bool
	// vinix.cpuidle=mwait: use MWAIT for C1 although CPUID enumerates no C1
	// sub-state. See mwait_table().
	forced bool
	// vinix.max_cstate=N: keep the first N states. Zero is no limit.
	limit int
}

pub struct MwaitState {
pub mut:
	name                string
	desc                string
	hint                u32
	exit_latency_us     u32
	target_residency_us u32
	flags               u32
}

pub struct MwaitTable {
pub mut:
	driver string
	// Why the table is what it is, for the log.
	reason string
	count  int
	states [max_states]MwaitState
}

fn (mut t MwaitTable) put(name string, desc string, hint u32, exit_latency_us u32, target_residency_us u32, flags u32) {
	if t.count >= max_states {
		return
	}
	t.states[t.count] = MwaitState{
		name:                name
		desc:                desc
		hint:                hint
		exit_latency_us:     exit_latency_us
		target_residency_us: target_residency_us
		flags:               flags
	}
	t.count++
}

// How many sub-states CPUID.5:EDX gives the C-state `hint` names. The nibble
// for MWAIT C-state n is n + 1, C0's being the first.
pub fn mwait_substates(substates u32, hint u32) u32 {
	// Parenthesised: V gives >> and * the same precedence, where the C this is
	// taken from shifts by the product.
	nibble := ((hint >> 4) & 0xf) + 1
	return (substates >> (nibble * 4)) & 0xf
}

// intel_idle.c's table for an Intel family 6 `model`, C1 first, or false when
// it has none that is copied here. Models whose entry there says use_acpi --
// the servers, where firmware decides which states are allowed -- are not: a
// table without that say-so would overrule it.
fn intel_model_states(model u32, mut t MwaitTable) bool {
	deep := state_mwait | state_masked
	match model {
		// nehalem_cstates: NEHALEM, NEHALEM_G, WESTMERE.
		0x1e, 0x1f, 0x25 {
			t.put('C1', 'MWAIT 0x00', 0x00, 3, 6, deep)
			t.put('C1E', 'MWAIT 0x01', 0x01, 10, 20, deep)
			t.put('C3', 'MWAIT 0x10', 0x10, 20, 80, deep)
			t.put('C6', 'MWAIT 0x20', 0x20, 200, 800, deep)
		}
		// snb_cstates: SANDYBRIDGE.
		0x2a {
			t.put('C1', 'MWAIT 0x00', 0x00, 2, 2, deep)
			t.put('C1E', 'MWAIT 0x01', 0x01, 10, 20, deep)
			t.put('C3', 'MWAIT 0x10', 0x10, 80, 211, deep)
			t.put('C6', 'MWAIT 0x20', 0x20, 104, 345, deep)
			t.put('C7', 'MWAIT 0x30', 0x30, 109, 345, deep)
		}
		// ivb_cstates: IVYBRIDGE.
		0x3a {
			t.put('C1', 'MWAIT 0x00', 0x00, 1, 1, deep)
			t.put('C1E', 'MWAIT 0x01', 0x01, 10, 20, deep)
			t.put('C3', 'MWAIT 0x10', 0x10, 59, 156, deep)
			t.put('C6', 'MWAIT 0x20', 0x20, 80, 300, deep)
			t.put('C7', 'MWAIT 0x30', 0x30, 87, 300, deep)
		}
		// hsw_cstates: HASWELL, HASWELL_L, HASWELL_G.
		0x3c, 0x45, 0x46 {
			t.put('C1', 'MWAIT 0x00', 0x00, 2, 2, deep)
			t.put('C1E', 'MWAIT 0x01', 0x01, 10, 20, deep)
			t.put('C3', 'MWAIT 0x10', 0x10, 33, 100, deep)
			t.put('C6', 'MWAIT 0x20', 0x20, 133, 400, deep)
			t.put('C7s', 'MWAIT 0x32', 0x32, 166, 500, deep)
			t.put('C8', 'MWAIT 0x40', 0x40, 300, 900, deep)
			t.put('C9', 'MWAIT 0x50', 0x50, 600, 1800, deep)
			t.put('C10', 'MWAIT 0x60', 0x60, 2600, 7700, deep)
		}
		// bdw_cstates: BROADWELL, BROADWELL_G.
		0x3d, 0x47 {
			t.put('C1', 'MWAIT 0x00', 0x00, 2, 2, deep)
			t.put('C1E', 'MWAIT 0x01', 0x01, 10, 20, deep)
			t.put('C3', 'MWAIT 0x10', 0x10, 40, 100, deep)
			t.put('C6', 'MWAIT 0x20', 0x20, 133, 400, deep)
			t.put('C7s', 'MWAIT 0x32', 0x32, 166, 500, deep)
			t.put('C8', 'MWAIT 0x40', 0x40, 300, 900, deep)
			t.put('C9', 'MWAIT 0x50', 0x50, 600, 1800, deep)
			t.put('C10', 'MWAIT 0x60', 0x60, 2600, 7700, deep)
		}
		// skl_cstates: SKYLAKE_L, SKYLAKE, KABYLAKE_L, KABYLAKE. Without its
		// C8, C9 and C10: which of those may be used there depends on the
		// package C-state limit and on SGX (sklh_idle_state_table_update()),
		// neither of which is looked at here.
		0x4e, 0x5e, 0x8e, 0x9e {
			t.put('C1', 'MWAIT 0x00', 0x00, 2, 2, deep)
			t.put('C1E', 'MWAIT 0x01', 0x01, 10, 20, deep)
			t.put('C3', 'MWAIT 0x10', 0x10, 70, 100, deep)
			t.put('C6', 'MWAIT 0x20', 0x20, 85, 200, deep)
			t.put('C7s', 'MWAIT 0x33', 0x33, 124, 800, deep)
		}
		else {
			return false
		}
	}
	return true
}

// C1, C1E, C3 and C6 for an Intel family 6 model with no table, each with the
// slowest figures the tables above have for it.
fn intel_generic_states(mut t MwaitTable) {
	deep := state_mwait | state_masked
	t.put('C1', 'MWAIT 0x00', 0x00, 3, 6, deep)
	t.put('C1E', 'MWAIT 0x01', 0x01, 10, 20, deep)
	t.put('C3', 'MWAIT 0x10', 0x10, 80, 211, deep)
	t.put('C6', 'MWAIT 0x20', 0x20, 200, 800, deep)
}

// The states to offer on the processor `c` describes, and the driver's name:
// "halt" when MWAIT is not to be used, "mwait" when it is.
pub fn mwait_table(c MwaitCpu) MwaitTable {
	mut t := MwaitTable{
		driver: 'halt'
	}
	c1_substates := (c.substates >> 4) & 0xf
	extensions := c.extensions & leaf5_extensions != 0
	if !c.monitor || !c.leaf5 {
		t.reason = 'no MONITOR/MWAIT'
	} else if extensions && c1_substates == 0 && !c.forced {
		// With the extensions there should be a C1 sub-state. Linux prefers
		// HLT when there is not (prefer_mwait_c1_over_halt()), and so does
		// this: it is what an emulator that implements MWAIT as a mere pause
		// reports, where an idle CPU would spin.
		t.reason = 'CPUID.5 enumerates no C1 sub-state'
	} else {
		t.driver = 'mwait'
	}
	if t.driver == 'halt' {
		// Linux's figures for a C1 entered by HLT (processor_idle.c).
		t.put('C1', 'HLT', 0, 1, 1, 0)
		return limited(t, c.limit)
	}

	// Masked entry needs the extensions to be real: enumerated, with the
	// interrupt-break bit, and with the C1 sub-state that says the leaf
	// describes this processor.
	masked := extensions && c.extensions & leaf5_interrupt_break != 0 && c1_substates != 0
	if !masked {
		// MWAIT as it was first defined, no hints and no extensions, entered
		// as HLT is: `sti; mwait`.
		t.reason = if c.forced && extensions && c1_substates == 0 {
			'forced by vinix.cpuidle=mwait'
		} else {
			'MWAIT without interrupt-break'
		}
		t.put('C1', 'MWAIT 0x00', 0x00, 3, 6, state_mwait)
		return limited(t, c.limit)
	}

	mut candidates := MwaitTable{}
	mut generic := false
	if c.intel && c.family == 6 {
		if intel_model_states(c.model, mut candidates) {
			t.reason = 'intel_idle table for this model'
		} else {
			intel_generic_states(mut candidates)
			generic = true
			t.reason = 'generic Intel states from CPUID.5'
		}
	} else {
		candidates.put('C1', 'MWAIT 0x00', 0x00, 3, 6, state_mwait | state_masked)
		t.reason = if c.amd { 'AMD: deeper states need ACPI _CST' } else { 'C1 only' }
	}
	timers_survive := c.arat && c.nonstop_tsc
	for i in 0 .. candidates.count {
		s := candidates.states[i]
		if i > 0 {
			if !timers_survive {
				break
			}
			if mwait_substates(c.substates, s.hint) == 0 {
				continue
			}
			// C1E is the second sub-state of C1. A table says the model has
			// it; without one, CPUID has to.
			if s.hint == 0x01 && generic && c1_substates < 2 {
				continue
			}
		}
		t.put(s.name, s.desc, s.hint, s.exit_latency_us, s.target_residency_us, s.flags)
	}
	if !timers_survive && candidates.count > 1 {
		t.reason = if !c.arat {
			'C1 only: the APIC timer stops in deeper states'
		} else {
			'C1 only: the TSC stops in deeper states'
		}
	}
	return limited(t, c.limit)
}

fn limited(table MwaitTable, limit int) MwaitTable {
	mut t := table
	if limit > 0 && t.count > limit {
		t.count = limit
	}
	return t
}
