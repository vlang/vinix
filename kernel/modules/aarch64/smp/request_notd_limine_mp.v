// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module smp

import limine

// No Limine MP request in the default build. On Apple Silicon the request is
// not merely useless, it is what keeps the machine on a black screen:
//
// Limine 9.3.0 releases each secondary core through the device tree's
// spin-table and runs its AP trampoline at EL2, where it writes the EL1 page
// table registers by their EL1 names. Apple cores have HCR_EL2.E2H fixed at 1
// (Linux arch/arm64/kernel/head.S calls them "fruity CPUs" for it), so under
// VHE those writes land in the EL2 registers instead, and the trampoline turns
// the EL2 MMU on with page tables that do not map the trampoline. The core
// faults forever and never sets the booted flag. Limine then waits for it:
// 1,000,000 polls of delay(100000) on a 24 MHz counter is about 69 minutes per
// core, times seven cores, all of it after the screen has been cleared and
// boot services have been exited. The kernel is entered after roughly eight
// hours.
//
// The kernel does not need the request on Apple hardware, where the AIC path
// runs on CPU 0 alone. The QEMU runners build with LIMINE_MP=1, which supplies
// -d limine_mp and lets QEMU bring every configured virtual CPU online.
fn limine_response() &limine.LimineSMPResponse {
	return unsafe { nil }
}
