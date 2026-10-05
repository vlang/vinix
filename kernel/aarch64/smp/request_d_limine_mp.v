// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module smp

import limine

// Ask Limine to start the secondary cores. Compiled only with -d limine_mp;
// M1 deployment pairs this with the pinned VHE-aware Limine 12.8 loader and
// the kernel leaves every AP above its two-CPU hardware limit parked.
@[_linker_section: '.requests']
@[cinit]
__global (
	volatile smp_req = limine.LimineSMPRequest{
		flags:    0
		response: unsafe { nil }
	}
)

fn limine_response() &limine.LimineSMPResponse {
	return smp_req.response
}
