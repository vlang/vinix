// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module cpubugfixture

#include "linuxkpi_cpu_bug_fixture_v_contract.h"

fn C.vcb_original_l1tf_query() bool
fn C.vcb_original_l1tf_bit() u32
fn C.schedule_timeout_uninterruptible(i64) i64

@[export: 'vinix_linuxkpi_cpu_bug_fixture_l1tf']
pub fn l1tf() bool {
	return C.vcb_original_l1tf_query()
}

@[export: 'vinix_linuxkpi_cpu_bug_fixture_bit']
pub fn bit() u32 {
	return C.vcb_original_l1tf_bit()
}

@[export: 'vinix_linuxkpi_cpu_bug_fixture_sleep']
pub fn sleep(ticks i64) i64 {
	return C.schedule_timeout_uninterruptible(ticks)
}
