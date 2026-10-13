// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_encrypted_boot_set_rejects_conflicts_without_changing_any_saved_key() {
	mut volumes := BootVolumeSet{}
	mut disk := DiskKey{bytes: u64(-1) & ~u64(4095), sector: 4096, kind: 2}; disk.id[0] = 1
	mut request := EncryptedRequest{data: Request{slot: 63, offset: disk.bytes - 8192, length: 4096}, key: [64]u8{init: u8(index * 13 + 7)}}
	assert append_boot_volume(mut volumes, &disk, &request)
	before := volumes
	assert boot_volume_collection_valid(&volumes)
	request.data.slot = 62
	for offset in [disk.bytes - 8192, disk.bytes - 4096] {
		request.data.offset = offset
		assert append_boot_volume(mut volumes, &disk, &request) == (offset == disk.bytes - 4096)
		if offset == disk.bytes - 8192 { assert volumes == before }
	}
	request.data.slot = 63; disk.id[0] = 2
	saved := volumes; assert !append_boot_volume(mut volumes, &disk, &request) && volumes == saved
	request.data.slot = 61; assert append_boot_volume(mut volumes, &disk, &request)
	mut plain := PlanSet{}
	assert boot_volumes_plain_compatible(&plain, &volumes)
	mut plan := Plan{key: disk, count: 1}; plan.rows[0] = Request{slot: 1, offset: request.data.offset, length: 4096}
	assert append_plan(mut plain, &plan)
	assert !boot_volumes_plain_compatible(&plain, &volumes)
	plan.key.id[0] = 3; plain = PlanSet{}; assert append_plan(mut plain, &plan)
	assert boot_volumes_plain_compatible(&plain, &volumes)
	plan.rows[0].slot = 61; plain = PlanSet{}; assert append_plan(mut plain, &plan)
	assert !boot_volumes_plain_compatible(&plain, &volumes)
}

fn test_encrypted_boot_set_full_width_bounds_and_all_64_global_slots() {
	mut volumes := BootVolumeSet{}
	mut disk := DiskKey{bytes: u64(-1) & ~u64(4095), sector: 4096, kind: 2}; disk.id[0] = 1
	for slot in 0 .. 64 {
		request := EncryptedRequest{data: Request{slot: u32(slot), offset: disk.bytes - u64(64 - slot) * 4096,
			length: 4096, flags: u64(slot & 1)}, key: [64]u8{init: u8(index + slot)}}
		assert append_boot_volume(mut volumes, &disk, &request)
	}
	assert volumes.count == 64 && volumes.slots == u64(-1) && boot_volume_collection_valid(&volumes)
	saved := volumes
	request := EncryptedRequest{data: Request{slot: 0, offset: 0, length: 4096}}
	assert !append_boot_volume(mut volumes, &disk, &request) && volumes == saved
	for count in [-1, 65] { volumes = saved; volumes.count = count; assert !boot_volume_collection_valid(&volumes) }
	volumes = saved; volumes.slots = 0; assert !boot_volume_collection_valid(&volumes)
	volumes = saved; volumes.rows[63].request.data.length = u64(-1); assert !boot_volume_collection_valid(&volumes)
	volumes = BootVolumeSet{}; volumes.opened = 1; assert !append_boot_volume(mut volumes, &disk, &request)
	mut plain := PlanSet{slots: 1}; volumes = BootVolumeSet{}; assert !boot_volumes_plain_compatible(&plain, &volumes)
	plain = PlanSet{}; assert boot_volumes_plain_compatible(&plain, &volumes)
}

fn test_encrypted_boot_set_selects_only_visible_nonempty_bounded_configuration_names() {
	unsafe {
		for name in [c'a.vcrypt', c'z.data.vcrypt', c'with space.vcrypt'] { assert boot_volume_filename(name) }
		for name in [c'.vcrypt', c'.hidden.vcrypt', c'data.pass', c'data.vcrypt.old', c''] { assert !boot_volume_filename(name) }
		mut name := [264]char{init: char(`a`)}; name[263] = 0
		C.memcpy(&name[256], c'.vcrypt', 7)
		assert !boot_volume_filename(&name[0])
	}
}
