// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module smp

import limine

// Ask Limine to start the secondary cores. Compiled only with -d limine_mp;
// request_notd_limine_mp.v explains why that is not the default.
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
