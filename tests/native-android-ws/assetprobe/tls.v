// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module assetprobe

#include <pthread.h>
#include "tls-abi.h"

@[c_extern]
__global C.fixture_tls u64
@[typedef]
struct C.pthread_t {}

fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, &voidptr) i32
fn C.vinix_fixture_tls_read() u64
fn C.vinix_fixture_tls_write(u64)
fn C.vinix_fixture_tls_bss() u64
fn C.vinix_fixture_tls_weak() usize
fn C.vinix_fixture_tls_aligned() u8

fn tls_thread(data voidptr) voidptr {
	unsafe {
		if C.vinix_fixture_tls_read() != 37 || C.vinix_fixture_tls_bss() != 0 || C.vinix_fixture_tls_aligned() != 1 {
			return nil
		}
		C.vinix_fixture_tls_write(99)
		return voidptr(usize(C.vinix_fixture_tls_read() == 99 && C.vinix_fixture_tls_bss() == 71))
	}
}

@[export: 'Java_org_vinix_bootstrap_Main_nativeTls']
pub fn tls_check(e voidptr, class voidptr) u8 {
	unsafe {
		if C.vinix_fixture_tls_read() != 37 || C.vinix_fixture_tls_bss() != 0
			|| C.vinix_fixture_tls_weak() != 0 || C.vinix_fixture_tls_aligned() != 1 {
			return 0
		}
		C.vinix_fixture_tls_write(42)
		if C.fixture_tls != 42 { return 0 }
		C.fixture_tls = 43
		if C.vinix_fixture_tls_read() != 43 { return 0 }
		mut threads := [8]C.pthread_t{}
		for i in 0 .. threads.len {
			if C.pthread_create(&threads[i], nil, tls_thread, nil) != 0 { return 0 }
		}
		for worker in threads {
			mut result := voidptr(nil)
			if C.pthread_join(worker, &result) != 0 || usize(result) != 1 { return 0 }
		}
		return u8(C.vinix_fixture_tls_read() == 43 && C.vinix_fixture_tls_bss() == 71)
	}
}
