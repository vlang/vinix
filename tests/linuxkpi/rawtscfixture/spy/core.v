// SPDX-License-Identifier: GPL-2.0-or-later
// Independent raw instruction and CPU feature observations; no TSC algorithm.
@[has_globals]
module rawtscspy

#include "contract.h"

fn C.printf(&char, ...)

@[noreturn]
fn C.exit(i32)

__global (
	spy_timestamp       u64
	spy_feature_present bool
	spy_read_count      u32
	spy_query_count     u32
)

pub fn configure(next u64, present bool) {
	spy_timestamp = next
	spy_feature_present = present
	spy_read_count = 0
	spy_query_count = 0
}

pub fn read() u64 {
	spy_read_count++
	return spy_timestamp
}

@[export: 'vinix_linuxkpi_cpu_has']
pub fn feature(bit u32) bool {
	require(bit == 4, 7)
	spy_query_count++
	return spy_feature_present
}

pub fn read_count() u32 { return spy_read_count }

pub fn query_count() u32 { return spy_query_count }

pub fn require(valid bool, code i32) {
	if !valid {
		C.printf(c'FAIL: raw TSC condition %d\n', code)
		C.exit(1)
	}
}
