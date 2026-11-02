// SPDX-License-Identifier: GPL-2.0-or-later
// Genuine raw/cycle accessors; no ordering or cross-CPU equality assertion.
@[translated]
module tscfixture

#include "linuxkpi_tsc_fixture_v_contract.h"
@[typedef]
struct C.vkt_cycles {}
fn C.rdtsc() C.vkt_cycles
fn C.get_cycles() C.vkt_cycles
fn C.memcpy(voidptr, voidptr, uint) voidptr

@[export: 'vinix_linuxkpi_tsc_fixture_queries']
pub fn queries() i32 {
	raw := C.rdtsc()
	guarded := C.get_cycles()
	mut raw_bits := u64(0)
	mut guarded_bits := u64(0)
	unsafe {
		C.memcpy(&raw_bits, &raw, 8)
		C.memcpy(&guarded_bits, &guarded, 8)
	}
	// Native boot has already calibrated and used this machine's TSC. Host
// fixtures separately cover zero values and the absent-feature branch.
	return i32(raw_bits != 0 && guarded_bits != 0)
}
