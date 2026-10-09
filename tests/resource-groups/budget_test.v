module kbudget

import cgcontrol

fn test_orphaned_objects_and_migration_rollback() {
	configure(64 * 1024 * 1024)
	mut parent := cgcontrol.Group{memory_max: 4096}
	mut left := cgcontrol.Group{parent: unsafe { &parent }}
	mut right := cgcontrol.Group{parent: unsafe { &parent }, memory_max: 1024}
	owner := open_owner()?
	assert bind_group(owner, unsafe { &left }, 0)
	mut charge := reserve(owner, .socket, 2048)?
	assert !bind_group(owner, unsafe { &right }, 0)
	assert cgcontrol.snapshot(unsafe { &left }).kernel == 2048
	assert cgcontrol.snapshot(unsafe { &right }).kernel == 0
	shrink(mut charge, 1536)
	assert bind_group(owner, unsafe { &right }, 0)
	assert cgcontrol.snapshot(unsafe { &left }).kernel == 0
	assert cgcontrol.snapshot(unsafe { &right }).kernel == 512
	assert grow(mut charge, 512)
	assert !grow(mut charge, 1)
	close_owner(owner)
	assert cgcontrol.snapshot(unsafe { &right }).kernel == 1024
	release(charge)
	assert cgcontrol.snapshot(unsafe { &parent }).kernel == 0
	assert cgcontrol.snapshot(unsafe { &right }).kernel == 0
	assert snapshot().accounts == 0
}

fn test_exited_thread_keeps_physical_budget_but_releases_group_quota() {
	configure(64 * 1024 * 1024)
	mut left := cgcontrol.Group{memory_max: 2048}
	mut right := cgcontrol.Group{memory_max: 1024}
	owner := open_owner()?
	assert bind_group(owner, unsafe { &left }, 0)
	mut stack := reserve(owner, .thread, 2048)?
	assert !bind_group(owner, unsafe { &right }, 0)
	retire_thread_group(mut stack)
	retire_thread_group(mut stack)
	assert cgcontrol.snapshot(unsafe { &left }).kernel == 0
	assert snapshot().bytes == 2048
	assert bind_group(owner, unsafe { &right }, 0)
	mut object := reserve(owner, .ipc, 1024)?
	assert cgcontrol.snapshot(unsafe { &right }).kernel == 1024
	shrink(mut stack, 512)
	assert grow(mut stack, 512)
	release(stack)
	assert cgcontrol.snapshot(unsafe { &right }).kernel == 1024
	close_owner(owner)
	release(object)
	assert snapshot().bytes == 0
	assert snapshot().accounts == 0
}
