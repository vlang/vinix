// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module migrationfixture

#include "linuxkpi_migration_fixture_v_contract.h"

struct C.completion {}

fn C.migrate_disable()
fn C.migrate_enable()
fn C.schedule_timeout_uninterruptible(i64) i64
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.wait_for_completion(&C.completion)

@[export: 'vinix_linuxkpi_migration_fixture_disable']
pub fn disable() {
	C.migrate_disable()
}

@[export: 'vinix_linuxkpi_migration_fixture_enable']
pub fn enable() {
	C.migrate_enable()
}

@[export: 'vinix_linuxkpi_migration_fixture_sleep']
pub fn sleep(ticks i64) i64 {
	return C.schedule_timeout_uninterruptible(ticks)
}

@[export: 'vinix_linuxkpi_migration_fixture_init_completion']
pub fn init_completion(storage voidptr) {
	unsafe { C.init_completion(&C.completion(storage)) }
}

@[export: 'vinix_linuxkpi_migration_fixture_complete']
pub fn complete(storage voidptr) {
	unsafe { C.complete(&C.completion(storage)) }
}

@[export: 'vinix_linuxkpi_migration_fixture_wait']
pub fn wait(storage voidptr) {
	unsafe { C.wait_for_completion(&C.completion(storage)) }
}
