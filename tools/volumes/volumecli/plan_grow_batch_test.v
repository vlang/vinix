// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn explicit_growth_key(member int, kind u32) DiskKey {
	mut key := DiskKey{bytes: 65536, sector: if member == 2 { u64(4096) } else { u64(512) },
		kind: if member == 2 { u32(3) - kind } else { kind }}
	key.id[0] = u8(member); if key.kind == 2 { key.id[15] = 0x55 }
	return key
}

fn explicit_growth_fixture(mut set PlanSet, grown u32, kind u32) {
	for member in [10, 1, 11, 2]! {
		mut plan := Plan{key: explicit_growth_key(member, kind)}
		if member == 1 { plan.count = 1; plan.rows[0] = Request{slot: 63, length: 4096, flags: 1} }
		assert append_plan(mut set, &plan)
	}
	for member in [2, 0, 3, 1]! {
		row := Request{slot: u32(member), offset: 8192 + u64(member / 2) * 16384,
			length: if grown & (u32(1) << member) != 0 { u64(8192) } else { u64(4096) }, flags: u64(member & 1)}
		assert bundle_add_row(mut set, if member & 1 == 0 { 1 } else { 3 }, &row)
	}
	for disk in [u32(3), 1]! {
		region := PoolRegion{pool: 3, disk: disk, window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	set.plans[1].rows[63] = Request{slot: 61, length: 99}
	set.plans[63].key.id[0] = 77; set.windows[63] = PoolRegion{pool: 62}
}

fn test_explicit_growth_subsets_match_independent_length_and_action_oracles() {
	mut attempts := 0
	for kind in [u32(1), 2] {
		for reverse in [false, true] {
			for grown in u32(0) .. 16 {
				for requested in u32(0) .. 16 {
					mut set := PlanSet{}; explicit_growth_fixture(mut set, grown, kind)
					original := set; mut expected := set
					mut batch := MappingGrowthBatch{}; mut wanted := MappingGrowthResults{}
					for ordinal in 0 .. 4 {
						member := if reverse { 3 - ordinal } else { ordinal }
						if requested & (u32(1) << member) == 0 { continue }
						at := batch.count; disk := if member & 1 == 0 { 1 } else { 3 }
						batch.keys[at] = original.plans[disk].key; batch.slots[at] = u32(member); batch.lengths[at] = 8192; batch.count++
						wanted.disks[at] = u32(disk)
						for row := u32(0); row < expected.plans[disk].count; row++ {
							if expected.plans[disk].rows[row].slot != u32(member) { continue }
							wanted.previous[at] = expected.plans[disk].rows[row].length
							expected.plans[disk].rows[row].length = 8192; wanted.rows[at] = expected.plans[disk].rows[row]
						}
					}
					mut results := MappingGrowthResults{count: 77}; results.disks[63] = 55; results.previous[63] = 99
					if requested == 0 {
						previous := results
						assert !bundle_grow_batch(mut set, &batch, mut results) && set == original && results == previous
					} else {
						wanted.count = batch.count
						assert bundle_grow_batch(mut set, &batch, mut results) && set == expected && results == wanted
						for i in 0 .. wanted.count { wanted.previous[i] = 8192 }
						assert bundle_grow_batch(mut set, &batch, mut results) && set == expected && results == wanted
					}
					attempts++
				}
			}
		}
	}
	assert attempts == 1024
}

fn test_later_growth_identity_slot_shrink_overlap_alignment_and_overflow_roll_back_every_field() {
	mut baseline := PlanSet{}; explicit_growth_fixture(mut baseline, 2, 1)
	for mode in 0 .. 12 {
		mut set := baseline; mut batch := MappingGrowthBatch{count: 2}
		batch.keys[0] = set.plans[1].key; batch.slots[0] = 0; batch.lengths[0] = 8192
		batch.keys[1] = set.plans[3].key; batch.slots[1] = 1; batch.lengths[1] = 8192
		match mode {
			0 { batch.count = -1 }
			1 { batch.count = 0 }
			2 { batch.count = 65 }
			3 { batch.keys[1].id[0] = 99 }
			4 { batch.keys[1] = batch.keys[0] }
			5 { batch.slots[1] = 0 }
			6 { batch.slots[1] = 64 }
			7 { batch.slots[1] = 55 }
			8 { batch.lengths[1] = 4096 }
			9 { batch.lengths[1] = 8193 }
			10 { batch.lengths[1] = u64(-1) }
			else { batch.lengths[1] = 0 }
		}
		mut result := MappingGrowthResults{count: 77}; result.disks[63] = 55; result.previous[63] = 99
		previous := result
		assert !bundle_grow_batch(mut set, &batch, mut result) && set == baseline && result == previous
	}
	mut set := baseline; mut batch := MappingGrowthBatch{count: 2}
	batch.keys[0] = set.plans[1].key; batch.slots[0] = 0; batch.lengths[0] = 8192
	batch.keys[1] = set.plans[3].key; batch.slots[1] = 1; batch.lengths[1] = 20480
	mut result := MappingGrowthResults{count: 9}
	assert !bundle_grow_batch(mut set, &batch, mut result) && set == baseline && result == MappingGrowthResults{count: 9}
	mut alias := Plan{key: set.plans[1].key}; alias.key.bytes *= 2; assert append_plan(mut set, &alias)
	ambiguous := set; batch.lengths[1] = 8192
	assert !bundle_grow_batch(mut set, &batch, mut result) && set == ambiguous && result == MappingGrowthResults{count: 9}
	set = baseline; batch.keys[1] = DiskKey{}
	assert !bundle_grow_batch(mut set, &batch, mut result) && set == baseline
	set.plans[0].key.kind = 3; invalid := set
	assert !bundle_grow_batch(mut set, &batch, mut result) && set == invalid
}

fn test_growth_identity_follows_compaction_and_uses_sector_alignment_outside_pool_windows() {
	mut set := PlanSet{}; explicit_growth_fixture(mut set, 0, 1)
	mut batch := MappingGrowthBatch{count: 2}
	batch.keys[0] = set.plans[1].key; batch.keys[0].bytes *= 2; batch.keys[0].sector = 4096
	batch.slots[0] = 0; batch.lengths[0] = 4608
	batch.keys[1] = set.plans[3].key; batch.slots[1] = 1; batch.lengths[1] = 8192
	mut result := MappingGrowthResults{}
	assert bundle_grow_batch(mut set, &batch, mut result) && result.disks[0] == 1 && result.disks[1] == 3
	assert result.rows[0].length == 4608 && result.rows[1].flags == 1
	assert bundle_forget_disk(mut set, 0); compacted := set
	assert bundle_grow_batch(mut set, &batch, mut result) && set == compacted && result.disks[0] == 0 && result.disks[1] == 2
	assert result.previous[0] == 4608 && result.previous[1] == 8192
}

fn test_full_195_argument_growth_cli_preserves_v2_limit_and_equal_size_retries() {
	work := os.join_path(os.temp_dir(), 'vinix-explicit-growth-full-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut set := PlanSet{}
	for disk in 0 .. 64 {
		mut plan := Plan{key: explicit_growth_key(disk + 1, if disk & 1 == 0 { u32(1) } else { u32(2) }), count: 1}
		plan.key.bytes = u64(-1) & ~u64(4095)
		plan.rows[0] = Request{slot: u32(disk), offset: plan.key.bytes - 8192, length: 4096, flags: u64(disk & 1)}
		assert append_plan(mut set, &plan)
	}
	for pool in 0 .. 64 {
		end := set.plans[0].key.bytes - u64(pool) * 4096
		region := PoolRegion{pool: u32(pool), disk: 0, window: SpaceWindow{start: end - 4096, end: end, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!; assert original.len == 8768
	mut values := []string{cap: 192}; mut expected := set
	for ordinal in 0 .. 64 {
		disk := 63 - ordinal; expected.plans[disk].rows[0].length = 8192
		mut identity := [41]char{}; disk_identity(&set.plans[disk].key, &identity[0])
		values << unsafe { cstring_to_vstring(&identity[0]) }; values << disk.str(); values << '8192'
	}
	unsafe {
		mut args := [196]&char{}; args[0] = &char(c'vinix-volume'); args[2] = path.str
		for i in 0 .. values.len { args[3 + i] = values[i].str }
		args[1] = &char(c'plan-preview-grow-batch'); assert run(195, &args[0]) == 0 && os.read_bytes(path)! == original
		args[1] = &char(c'plan-grow-batch'); assert run(195, &args[0]) == 0
		current := os.read_bytes(path)!; mut decoded := PlanSet{}
		assert current.len == 8768 && decode_bundle(current.data, current.len, mut decoded) && decoded == expected
		assert run(195, &args[0]) == 0 && os.read_bytes(path)! == current
		args[194] = &char(c'4096'); assert run(195, &args[0]) == 1 && os.read_bytes(path)! == current
	}
}

fn test_invalid_growth_sources_counts_and_later_cli_tokens_never_publish_prefixes() {
	work := os.join_path(os.temp_dir(), 'vinix-explicit-growth-cli-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut set := PlanSet{}; explicit_growth_fixture(mut set, 0, 1)
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!; os.symlink(path, work + '/alias')!
	mut batch := MappingGrowthBatch{count: 1}; batch.keys[0] = set.plans[1].key; batch.slots[0] = 0; batch.lengths[0] = 8192
	for preview in [false, true] {
		for bad in [work + '/missing', work, work + '/alias'] { assert grow_batch_bundle_plan(bad.str, &batch, preview) == 1 }
	}
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-grow-batch'), path.str,
			&char(c'mbr:00000001'), &char(c'0'), &char(c'8192'),
			&char(c'gpt:00000002-0000-0000-0000-000000000055'), &char(c'1'), &char(c'8192'), &char(nil)]!
		for command in [c'plan-grow-batch', c'plan-preview-grow-batch'] {
			args[1] = &char(command)
			for count in [2, 3, 5, 7, 196, 400] { assert run(count, &args[0]) == 2 }
			for at in 6 .. 9 {
				previous := args[at]; args[at] = &char(c'bad')
				assert run(9, &args[0]) == 2 && os.read_bytes(path)! == original; args[at] = previous
			}
			for invalid in [c'0', c'18446744073709551616'] { args[8] = &char(invalid); assert run(9, &args[0]) == 2 }
			args[8] = &char(c'8192')
		}
	}
	assert os.read_bytes(path)! == original && os.ls(work)!.len == 2
	os.write_file(path, 'bad bundle')!; assert grow_batch_bundle_plan(path.str, &batch, false) == 1 && os.read_file(path)! == 'bad bundle'
}
