// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import x86.cpu

// Linux's raw rdtsc accessor has only the ordering of volatile RDTSC. The
// native instruction preserves EDX:EAX without changing IRQ or pin state.
@[export: 'vinix_linuxkpi_raw_tsc']
fn raw_tsc() u64 {
	return cpu.rdtsc()
}
