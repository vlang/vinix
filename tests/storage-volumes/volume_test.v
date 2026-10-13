module fs

import errno
import aesxts
import event.eventstruct
import file
import kbudget
import klock
import memory
import proc
import resource
import sched
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
	discard_calls  int
	discard_offset u64
	discard_bytes  u64
	no_data        bool
	short_read     bool
	short_write    bool
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
	mut snapshot := d.metrics.snapshot(u64(d.stat.size), u64(d.stat.blksize), if d.readonly {
		resource.block_readonly
	} else {
		u64(0)
	}, d.identity)
	if d.no_status { snapshot.version = 0 }
	snapshot.flags |= resource.block_discard
	return snapshot
}

fn (mut d Disk) read(_ voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if d.failed {
		errno.set(errno.eio)
		return none
	}
	if d.short_read { return i64(count / 2) }
	unsafe { C.memcpy(buffer, &d.bytes[loc], count) }
	return i64(count)
}

fn (mut d Disk) write(_ voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if d.failed {
		errno.set(errno.eio)
		return none
	}
	if d.short_write { return i64(count / 2) }
	unsafe { C.memcpy(&d.bytes[loc], buffer, count) }
	return i64(count)
}

fn (mut d Disk) sync(_ voidptr) ? {
	if d.failed {
		errno.set(errno.eio)
		return none
	}
}

fn (mut d Disk) discard(offset u64, bytes u64) ? {
	d.discard_calls++
	d.discard_offset = offset
	d.discard_bytes = bytes
	if d.failed { errno.set(errno.eio); return none }
	if !d.no_data { unsafe { C.memset(&d.bytes[offset], 0, bytes) } }
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

fn encryption_key() [64]u8 {
	mut key := [64]u8{}; for i in 0 .. 64 { key[i] = u8(i * 13 + 7) }; return key
}

fn test_encrypted_mapper_ciphertext_sectors_growth_errors_key_erasure_and_balanced_cycles() {
	before := memory.live; budget := kbudget.host_budget_live
	mut disk, mut descriptor := fixture(700); key := encryption_key()
	for limit in 0 .. 2 {
		memory.left = limit; assert create_encrypted_volume(mut descriptor, VolumeRequest{version: 1, slot: 60, offset: 512, length: 2048}, unsafe { &key }) or { -1 } == -1
		assert logical_volumes[60] == unsafe { nil } && disk.refcount == 1 && memory.live == before && kbudget.host_budget_live == budget
	}
	memory.left = -1
	reject_publication = true; assert create_encrypted_volume(mut descriptor, VolumeRequest{version: 1, slot: 60, offset: 512, length: 2048}, unsafe { &key }) or { -1 } == -1
	reject_publication = false; assert memory.live == before && kbudget.host_budget_live == budget && disk.refcount == 1
	mut repeated := [64]u8{}; assert create_encrypted_volume(mut descriptor, VolumeRequest{version: 1, slot: 60, length: 2048}, unsafe { &repeated }) or { -1 } == -1
	for _ in 0 .. 200 {
		assert create_encrypted_volume(mut descriptor, VolumeRequest{version: 1, slot: 60, offset: 512, length: 2048}, unsafe { &key }) or { -1 } == 0
		mut volume := logical_volumes[60]; assert volume.encrypted && block_encryption_used()
		status := volume.block_status(); assert status.flags & resource.block_encrypted != 0 && status.flags & resource.block_discard == 0
		mut plain := [1024]u8{init: 0x73}; original := plain; mut got := [1024]u8{}
		memory.check_zero_size = 512; memory.check_zero_failed = false; frees := memory.check_zero_frees
		assert volume.write(unsafe { nil }, &plain[0], 0, 1024) or { -1 } == 1024 && plain == original
		assert volume.read(unsafe { nil }, &got[0], 0, 1024) or { -1 } == 1024 && got == plain
		assert disk.bytes[0] == 0 && disk.bytes[1536] == 0
		mut differs := false; mut sectors_differ := false
		for i in 0 .. 512 { if disk.bytes[512 + i] != plain[i] { differs = true }; if disk.bytes[512 + i] != disk.bytes[1024 + i] { sectors_differ = true } }; assert differs && sectors_differ
		assert memory.check_zero_frees == frees + 2 && !memory.check_zero_failed
		generation := volume.generation; assert change_logical_volume(mut volume, volume_resize, VolumeRequest{version: 1, length: 4096}) or { -1 } == 0
		assert volume.generation == generation && volume.read(unsafe { nil }, &got[0], 0, 1024) or { -1 } == 1024 && got == plain
		disk.failed = true; got = [1024]u8{init: 0x81}; sentinel := got
		assert volume.read(unsafe { nil }, &got[0], 0, 512) or { -1 } == -1 && got == sentinel
		assert volume.write(unsafe { nil }, &plain[0], 0, 512) or { -1 } == -1 && plain == original
		disk.failed = false; disk.short_read = true; assert volume.read(unsafe { nil }, &got[0], 0, 512) or { -1 } == -1 && got == sentinel
		disk.short_read = false; disk.short_write = true; assert volume.write(unsafe { nil }, &plain[0], 0, 512) or { -1 } == -1 && plain == original; disk.short_write = false
		memory.left = 0; assert volume.write(unsafe { nil }, &plain[0], 0, 512) or { -1 } == -1; memory.left = -1
		kbudget.host_budget_deny = true; assert volume.read(unsafe { nil }, &got[0], 0, 512) or { -1 } == -1; kbudget.host_budget_deny = false
		volume.discard(0, 512) or {}; assert errno.get() == errno.eopnotsupp && disk.discard_calls == 0
		assert !memory.check_zero_failed; memory.check_zero_size = 0
		// Keep one explicit owner through node/table retirement to inspect the
		// cleared schedule and prove old descriptors cannot use the key.
		mut held := volume.open_owned(resource.o_rdonly) or { panic('hold encrypted mapping') }
		assert change_logical_volume(mut volume, volume_remove, VolumeRequest{}) or { -1 } == 0
		assert volume.cipher == aesxts.Cipher{} && volume.read(unsafe { nil }, &got[0], 0, 512) or { -1 } == -1
		assert errno.get() == errno.enodev; resource.release_resource(mut held)
		assert disk.refcount == 1 && memory.live == before && kbudget.host_budget_live == budget
	}
}

fn test_encrypted_ioctl_authorization_request_bounds_readonly_native_4096_and_reopen() {
	before := memory.live; budget := kbudget.host_budget_live
	mut disk, mut descriptor := fixture(701); key := encryption_key(); mut request := EncryptedVolumeRequest{data: VolumeRequest{version: 1, slot: 61, length: 4096}, key: key}
	proc.admin = false; assert storage_ioctl(mut descriptor, volume_create_encrypted, unsafe { &request }) or { -1 } == -1 && errno.get() == errno.eperm; proc.admin = true
	assert storage_ioctl(mut descriptor, volume_create_encrypted, unsafe { nil }) or { -1 } == -1 && errno.get() == errno.efault
	request.data.version = 2; assert storage_ioctl(mut descriptor, volume_create_encrypted, unsafe { &request }) or { -1 } == -1; request.data.version = 1
	disk.stat.blksize = 4096; request.data.flags = 1
	assert storage_ioctl(mut descriptor, volume_create_encrypted, unsafe { &request }) or { -1 } == 0
	mut volume := logical_volumes[61]; mut plain := [4096]u8{init: 0x65}
	assert volume.write(unsafe { nil }, &plain[0], 0, 4096) or { -1 } == -1 && errno.get() == errno.erofs
	assert change_logical_volume(mut volume, volume_remove, VolumeRequest{}) or { -1 } == 0
	request.data.flags = 0; assert storage_ioctl(mut descriptor, volume_create_encrypted, unsafe { &request }) or { -1 } == 0
	volume = logical_volumes[61]; assert volume.write(unsafe { nil }, &plain[0], 0, 4096) or { -1 } == 4096; volume.sync(unsafe { nil }) or { assert false }
	assert change_logical_volume(mut volume, volume_remove, VolumeRequest{}) or { -1 } == 0
	assert storage_ioctl(mut descriptor, volume_create_encrypted, unsafe { &request }) or { -1 } == 0
	volume = logical_volumes[61]; mut got := [4096]u8{}; assert volume.read(unsafe { nil }, &got[0], 0, 4096) or { -1 } == 4096 && got == plain
	assert change_logical_volume(mut volume, volume_remove, VolumeRequest{}) or { -1 } == 0
	assert memory.live == before && kbudget.host_budget_live == budget && disk.refcount == 1 && block_encryption_used()
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

fn test_discard_bounds_translation_permissions_and_reservation_cleanup() {
	mut disk, mut descriptor := fixture(109)
	mut range := [u64(512), u64(512)]!
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == 0
	assert disk.discard_calls == 1 && disk.discard_offset == 512 && disk.discard_bytes == 512
	for invalid in [u64(0), 511, u64(-1), 8192] {
		range[1] = invalid
		assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
	}
	assert disk.discard_calls == 1
	range[1] = 512
	proc.admin = false
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
	proc.admin = true
	descriptor.handle.flags = resource.o_rdonly
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
	descriptor.handle.flags = resource.o_rdwr
	disk.readonly = true
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
	disk.readonly = false
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, unsafe { nil }) or { -1 } == -1
	security.host_securelevel = 2
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
	security.host_securelevel = 0
	assert create_logical_volume(mut descriptor, VolumeRequest{version: 1, slot: 9, offset: 1024, length: 1024}) or { -1 } == 0
	mut volume := logical_volumes[9]
	mut handle := file.Handle{resource: volume.box, flags: resource.o_rdwr}
	mut view := file.FD{handle: &handle}
	assert storage_ioctl(mut view, resource.block_discard_ioctl, &range[0]) or { -1 } == 0
	assert disk.discard_offset == 1536 && disk.discard_bytes == 512
	disk.failed = true
	assert storage_ioctl(mut view, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
	assert volume.block_status().errors == 1
	disk.failed = false
	assert change_logical_volume(mut volume, volume_remove, VolumeRequest{}) or { -1 } == 0
	mount := security.begin_block_mount(disk.identity) or { panic('leaked reservation') }
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
	security.finish_block_mount(mount, true)
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
}

fn test_large_discard_yields_cancels_and_releases_the_whole_extent() {
	mut disk, mut descriptor := fixture(110)
	disk.no_data = true
	disk.stat.size = 131072
	disk.identity = resource.BlockIdentity{is_block: true, disk_id: 110, length: 131072}
	mut range := [u64(0), u64(131072)]!
	sched.host_yield_hook = fn () { proc.host_cancel(true) }
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
	assert errno.get() == errno.eintr && disk.discard_calls == 1 && disk.discard_bytes == 65536
	proc.host_cancel(false)
	token := security.begin_block_reconfigure(disk.identity) or { panic('cancel leaked reservation') }
	security.end_block_reconfigure(token)
	sched.host_yield_hook = fn () { security.host_securelevel = 2 }
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == -1
	assert errno.get() == errno.eperm && disk.discard_calls == 2
	security.host_securelevel = 0
	sched.host_yield_hook = fn () {}
	assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == 0
	assert disk.discard_calls == 4 && disk.discard_offset == 65536 && disk.discard_bytes == 65536
}

fn test_discard_batches_preserve_whole_logical_sectors() {
	expected_calls := [3, 100]!
	for index, sector in [u64(1536), u64(131072)]! {
		mut disk, mut descriptor := fixture(111)
		disk.no_data = true
		size := sector * 100
		disk.stat.size = i64(size)
		disk.stat.blksize = i64(sector)
		disk.identity = resource.BlockIdentity{is_block: true, disk_id: 111, length: size}
		mut range := [u64(0), size]!
		assert storage_ioctl(mut descriptor, resource.block_discard_ioctl, &range[0]) or { -1 } == 0
		assert disk.discard_calls == expected_calls[index]
		assert disk.discard_offset % sector == 0 && disk.discard_bytes % sector == 0
		assert disk.discard_offset + disk.discard_bytes == size
	}
}
