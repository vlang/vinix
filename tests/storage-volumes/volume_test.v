module fs

import errno
import event.eventstruct
import file
import kbudget
import klock
import memory
import proc
import resource
import security
import stat

struct Disk {
mut:
	stat           stat.Stat
	refcount       int = 1
	l              klock.Lock
	event          eventstruct.Event
	status         int
	can_mmap       bool
	bytes          [8192]u8
	no_status      bool
	failed         bool
	readonly       bool
	identity       resource.BlockIdentity
	identity_calls int
	switch_at      int
	next_identity  resource.BlockIdentity
	metrics        resource.BlockMetrics
}

fn (d &Disk) block_identity() resource.BlockIdentity {
	mut current := unsafe { d }
	current.identity_calls++
	if current.switch_at != 0 && current.identity_calls == current.switch_at {
		current.identity = current.next_identity
	}
	return current.identity
}

fn (mut d Disk) block_status() resource.BlockStatus {
	mut snapshot := d.metrics.snapshot(8192, 512, if d.readonly {
		resource.block_readonly
	} else {
		u64(0)
	}, d.identity)
	if d.no_status { snapshot.version = 0 }
	return snapshot
}

fn (mut d Disk) read(_ voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if d.failed {
		errno.set(errno.eio)
		return none
	}
	unsafe { C.memcpy(buffer, &d.bytes[loc], count) }
	return i64(count)
}

fn (mut d Disk) write(_ voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if d.failed {
		errno.set(errno.eio)
		return none
	}
	unsafe { C.memcpy(&d.bytes[loc], buffer, count) }
	return i64(count)
}

fn (mut d Disk) sync(_ voidptr) ? {
	if d.failed {
		errno.set(errno.eio)
		return none
	}
}

fn (mut d Disk) unref(_ voidptr) ? { d.refcount-- }

fn (mut d Disk) ioctl(_ voidptr, _ u64, _ voidptr) ?int { return none }

fn (mut d Disk) grow(_ voidptr, _ u64) ? {}

fn (mut d Disk) link(_ voidptr) ? {}

fn (mut d Disk) unlink(_ voidptr) ? {}

fn (mut d Disk) mmap(_ voidptr, _ u64, _ int) voidptr { return unsafe { nil } }

fn fixture(id u64) (&Disk, &file.FD) {
	mut d := &Disk{
		stat:     stat.Stat{ size: 8192, blksize: 512, mode: stat.ifblk }
		identity: resource.BlockIdentity{ is_block: true, disk_id: id, start: 4096, length: 8192 }
	}
	security.register_block_device(d.identity)
	box := &resource.Resource(d)
	return d, &file.FD{ handle: &file.Handle{ resource: box, flags: resource.o_rdwr } }
}

fn test_extent_overflow_alignment_and_parent_offsets() {
	identity := resource.BlockIdentity{ is_block: true, disk_id: 1, start: u64(-1) - 8192, length: 8192 }
	assert volume_extent(identity, 512, 512, 512) or { panic('extent') }.start == u64(-1) - 7680
	for offset, length in {
		u64(-1):   u64(512)
		u64(8192): u64(512)
		u64(1):    u64(512)
		u64(0):    u64(0)
	} {
		mut failed := false
		volume_extent(identity, offset, length, 512) or { failed = true }
		assert failed
	}
}

fn test_mapping_growth_failure_health_and_final_ownership() {
	before := memory.live
	budget_before := kbudget.host_budget_live
	mut disk, mut descriptor := fixture(100)
	assert create_logical_volume(mut descriptor, VolumeRequest{ version: 1, slot: 0, offset: 512, length: 1024 }) or { -1 } == 0
	mut volume := logical_volumes[0]
	assert disk.refcount == 2
	mut bytes := [512]u8{init: 0x71}
	assert volume.write(unsafe { nil }, &bytes[0], 0, 512) or { -1 } == 512
	assert disk.bytes[0] == 0 && disk.bytes[512] == 0x71 && disk.bytes[1024] == 0
	mut got := [512]u8{}
	assert volume.read(unsafe { nil }, &got[0], 0, 512) or { -1 } == 512 && got == bytes
	for offset in [u64(-1), 1024, 1] {
		assert volume.read(unsafe { nil }, &got[0], offset, 512) or { -1 } == -1
	}
	assert change_logical_volume(mut volume, volume_resize, VolumeRequest{ version: 1, length: 2048 }) or { -1 } == 0
	assert volume.stat.size == 2048 && volume.identity.start == 4608
	volume.sync(unsafe { nil }) or { assert false }
	disk.failed = true
	assert volume.write(unsafe { nil }, &bytes[0], 0, 512) or { -1 } == -1
	volume.sync(unsafe { nil }) or {}
	status := volume.block_status()
	assert status.writes == 1 && status.reads == 1 && status.flushes == 1 && status.errors == 2 && status.last_error == errno.eio
	disk.failed = false
	assert change_logical_volume(mut volume, volume_remove, VolumeRequest{}) or { -1 } == 0
	assert logical_volumes[0] == unsafe { nil } && disk.refcount == 1 && memory.live == before && kbudget.host_budget_live == budget_before
}

fn test_overlap_readonly_oom_and_repeat_cycles_are_balanced() {
	before := memory.live
	budget_before := kbudget.host_budget_live
	mut disk, mut descriptor := fixture(101)
	for limit in 0 .. 2 {
		memory.left = limit
		assert create_logical_volume(mut descriptor, VolumeRequest{ version: 1, slot: 1, length: 1024 }) or { -1 } == -1
		assert logical_volumes[1] == unsafe { nil } && disk.refcount == 1 && memory.live == before && kbudget.host_budget_live == budget_before
	}
	memory.left = -1
	for _ in 0 .. 200 {
		assert create_logical_volume(mut descriptor, VolumeRequest{ version: 1, slot: 1, length: 1024, flags: 1 }) or { -1 } == 0
		mut volume := logical_volumes[1]
		mut bytes := [512]u8{}
		assert volume.write(unsafe { nil }, &bytes[0], 0, 512) or { -1 } == -1
		assert create_logical_volume(mut descriptor, VolumeRequest{ version: 1, slot: 2, offset: 512, length: 1024 }) or { -1 } == -1
		assert change_logical_volume(mut volume, volume_remove, VolumeRequest{}) or { -1 } == 0
		assert disk.refcount == 1
		assert kbudget.host_budget_live == budget_before
		assert memory.live == before
	}
}

fn test_reservations_exclude_mount_swap_and_alias_raw_writes() {
	mut disk, mut descriptor := fixture(102)
	token := security.begin_block_reconfigure(disk.identity) or { panic('reserve') }
	assert security.begin_user_device_write(mut descriptor.handle.resource) or { -2 } == -2
	assert security.begin_block_mount(disk.identity) or { -2 } == -2
	assert security.claim_swap(disk.identity) or { -2 } == -2
	security.end_block_reconfigure(token)
	write := security.begin_user_device_write(mut descriptor.handle.resource) or { panic('write') }
	assert security.begin_block_reconfigure(disk.identity) or { -2 } == -2
	security.end_user_device_write(write)
	mount := security.begin_block_mount(disk.identity) or { panic('mount') }
	assert security.begin_block_reconfigure(disk.identity) or { -2 } == -2
	security.finish_block_mount(mount, true)
	assert security.begin_block_reconfigure(disk.identity) or { -2 } == -2
}

fn test_ioctl_admin_version_and_fault_rejection() {
	_, mut descriptor := fixture(103)
	mut request := VolumeRequest{ version: 1, slot: 4, length: 1024 }
	proc.admin = false
	assert storage_ioctl(mut descriptor, volume_create, &request) or { -1 } == -1
	proc.admin = true
	assert storage_ioctl(mut descriptor, volume_create, unsafe { nil }) or { -1 } == -1
	request.version = 2
	assert storage_ioctl(mut descriptor, volume_create, &request) or { -1 } == -1
	mut status := resource.BlockStatus{}
	assert storage_ioctl(mut descriptor, resource.block_status_ioctl, &status) or { -1 } == 0 && status.bytes == 8192 && status.sector == 512
}

fn test_distinct_extents_reuse_bounded_policy_rows() {
	mut disk, mut descriptor := fixture(104)
	before := memory.live
	budget_before := kbudget.host_budget_live
	rows := security.host_policy_rows()
	for i in 0 .. 200 {
		offset := u64(i % 8) * 512
		length := u64((i / 8) % 8 + 1) * 512
		assert create_logical_volume(mut descriptor, VolumeRequest{ version: 1, slot: 5, offset: offset, length: length }) or { -1 } == 0
		mut volume := logical_volumes[5]
		assert change_logical_volume(mut volume, volume_remove, VolumeRequest{}) or { -1 } == 0
	}
	assert security.host_policy_rows() <= rows + 1
	assert kbudget.host_budget_live == budget_before
	assert memory.live == before && disk.refcount == 1
}

fn test_write_admission_retries_changed_geometry_without_leaking_tokens() {
	mut disk, mut descriptor := fixture(105)
	old := disk.identity
	next := resource.BlockIdentity{ is_block: true, disk_id: 105, start: 4096, length: 4096 }
	policy := security.register_dynamic_block_device(next) or { panic('policy') }
	disk.next_identity = next
	disk.switch_at = disk.identity_calls + 2
	token := security.begin_user_device_write(mut descriptor.handle.resource) or { panic('write') }
	assert disk.identity == next && disk.identity_calls >= disk.switch_at + 2
	security.end_user_device_write(token)
	reservation := security.begin_block_reconfigure(old) or { panic('leaked token') }
	security.end_block_reconfigure(reservation)
	security.release_dynamic_block_device(policy)
}

fn test_budget_denial_precedes_policy_and_allocation_admission() {
	_, mut descriptor := fixture(106)
	before := memory.live
	budget := kbudget.host_budget_live
	kbudget.host_budget_deny = true
	assert create_logical_volume(mut descriptor, VolumeRequest{ version: 1, slot: 6, length: 1024 }) or { -1 } == -1
	kbudget.host_budget_deny = false
	assert logical_volumes[6] == unsafe { nil } && memory.live == before && kbudget.host_budget_live == budget
}

fn test_failed_publication_rolls_back_parent_policy_and_charges() {
	mut disk, mut descriptor := fixture(107)
	before := memory.live
	budget := kbudget.host_budget_live
	reject_publication = true
	assert create_logical_volume(mut descriptor, VolumeRequest{ version: 1, slot: 7, length: 1024 }) or { -1 } == -1
	reject_publication = false
	assert logical_volumes[7] == unsafe { nil } && disk.refcount == 1 && memory.live == before && kbudget.host_budget_live == budget
	reservation := security.begin_block_reconfigure(disk.identity) or { panic('leaked policy reservation') }
	security.end_block_reconfigure(reservation)
}

fn test_unsupported_parent_status_fails_closed() {
	mut disk, mut descriptor := fixture(108)
	disk.no_status = true
	mut snapshot := resource.BlockStatus{}
	assert storage_ioctl(mut descriptor, resource.block_status_ioctl, &snapshot) or { -1 } == -1
	assert errno.get() == errno.enotty
	assert create_logical_volume(mut descriptor, VolumeRequest{ version: 1, slot: 8, length: 512 }) or { -1 } == -1
	assert logical_volumes[8] == unsafe { nil }
}
