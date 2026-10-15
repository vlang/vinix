// SPDX-License-Identifier: GPL-2.0-or-later
// Typed public Linux ABI; the native sleeping algorithm uses private views.
@[translated]
module headercore

#include "linuxkpi_rwsem_v_contract.h"

struct C.rw_semaphore {}
struct C.lock_class_key {}

fn C.vrs_init(voidptr)
fn C.vrs_down_read(voidptr, u32) i32
fn C.vrs_down_write(voidptr, u32) i32
fn C.vrs_try_read(voidptr) i32
fn C.vrs_try_write(voidptr) i32
fn C.vrs_up_read(voidptr)
fn C.vrs_up_write(voidptr)
fn C.vrs_downgrade(voidptr)

@[export: '__init_rwsem']
pub fn rwsem_init(sem &C.rw_semaphore, _name C.vkh_const_char_p, _key &C.lock_class_key) {
	C.vrs_init(sem)
}

@[export: 'down_read']
pub fn rwsem_down_read(sem &C.rw_semaphore) {
	C.vrs_down_read(sem, 2)
}

@[export: 'down_read_interruptible']
pub fn rwsem_down_read_interruptible(sem &C.rw_semaphore) i32 {
	return C.vrs_down_read(sem, 1)
}

@[export: 'down_read_killable']
pub fn rwsem_down_read_killable(sem &C.rw_semaphore) i32 {
	return C.vrs_down_read(sem, 0x102)
}

@[export: 'down_read_trylock']
pub fn rwsem_down_read_trylock(sem &C.rw_semaphore) i32 {
	return C.vrs_try_read(sem)
}

@[export: 'down_write']
pub fn rwsem_down_write(sem &C.rw_semaphore) {
	C.vrs_down_write(sem, 2)
}

@[export: 'down_write_killable']
pub fn rwsem_down_write_killable(sem &C.rw_semaphore) i32 {
	return C.vrs_down_write(sem, 0x102)
}

@[export: 'down_write_trylock']
pub fn rwsem_down_write_trylock(sem &C.rw_semaphore) i32 {
	return C.vrs_try_write(sem)
}

@[export: 'up_read']
pub fn rwsem_up_read(sem &C.rw_semaphore) {
	C.vrs_up_read(sem)
}

@[export: 'up_write']
pub fn rwsem_up_write(sem &C.rw_semaphore) {
	C.vrs_up_write(sem)
}

@[export: 'downgrade_write']
pub fn rwsem_downgrade_write(sem &C.rw_semaphore) {
	C.vrs_downgrade(sem)
}
