// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn forget_key(member int, kind u32) DiskKey {
	mut key := DiskKey{bytes: 65536, sector: if member & 1 == 0 { u64(512) } else { u64(4096) }, kind: kind}
	key.id[0] = u8(member + 1)
	if kind == 2 { key.id[15] = 0xa7 }
	return key
}

fn forget_fixture(mut set PlanSet, present u32, kind u32) {
	for member in [2, 5, 0, 4, 3, 1]! {
		if member < 4 && present & (u32(1) << member) == 0 { continue }
		mut plan := Plan{key: forget_key(member, kind)}
		if member >= 4 { plan.count = 1; plan.rows[0] = Request{slot: u32(member), length: 4096, flags: u64(member & 1)} }
		plan.rows[63] = Request{slot: 61, length: 99}
		at := set.count; assert append_plan(mut set, &plan)
		if member >= 4 {
			region := PoolRegion{pool: 3, disk: u32(at), window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}
			assert bundle_pool_add(mut set, &region)
		}
	}
	set.plans[63].key.id[0] = 77; set.windows[63] = PoolRegion{pool: 62}
}

fn test_forget_subsets_match_independent_stable_compaction_and_pool_index_oracles() {
	mut attempts := 0
	for kind in [u32(1), 2] {
		for reverse in [false, true] {
			for present in u32(0) .. 16 {
				for requested in u32(0) .. 16 {
					mut set := PlanSet{}; forget_fixture(mut set, present, kind)
					original := set; mut expected := set
					mut batch := DiskForgetBatch{}
					mut wanted := DiskForgetResults{}
					for i in 0 .. 64 { wanted.disks[i] = u32(-1); wanted.retained[i] = u32(-1) }
					for ordinal in 0 .. 4 {
						member := if reverse { 3 - ordinal } else { ordinal }
						if requested & (u32(1) << member) == 0 { continue }
						at := batch.count; batch.keys[at] = forget_key(member, kind); batch.count++
						for disk in 0 .. original.count {
							if original.plans[disk].key.id[0] == u8(member + 1) { wanted.disks[at] = u32(disk); wanted.removed |= u64(1) << at }
						}
					}
					mut retained := 0
					for disk in 0 .. original.count {
						member := int(original.plans[disk].key.id[0]) - 1
						if member < 4 && requested & (u32(1) << member) != 0 { continue }
						wanted.retained[disk] = u32(retained); expected.plans[retained] = original.plans[disk]; retained++
					}
					for disk in retained .. original.count { expected.plans[disk] = Plan{} }
					expected.count = retained
					for at in 0 .. original.regions { expected.windows[at].disk = wanted.retained[original.windows[at].disk] }
					mut results := DiskForgetResults{count: 77, removed: u64(-1)}; results.retained[63] = 55
					if requested == 0 {
						previous := results
						assert !bundle_forget_batch(mut set, &batch, mut results) && set == original && results == previous
					} else {
						wanted.count = batch.count
						assert bundle_forget_batch(mut set, &batch, mut results) && set == expected && results == wanted
						assert bundle_forget_batch(mut set, &batch, mut results) && set == expected && results.removed == 0
						for disk in 0 .. set.count { assert results.retained[disk] == u32(disk) }
					}
					attempts++
				}
			}
		}
	}
	assert attempts == 1024
}

fn test_later_protected_duplicate_invalid_or_last_disk_requests_roll_back_every_field() {
	mut baseline := PlanSet{}; forget_fixture(mut baseline, 15, 1)
	for mode in 0 .. 9 {
		mut set := baseline; mut batch := DiskForgetBatch{count: 2}
		batch.keys[0] = forget_key(2, 1); batch.keys[1] = forget_key(0, 1)
		match mode {
			0 { batch.count = -1 }
			1 { batch.count = 0 }
			2 { batch.count = 65 }
			3 { batch.keys[1] = forget_key(5, 1) }
			4 { batch.keys[1] = batch.keys[0]; batch.keys[1].bytes *= 2 }
			5 { batch.keys[1].id[15] = 1 }
			6 { batch.keys[1].kind = 3 }
			7 { batch.keys[1].id = [16]u8{} }
			else {
				region := PoolRegion{pool: 4, disk: 2, window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}
				assert bundle_pool_add(mut set, &region)
			}
		}
		before := set; mut results := DiskForgetResults{count: 77, removed: u64(-1)}; results.disks[63] = 55
		previous := results
		assert !bundle_forget_batch(mut set, &batch, mut results) && set == before && results == previous
	}
	mut set := PlanSet{}; mut batch := DiskForgetBatch{count: 3}
	for i in 0 .. 3 { plan := Plan{key: forget_key(i, 2)}; assert append_plan(mut set, &plan); batch.keys[i] = plan.key }
	before := set; mut results := DiskForgetResults{count: 9}
	assert !bundle_forget_batch(mut set, &batch, mut results) && set == before && results == DiskForgetResults{count: 9}
	mut alias := set.plans[0]; alias.key.bytes *= 2; assert append_plan(mut set, &alias)
	ambiguous := set; batch.count = 1
	assert !bundle_forget_batch(mut set, &batch, mut results) && set == ambiguous && results == DiskForgetResults{count: 9}
	set = baseline; set.plans[0].key.kind = 3; invalid := set
	assert !bundle_forget_batch(mut set, &batch, mut results) && set == invalid
}

fn test_identity_parser_round_trips_all_guid_bytes_and_rejects_malformed_cli_before_io() {
	for kind in [u32(1), 2] {
		mut key := forget_key(0, kind)
		if kind == 2 { for i in 0 .. 16 { key.id[i] = u8(i * 17 + 3) } }
		mut text := [41]char{}; disk_identity(&key, &text[0])
		mut decoded := DiskKey{}
		assert parse_disk_identity(&text[0], mut decoded) && decoded.kind == key.kind && decoded.id == key.id
		for i in 0 .. 40 { if text[i] >= `a` && text[i] <= `f` && i >= 4 { text[i] = char(int(text[i]) - 32) } }
		assert parse_disk_identity(&text[0], mut decoded) && decoded.id == key.id
	}
	for text in ['', '0', 'mbr:00000000', 'mbr:1234567', 'mbr:123456789', 'mbr:1234567z', 'MBR:12345678',
		'gpt:00000000-0000-0000-0000-000000000000', 'gpt:01234567_89ab-cdef-0123-456789abcdef',
		'gpt:01234567-89ab-cdef-0123-456789abcdeg', 'gpt:0123456789abcdef0123456789abcdef',
		'gpt:01234567-89ab-cdef-0123-456789abcdefx'] {
		mut key := forget_key(8, 1); previous := key
		assert !parse_disk_identity(text.str, mut key) && key == previous
		unsafe {
			mut args := [&char(c'vinix-volume'), &char(c'plan-forget-batch'), &char(c'/absent'), &char(c'mbr:12345678'), text.str, &char(nil)]!
			for command in [c'plan-forget-batch', c'plan-preview-forget-batch'] {
				args[1] = &char(command)
				assert run(5, &args[0]) == 2
				for count in [2, 3, 68, 260] { assert run(count, &args[0]) == 2 }
			}
		}
	}
}

fn test_full_v2_64_identity_cli_compacts_63_disks_and_retries_without_selecting_survivor() {
	work := os.join_path(os.temp_dir(), 'vinix-forget-full-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}; mut names := []string{cap: 64}
	for disk in 0 .. 64 {
		mut plan := Plan{key: forget_key(disk, if disk & 1 == 0 { u32(1) } else { u32(2) })}
		if disk == 63 {
			plan.count = 64; plan.key.bytes = u64(-1) & ~u64(4095)
			for row in 0 .. 64 { plan.rows[row] = Request{slot: u32(row), offset: u64(row) * 4096, length: 4096, flags: u64(row & 1)} }
		}
		assert append_plan(mut set, &plan)
		mut text := [41]char{}; disk_identity(&plan.key, &text[0]); names << unsafe { cstring_to_vstring(&text[0]) }
	}
	for pool in 0 .. 64 {
		end := set.plans[63].key.bytes - u64(pool) * 4096
		region := PoolRegion{pool: u32(pool), disk: 63, window: SpaceWindow{start: end - 4096, end: end, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!; assert original.len == 8768
	mut expected := PlanSet{count: 1, slots: set.slots, regions: 64}; expected.plans[0] = set.plans[63]
	for at in 0 .. 64 { expected.windows[at] = set.windows[at]; expected.windows[at].disk = 0 }
	unsafe {
		mut args := [68]&char{}; args[0] = &char(c'vinix-volume'); args[2] = path.str
		for i in 0 .. 63 { args[3 + i] = names[62 - i].str }; args[66] = &char(c'mbr:ffffffff')
		args[1] = &char(c'plan-preview-forget-batch'); assert run(67, &args[0]) == 0 && os.read_bytes(path)! == original
		args[1] = &char(c'plan-forget-batch'); assert run(67, &args[0]) == 0
		current := os.read_bytes(path)!; mut decoded := PlanSet{}
		assert current.len == 4736
		assert decode_bundle(current.data, current.len, mut decoded)
		assert decoded == expected
		assert run(67, &args[0]) == 0 && os.read_bytes(path)! == current
	}
	os.symlink(path, work + '/alias')!
	mut batch := DiskForgetBatch{count: 1}; batch.keys[0] = forget_key(0, 1)
	for preview in [false, true] {
		for bad in [(work + '/missing'), work, (work + '/alias')] { assert forget_batch_bundle_plan(bad.str, &batch, preview) == 1 }
	}
	current := os.read_bytes(path)!; os.write_file(path, 'bad bundle')!
	assert forget_batch_bundle_plan(path.str, &batch, false) == 1 && os.read_file(path)! == 'bad bundle'
	assert current.len == 4736 && os.ls(work)!.len == 2
}
