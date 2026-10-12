// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn addition_key(member int, kind u32) DiskKey {
	mut key := DiskKey{bytes: 65536, sector: if member == 2 { u64(4096) } else { u64(512) },
		kind: if member == 2 { u32(3) - kind } else { kind }}
	key.id[0] = u8(member)
	if key.kind == 2 { key.id[15] = 0x55 }
	return key
}

fn addition_row(member int) Request {
	return Request{slot: u32(member), offset: u64(1 + member / 2) * 8192,
		length: 4096, flags: u64(member & 1)}
}

fn addition_fixture(mut set PlanSet, existing u32, kind u32) {
	for member in [10, 1, 11, 2]! {
		mut plan := Plan{key: addition_key(member, kind)}
		if member == 1 { plan.count = 1; plan.rows[0] = Request{slot: 63, length: 4096, flags: 1} }
		assert append_plan(mut set, &plan)
	}
	for member in [2, 0, 3, 1]! {
		if existing & (u32(1) << member) == 0 { continue }
		row := addition_row(member); assert bundle_add_row(mut set, if member & 1 == 0 { 1 } else { 3 }, &row)
	}
	for disk in [u32(3), 1]! {
		region := PoolRegion{pool: 3, disk: disk, window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	set.plans[1].rows[63] = Request{slot: 61, length: 99}
	set.plans[63].key.id[0] = 77; set.windows[63] = PoolRegion{pool: 62}
}

fn test_addition_subsets_preserve_order_and_match_independent_explicit_append_keep_oracles() {
	mut attempts := 0
	for kind in [u32(1), 2] {
		for reverse in [false, true] {
			for existing in u32(0) .. 16 {
				for requested in u32(0) .. 16 {
					mut set := PlanSet{}; addition_fixture(mut set, existing, kind)
					original := set; mut expected := set
					mut batch := MappingAdditionBatch{}; mut wanted := MappingAdditionResults{}
					for ordinal in 0 .. 4 {
						member := if reverse { 3 - ordinal } else { ordinal }
						if requested & (u32(1) << member) == 0 { continue }
						at := batch.count; target := if member & 1 == 0 { 1 } else { 3 }
						batch.rows[at] = addition_row(member); batch.keys[at] = original.plans[target].key; batch.count++
						wanted.disks[at] = u32(target)
						if existing & (u32(1) << member) != 0 { wanted.keep |= u64(1) << at }
						else {
							expected.plans[target].rows[expected.plans[target].count] = batch.rows[at]; expected.plans[target].count++
							expected.slots |= u64(1) << member
						}
					}
					mut results := MappingAdditionResults{count: 77, keep: u64(-1)}; results.disks[63] = 55
					if requested == 0 {
						previous := results
						assert !bundle_add_batch(mut set, &batch, mut results) && set == original && results == previous
					} else {
						wanted.count = batch.count
						assert bundle_add_batch(mut set, &batch, mut results) && set == expected && results == wanted
						assert bundle_add_batch(mut set, &batch, mut results) && set == expected && results.keep == (u64(1) << batch.count) - 1
						assert results.disks == wanted.disks
					}
					attempts++
				}
			}
		}
	}
	assert attempts == 1024
}

fn test_later_identity_slot_geometry_and_mode_conflicts_preserve_all_caller_fields() {
	mut baseline := PlanSet{}; addition_fixture(mut baseline, 2, 1)
	for mode in 0 .. 15 {
		mut set := baseline; mut batch := MappingAdditionBatch{count: 2}
		batch.keys[0] = set.plans[1].key; batch.rows[0] = addition_row(0)
		batch.keys[1] = set.plans[3].key; batch.rows[1] = addition_row(1)
		match mode {
			0 { batch.count = -1 }
			1 { batch.count = 0 }
			2 { batch.count = 65 }
			3 { batch.keys[1].id[0] = 99 }
			4 { batch.keys[1] = batch.keys[0] }
			5 { batch.rows[1].flags = 0 }
			6 { batch.rows[1].offset += 4096 }
			7 { batch.rows[1].length = 8192 }
			8 { batch.rows[1].slot = 0 }
			9 { batch.rows[1].slot = 64 }
			10 { batch.rows[1].version = 2 }
			11 { batch.rows[1].flags = 2 }
			12 { batch.rows[1].slot = 2; batch.rows[1].offset = 8193 }
			13 { batch.rows[1].slot = 2; batch.rows[1].offset = u64(-1) }
			else { batch.rows[1].length = 0 }
		}
		mut result := MappingAdditionResults{count: 77, keep: u64(-1)}; result.disks[63] = 55
		previous := result
		assert !bundle_add_batch(mut set, &batch, mut result) && set == baseline && result == previous
	}
	mut set := baseline; mut batch := MappingAdditionBatch{count: 2}
	batch.keys[0] = set.plans[1].key; batch.rows[0] = addition_row(0)
	batch.keys[1] = batch.keys[0]; batch.rows[1] = Request{slot: 2, offset: 8192, length: 4096}
	mut result := MappingAdditionResults{count: 9}
	assert !bundle_add_batch(mut set, &batch, mut result) && set == baseline && result == MappingAdditionResults{count: 9}
	mut alias := Plan{key: set.plans[1].key}; alias.key.bytes *= 2; assert append_plan(mut set, &alias)
	ambiguous := set
	assert !bundle_add_batch(mut set, &batch, mut result) && set == ambiguous && result == MappingAdditionResults{count: 9}
	set = baseline; set.plans[0].key.kind = 3; invalid := set
	assert !bundle_add_batch(mut set, &batch, mut result) && set == invalid
}

fn test_identity_retries_follow_compaction_and_explicit_extents_need_no_pool_alignment() {
	mut set := PlanSet{}; addition_fixture(mut set, 0, 1)
	mut batch := MappingAdditionBatch{count: 2}
	batch.keys[0] = set.plans[1].key; batch.keys[0].bytes *= 2; batch.keys[0].sector = 4096
	batch.rows[0] = Request{slot: 0, offset: 4608, length: 512}
	batch.keys[1] = set.plans[3].key; batch.rows[1] = addition_row(1)
	mut result := MappingAdditionResults{}
	assert bundle_add_batch(mut set, &batch, mut result) && result.disks[0] == 1 && result.disks[1] == 3 && result.keep == 0
	assert bundle_forget_disk(mut set, 0)
	compacted := set
	assert bundle_add_batch(mut set, &batch, mut result) && set == compacted && result.disks[0] == 0 && result.disks[1] == 2 && result.keep == 3
}

fn test_full_323_argument_cli_reaches_v2_limit_and_preserves_durable_keep_retries() {
	work := os.join_path(os.temp_dir(), 'vinix-addition-full-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut set := PlanSet{}
	for disk in 0 .. 64 {
		mut plan := Plan{key: addition_key(disk + 1, if disk & 1 == 0 { u32(1) } else { u32(2) })}
		plan.key.bytes = u64(-1) & ~u64(4095); assert append_plan(mut set, &plan)
	}
	for pool in 0 .. 64 {
		end := set.plans[0].key.bytes - u64(pool) * 4096
		region := PoolRegion{pool: u32(pool), disk: 0, window: SpaceWindow{start: end - 4096, end: end, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!; assert original.len == 6720
	mut values := []string{cap: 320}; mut expected := set
	for ordinal in 0 .. 64 {
		disk := 63 - ordinal; row := Request{slot: u32(ordinal), offset: set.plans[disk].key.bytes - 8192, length: 4096, flags: u64(ordinal & 1)}
		expected.plans[disk].rows[0] = row; expected.plans[disk].count = 1; expected.slots |= u64(1) << ordinal
		mut identity := [41]char{}; disk_identity(&set.plans[disk].key, &identity[0])
		values << unsafe { cstring_to_vstring(&identity[0]) }; values << ordinal.str(); values << row.offset.str()
		values << '4096'; values << if row.flags == 1 { 'ro' } else { 'rw' }
	}
	unsafe {
		mut args := [324]&char{}; args[0] = &char(c'vinix-volume'); args[2] = path.str
		for i in 0 .. values.len { args[3 + i] = values[i].str }
		args[1] = &char(c'plan-preview-add-batch'); assert run(323, &args[0]) == 0 && os.read_bytes(path)! == original
		args[1] = &char(c'plan-add-batch'); assert run(323, &args[0]) == 0
		current := os.read_bytes(path)!; mut decoded := PlanSet{}
		assert current.len == 8768 && decode_bundle(current.data, current.len, mut decoded) && decoded == expected
		assert run(323, &args[0]) == 0 && os.read_bytes(path)! == current
		args[322] = &char(c'invalid'); assert run(323, &args[0]) == 2 && os.read_bytes(path)! == current
	}
}

fn test_bad_sources_and_later_malformed_cli_tokens_never_publish_a_prefix() {
	work := os.join_path(os.temp_dir(), 'vinix-addition-cli-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut set := PlanSet{}; addition_fixture(mut set, 0, 1)
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!
	os.symlink(path, work + '/alias')!
	mut batch := MappingAdditionBatch{count: 1}; batch.keys[0] = set.plans[1].key; batch.rows[0] = addition_row(0)
	for preview in [false, true] {
		for bad in [work + '/missing', work, work + '/alias'] { assert add_batch_bundle_plan(bad.str, &batch, preview) == 1 }
	}
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-add-batch'), path.str,
			&char(c'mbr:00000001'), &char(c'0'), &char(c'8192'), &char(c'4096'), &char(c'rw'),
			&char(c'gpt:00000002-0000-0000-0000-000000000055'), &char(c'1'), &char(c'8192'), &char(c'4096'), &char(c'ro'), &char(nil)]!
		for command in [c'plan-add-batch', c'plan-preview-add-batch'] {
			args[1] = &char(command)
			for count in [2, 3, 7, 9, 324, 400] { assert run(count, &args[0]) == 2 }
			for at in 8 .. 13 {
				previous := args[at]; args[at] = &char(c'bad')
				assert run(13, &args[0]) == 2 && os.read_bytes(path)! == original; args[at] = previous
			}
			args[11] = &char(c'0'); assert run(13, &args[0]) == 2; args[11] = &char(c'4096')
			args[10] = &char(c'18446744073709551616'); assert run(13, &args[0]) == 2; args[10] = &char(c'8192')
		}
	}
	assert os.read_bytes(path)! == original && os.ls(work)!.len == 2
	os.write_file(path, 'bad bundle')!; assert add_batch_bundle_plan(path.str, &batch, false) == 1 && os.read_file(path)! == 'bad bundle'
}
