// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module smpfixture

#include "linuxkpi_smp_fixture_v_contract.h"

type Callback = fn (voidptr)
type Condition = fn (i32, voidptr) bool
@[typedef]
struct C.call_single_data_t {}
struct C.cpumask {}
@[c_extern]
__global C.cpu_online_mask &C.cpumask
fn C.smp_call_function_single(i32, Callback, voidptr, i32) i32
fn C.smp_call_function(Callback, voidptr, i32)
fn C.on_each_cpu_cond_mask(Condition, Callback, voidptr, bool, &C.cpumask)

// Only typed test call boundaries live here. The original declarations and
// actual production V implementations own stack records and queue algorithms.
@[export: 'vinix_linuxkpi_smp_fixture_csd_bytes']
pub fn csd_bytes() u32 { return u32(sizeof(C.call_single_data_t)) }

@[export: 'vinix_linuxkpi_smp_fixture_single']
pub fn single(cpu i32, callback Callback, info voidptr, wait i32) i32 {
	return C.smp_call_function_single(cpu, callback, info, wait)
}

@[export: 'vinix_linuxkpi_smp_fixture_many']
pub fn many(callback Callback, info voidptr, include_local bool, condition Condition) {
	if include_local {
		C.on_each_cpu_cond_mask(condition, callback, info, true, unsafe { C.cpu_online_mask })
	} else {
		C.smp_call_function(callback, info, 1)
	}
}
