// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn contraction_key(member int, kind u32) DiskKey {
	mut key := DiskKey{bytes: 65536, sector: if member & 1 == 0 { u64(4096) } else { u64(512) },
		kind: if member & 1 == 0 { u32(3) - kind } else { kind }}
	key.id[0] = u8(member); if key.kind == 2 { key.id[15] = 0x55 }; return key
}

fn contraction_fixture(mut set PlanSet, contracted u32, kind u32) {
	for member in [10, 1, 2, 11, 3, 4]! {
		mut plan := Plan{key: contraction_key(member, kind)}
		if member < 10 {
			plan.count = 1; plan.rows[0] = Request{slot: u32(member - 1), offset: 8192, length: 8192, flags: u64(member & 1)}
			if member == 1 { plan.count = 2; plan.rows[1] = Request{slot: 63, length: 4096, flags: 1} }
		}
		assert append_plan(mut set, &plan)
	}
	for member in [4, 2, 1, 3]! {
		disk := if member < 3 { member } else { member + 1 }
		region := PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: 8192,
			end: if contracted & (u32(1) << (member - 1)) != 0 { u64(24576) } else { u64(32768) }, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
		other := PoolRegion{pool: 4, disk: u32(disk), window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}
		assert bundle_pool_add(mut set, &other)
	}
	set.plans[1].rows[63] = Request{slot: 61, length: 99}; set.plans[63].key.id[0] = 77; set.windows[63] = PoolRegion{pool: 62}
}

fn test_contraction_subsets_match_independent_end_action_and_priority_oracles() {
	mut attempts := 0
	for kind in [u32(1), 2] {
		for reverse in [false, true] {
			for contracted in u32(0) .. 16 {
				for requested in u32(0) .. 16 {
					mut set := PlanSet{}; contraction_fixture(mut set, contracted, kind); original := set; mut expected := set
					mut batch := PoolContractionBatch{}; mut wanted := PoolContractionResults{}
					for ordinal in 0 .. 4 {
						member := if reverse { 4 - ordinal } else { ordinal + 1 }
						if requested & (u32(1) << (member - 1)) == 0 { continue }
						disk := if member < 3 { member } else { member + 1 }; at := batch.count
						batch.keys[at] = original.plans[disk].key; batch.ends[at] = 24576; batch.count++
						for region in 0 .. expected.regions {
							row := expected.windows[region]; if row.pool != 3 || row.disk != u32(disk) { continue }
							wanted.previous[at] = row.window.end
							expected.windows[region] = PoolRegion{pool: 3, disk: row.disk, window: SpaceWindow{start: row.window.start, end: 24576, alignment: row.window.alignment}}
							wanted.rows[at] = expected.windows[region]
						}
					}
					mut result := PoolContractionResults{count: 77}; result.previous[63] = 99; result.rows[63].disk = 55
					if requested == 0 {
						before := result; assert !bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == original && result == before
					} else {
						wanted.count = batch.count
						assert bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == expected && result == wanted
						for i in 0 .. wanted.count { wanted.previous[i] = 24576 }
						assert bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == expected && result == wanted
					}
					attempts++
				}
			}
		}
	}
	assert attempts == 1024
}

fn test_later_contraction_identity_membership_bounds_and_occupied_tail_failures_roll_back_all_fields() {
	mut baseline := PlanSet{}; contraction_fixture(mut baseline, 0, 1)
	for mode in 0 .. 14 {
		mut set := baseline; mut batch := PoolContractionBatch{count: 2}
		batch.keys[0] = set.plans[1].key; batch.ends[0] = 24576; batch.keys[1] = set.plans[2].key; batch.ends[1] = 24576
		match mode {
			0 { batch.count = -1 }
			1 { batch.count = 0 }
			2 { batch.count = 65 }
			3 { batch.keys[1].id[0] = 99 }
			4 { batch.keys[1] = batch.keys[0]; batch.keys[1].bytes *= 2 }
			5 { batch.keys[1] = set.plans[0].key }
			6 { batch.keys[1] = DiskKey{} }
			7 { batch.ends[1] = 0 }
			8 { batch.ends[1] = 4096 }
			9 { batch.ends[1] = 8192 }
			10 { batch.ends[1] = 12288 }
			11 { batch.ends[1] = 24577 }
			12 { batch.ends[1] = 65536 }
			else { batch.ends[1] = u64(-1) }
		}
		mut result := PoolContractionResults{count: 77}; result.rows[63].disk = 55; result.previous[63] = 99; before := result
		assert !bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == baseline && result == before
	}
	mut set := baseline; mut batch := PoolContractionBatch{count: 1}; batch.keys[0] = set.plans[1].key; batch.ends[0] = 24576
	mut result := PoolContractionResults{count: 9}
	assert !bundle_pool_contract_batch(mut set, 64, &batch, mut result) && set == baseline && result == PoolContractionResults{count: 9}
	assert !bundle_pool_contract_batch(mut set, 5, &batch, mut result) && set == baseline
	mut alias := Plan{key: set.plans[1].key}; alias.key.bytes *= 2; assert append_plan(mut set, &alias); ambiguous := set
	assert !bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == ambiguous && result == PoolContractionResults{count: 9}
	set = baseline; set.plans[0].key.kind = 3; invalid := set
	assert !bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == invalid
}

fn test_contraction_protects_clipped_mapping_intersections_and_uses_saved_sector_geometry_after_compaction() {
	mut set := PlanSet{}; mut plan := Plan{key: contraction_key(1, 1), count: 1}
	plan.rows[0] = Request{slot: 1, offset: 4096, length: 8704, flags: 1}; assert append_plan(mut set, &plan)
	region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 8192, end: 32768, alignment: 4096}}; assert bundle_pool_add(mut set, &region)
	mut batch := PoolContractionBatch{count: 1}; batch.keys[0] = plan.key; batch.ends[0] = 12800
	mut result := PoolContractionResults{}; assert bundle_pool_contract_batch(mut set, 3, &batch, mut result)
	assert result.rows[0].window.end == 12800 && set.plans[0] == plan // Sector-aligned end need not align to allocation alignment.
	contracted := set; batch.ends[0] = 12288
	assert !bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == contracted
	set.plans[0].rows[0] = Request{slot: 1, offset: 28672, length: 8192, flags: 1}; set.windows[0] = region
	clipped := set; batch.ends[0] = 28672
	assert !bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == clipped
	batch.ends[0] = 32768; assert bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == clipped
	set = PlanSet{}; contraction_fixture(mut set, 0, 1); batch.count = 2
	batch.keys[0] = set.plans[1].key; batch.keys[0].bytes *= 2; batch.keys[0].sector = 4096; batch.ends[0] = 25088
	batch.keys[1] = set.plans[2].key; batch.ends[1] = 24576
	assert bundle_pool_contract_batch(mut set, 3, &batch, mut result) && result.rows[0].disk == 1 && result.rows[1].disk == 2
	assert bundle_forget_disk(mut set, 0); compacted := set
	assert bundle_pool_contract_batch(mut set, 3, &batch, mut result) && set == compacted && result.rows[0].disk == 0 && result.rows[1].disk == 1
}

fn test_full_132_argument_contraction_cli_preserves_full_v2_sets_and_durable_equal_end_retries() {
	work := os.join_path(os.temp_dir(), 'vinix-contraction-full-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut set := PlanSet{}
	for disk in 0 .. 64 {
		mut plan := Plan{key: contraction_key(disk + 1, 1), count: 1}
		plan.key.bytes = u64(-1) & ~u64(4095); plan.rows[0] = Request{slot: u32(disk), offset: plan.key.bytes - 16384, length: 4096, flags: u64(disk & 1)}
		assert append_plan(mut set, &plan)
	}
	for disk in 0 .. 64 {
		end := set.plans[disk].key.bytes; region := PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: end - 16384, end: end, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!; assert original.len == 8768
	mut expected := set; mut values := []string{cap: 128}
	for ordinal in 0 .. 64 {
		disk := 63 - ordinal; row := set.windows[disk]; end := row.window.end - 8192
		expected.windows[disk] = PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: row.window.start, end: end, alignment: row.window.alignment}}
		mut identity := [41]char{}; disk_identity(&set.plans[disk].key, &identity[0]); values << unsafe { cstring_to_vstring(&identity[0]) }; values << end.str()
	}
	unsafe {
		mut args := [133]&char{}; args[0] = &char(c'vinix-volume'); args[2] = path.str; args[3] = &char(c'3')
		for i in 0 .. values.len { args[4 + i] = values[i].str }
		args[1] = &char(c'pool-preview-contract-batch'); assert run(132, &args[0]) == 0 && os.read_bytes(path)! == original
		args[1] = &char(c'pool-contract-batch'); assert run(132, &args[0]) == 0
		current := os.read_bytes(path)!; mut decoded := PlanSet{}; assert current.len == 8768 && decode_bundle(current.data, current.len, mut decoded) && decoded == expected
		assert run(132, &args[0]) == 0 && os.read_bytes(path)! == current
		args[131] = &char(c'1'); assert run(132, &args[0]) == 1 && os.read_bytes(path)! == current
	}
}

fn test_contraction_sources_and_later_cli_tokens_fail_without_publication_prefixes() {
	work := os.join_path(os.temp_dir(), 'vinix-contraction-cli-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut set := PlanSet{}; contraction_fixture(mut set, 0, 1)
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!; os.symlink(path, work + '/alias')!
	mut batch := PoolContractionBatch{count: 1}; batch.keys[0] = set.plans[1].key; batch.ends[0] = 24576
	for preview in [false, true] { for bad in [work + '/missing', work, work + '/alias'] { assert contract_batch_pool_plan(bad.str, 3, &batch, preview) == 1 } }
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-contract-batch'), path.str, &char(c'3'),
			&char(c'mbr:00000001'), &char(c'24576'), &char(c'gpt:00000002-0000-0000-0000-000000000055'), &char(c'24576'), &char(nil)]!
		for command in [c'pool-contract-batch', c'pool-preview-contract-batch'] {
			args[1] = &char(command); for count in [2, 3, 5, 7, 133, 400] { assert run(count, &args[0]) == 2 }
			for at in [3, 6, 7] { previous := args[at]; args[at] = &char(c'bad'); assert run(8, &args[0]) == 2 && os.read_bytes(path)! == original; args[at] = previous }
			args[3] = &char(c'64'); assert run(8, &args[0]) == 2; args[3] = &char(c'3')
			for invalid in [c'0', c'18446744073709551616'] { args[7] = &char(invalid); assert run(8, &args[0]) == 2 }; args[7] = &char(c'24576')
		}
	}
	assert os.read_bytes(path)! == original && os.ls(work)!.len == 2
	os.write_file(path, 'bad bundle')!; assert contract_batch_pool_plan(path.str, 3, &batch, false) == 1 && os.read_file(path)! == 'bad bundle'
}
