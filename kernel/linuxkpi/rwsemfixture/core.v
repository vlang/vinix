// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module rwsemfixture

#include "linuxkpi_rwsem_fixture_v_contract.h"

struct C.list_head {
	next &C.list_head
	prev &C.list_head
}
@[typedef]
struct C.atomic_long_t {}
@[typedef]
struct C.raw_spinlock_t {}
struct C.rw_semaphore {
	count C.atomic_long_t
	owner C.atomic_long_t
	wait_lock C.raw_spinlock_t
	wait_list C.list_head
}
struct C.completion {}
fn C.init_rwsem(&C.rw_semaphore)
fn C.down_read(&C.rw_semaphore)
fn C.down_read_interruptible(&C.rw_semaphore) i32
fn C.down_read_killable(&C.rw_semaphore) i32
fn C.down_read_non_owner(&C.rw_semaphore)
fn C.down_write(&C.rw_semaphore)
fn C.down_write_killable(&C.rw_semaphore) i32
fn C.down_read_trylock(&C.rw_semaphore) i32
fn C.down_write_trylock(&C.rw_semaphore) i32
fn C.up_read(&C.rw_semaphore)
fn C.up_read_non_owner(&C.rw_semaphore)
fn C.up_write(&C.rw_semaphore)
fn C.downgrade_write(&C.rw_semaphore)
fn C.atomic_long_read(&C.atomic_long_t) isize
fn C.raw_spin_lock_irqsave(&C.raw_spinlock_t, usize)
fn C.raw_spin_unlock_irqrestore(&C.raw_spinlock_t, usize)
fn C.init_completion(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.kzalloc(usize, u32) voidptr
fn C.kfree(voidptr)
@[c_extern]
__global C.vinix_rwsem_fixture_static C.rw_semaphore
@[c_extern]
__global C.GFP_KERNEL u32

@[export: 'vinix_linuxkpi_rwsem_fixture_static']
pub fn static_storage() voidptr { return unsafe { &C.vinix_rwsem_fixture_static } }
@[export: 'vinix_linuxkpi_rwsem_fixture_init']
pub fn init(storage voidptr) { unsafe { C.init_rwsem(&C.rw_semaphore(storage)) } }
@[export: 'vinix_linuxkpi_rwsem_fixture_read']
pub fn read(storage voidptr, mode u32) i32 {
	unsafe {
		sem := &C.rw_semaphore(storage)
		if mode == 1 { return C.down_read_interruptible(sem) }
		if mode == 2 { return C.down_read_killable(sem) }
		if mode == 3 { C.down_read_non_owner(sem) } else { C.down_read(sem) }
		return 0
	}
}
@[export: 'vinix_linuxkpi_rwsem_fixture_write']
pub fn write(storage voidptr, killable bool) i32 {
	unsafe {
		sem := &C.rw_semaphore(storage)
		if killable { return C.down_write_killable(sem) }
		C.down_write(sem)
		return 0
	}
}
@[export: 'vinix_linuxkpi_rwsem_fixture_try']
pub fn try_lock(storage voidptr, writer bool) i32 {
	unsafe {
		sem := &C.rw_semaphore(storage)
		return if writer { C.down_write_trylock(sem) } else { C.down_read_trylock(sem) }
	}
}
@[export: 'vinix_linuxkpi_rwsem_fixture_up']
pub fn up(storage voidptr, mode u32) {
	unsafe {
		sem := &C.rw_semaphore(storage)
		if mode == 1 { C.up_write(sem) }
		else if mode == 2 { C.up_read_non_owner(sem) }
		else { C.up_read(sem) }
	}
}
@[export: 'vinix_linuxkpi_rwsem_fixture_downgrade']
pub fn downgrade(storage voidptr) { unsafe { C.downgrade_write(&C.rw_semaphore(storage)) } }
// The original wait lock protects list traversal; no waiter pointer escapes.
@[export: 'vinix_linuxkpi_rwsem_fixture_value']
pub fn value(storage voidptr, field u32) i64 {
	unsafe {
		sem := &C.rw_semaphore(storage)
		mut flags := usize(0)
		C.raw_spin_lock_irqsave(&sem.wait_lock, flags)
		mut result := i64(0)
		if field == 0 { result = C.atomic_long_read(&sem.count) }
		else if field == 1 { result = C.atomic_long_read(&sem.owner) }
		else {
			for node := sem.wait_list.next; node != &sem.wait_list; node = node.next { result++ }
		}
		C.raw_spin_unlock_irqrestore(&sem.wait_lock, flags)
		return result
	}
}
@[export: 'vinix_linuxkpi_rwsem_fixture_init_completion']
pub fn init_completion(storage voidptr) { unsafe { C.init_completion(&C.completion(storage)) } }
@[export: 'vinix_linuxkpi_rwsem_fixture_complete']
pub fn complete(storage voidptr) { unsafe { C.complete_all(&C.completion(storage)) } }
@[export: 'vinix_linuxkpi_rwsem_fixture_wait']
pub fn wait(storage voidptr) { unsafe { C.wait_for_completion(&C.completion(storage)) } }
@[export: 'vinix_linuxkpi_rwsem_fixture_alloc']
pub fn alloc() voidptr {
	storage := C.kzalloc(sizeof(C.rw_semaphore), C.GFP_KERNEL)
	if storage != unsafe { nil } { init(storage) }
	return storage
}
@[export: 'vinix_linuxkpi_rwsem_fixture_free']
pub fn free(storage voidptr) { C.kfree(storage) }
