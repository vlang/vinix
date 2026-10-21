// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module tlsprobe

#include "tls-abi.h"

@[c_extern]
__global C.fixture_tls u64

@[c_extern]
__global C.fixture_tls_bss u64

@[c_extern]
__global C.fixture_tls_weak u64

// Storage declarations live in a tiny generated ELF ABI fixture. All reads,
// writes and assertions are V; GCC emits real ARM64 TLSDESC relocations.
@[export: 'vinix_fixture_tls_read']
pub fn read_tls() u64 { return unsafe { C.fixture_tls } }

@[export: 'vinix_fixture_tls_write']
pub fn write_tls(value u64) {
	unsafe { C.fixture_tls = value }
}

@[export: 'vinix_fixture_tls_bss']
pub fn bss_tls() u64 {
	unsafe {
		old := C.fixture_tls_bss
		C.fixture_tls_bss = 71
		return old
	}
}

@[export: 'vinix_fixture_tls_weak']
pub fn weak_tls() usize { return usize(unsafe { &C.fixture_tls_weak }) }

@[export: 'vinix_fixture_tls_aligned']
pub fn aligned_tls() u8 {
	return u8(usize(unsafe { &C.fixture_tls }) % 64 == 0 && usize(unsafe { &C.fixture_tls_bss }) % 64 == 0)
}
