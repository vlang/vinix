// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module syspower

import x86.cpu
import x86.msr

const msr_efer = u32(0xc0000080)

// The control registers that hold a CPU's protections: write protection of
// kernel pages (CR0.WP), supervisor execution and access prevention and
// user-mode instruction prevention (CR4.SMEP, SMAP, UMIP), and no-execute
// (EFER.NXE). A CPU that comes back from a sleep without one of them runs the
// same kernel with a hole in it and gives no sign, so they are recorded
// before the sleep and compared after it.
//
// The speculation controls are not here: they are per-CPU registers the
// mitigation code applies when a CPU starts, which is also where a CPU that
// lost power in a deep sleep gets them back.
pub struct SecurityState {
pub:
	cr0  u64
	cr4  u64
	efer u64
}

fn platform_security_state() SecurityState {
	return SecurityState{
		cr0:  cpu.read_cr0()
		cr4:  cpu.read_cr4()
		efer: msr.rdmsr(msr_efer)
	}
}

fn platform_security_restore(state SecurityState) {
	msr.wrmsr(msr_efer, state.efer)
	cpu.write_cr4(state.cr4)
	cpu.write_cr0(state.cr0)
}

fn security_changed(before SecurityState) bool {
	now := platform_security_state()
	return now.cr0 != before.cr0 || now.cr4 != before.cr4 || now.efer != before.efer
}
