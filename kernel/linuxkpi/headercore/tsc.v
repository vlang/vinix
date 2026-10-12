// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module headercore

#include "linuxkpi_tsc_v_contract.h"

@[typedef]
struct C.vkt_cycles {}

fn C.vinix_linuxkpi_raw_tsc() u64

// Original x86 rdtsc and cycles_t use unsigned long long, which need not have
// the native V u64 spelling. Copy all 64 bits through borrowed stack storage.
@[export: 'rdtsc']
pub fn rdtsc() C.vkt_cycles {
	value := C.vinix_linuxkpi_raw_tsc()
	mut result := C.vkt_cycles{}
	unsafe { C.memcpy(&result, &value, 8) }
	return result
}
