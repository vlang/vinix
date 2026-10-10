// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module syspower

import aarch64.cpu

// The system registers that hold a CPU's protections: SCTLR_EL1 (write
// implies no-execute, privileged access never on exception entry, alignment
// and stack checks, the MMU and caches themselves) and TCR_EL1 (which half of
// the address space is whose, and whether user addresses may carry tags). A
// CPU that comes back from a sleep without one of them runs the same kernel
// with a hole in it and gives no sign, so they are recorded before the sleep
// and compared after it.
pub struct SecurityState {
pub:
	sctlr u64
	tcr   u64
}

fn platform_security_state() SecurityState {
	return SecurityState{
		sctlr: cpu.read_sctlr_el1()
		tcr:   cpu.read_tcr_el1()
	}
}

fn platform_security_restore(state SecurityState) {
	cpu.write_tcr_el1(state.tcr)
	cpu.write_sctlr_el1(state.sctlr)
}

fn security_changed(before SecurityState) bool {
	now := platform_security_state()
	return now.sctlr != before.sctlr || now.tcr != before.tcr
}
