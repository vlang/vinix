// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn members_fixture(mut set PlanSet, first_sector u64, second_sector u64, kind u32, present int) {
	for disk in 0 .. 2 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 32768,
			sector: if disk == 0 { first_sector } else { second_sector }, kind: if disk == 0 { kind } else { u32(3) - kind }}}
		plan.key.id[0] = u8(disk + 1)
		plan.rows[0] = Request{slot: u32(disk + 2), offset: 0, length: 8192, flags: u64(disk)}
		assert append_plan(mut set, &plan)
		other := PoolRegion{pool: 4, disk: u32(disk), window: SpaceWindow{start: 16384, end: 24576, alignment: 4096}}
		assert bundle_pool_add(mut set, &other)
	}
	for disk in [1, 0] {
		if present & (1 << disk) == 0 { continue }
		row := PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: 8192, end: 12288, alignment: 4096}}
		assert bundle_pool_add(mut set, &row)
	}
	set.plans[63].key.id[0] = 79
	set.windows[63] = PoolRegion{pool: 62}
}

fn test_membership_batches_match_independent_oracle_in_4096_add_and_remove_cases() {
	windows := [SpaceWindow{start: 0, end: 4096, alignment: 4096},
		SpaceWindow{start: 8192, end: 12288, alignment: 4096},
		SpaceWindow{start: 20480, end: 28672, alignment: 4096},
		SpaceWindow{start: 28672, end: 36864, alignment: 4096},
		SpaceWindow{start: 8192, end: 12288, alignment: 256},
		SpaceWindow{start: 512, end: 4096, alignment: 4096},
		SpaceWindow{start: 0, end: 4608, alignment: 4096},
		SpaceWindow{start: 8192, end: 12288, alignment: 0}]!
	for first_sector in [u64(512), 4096] {
		for second_sector in [u64(512), 4096] {
			for kind in [u32(1), 2] {
				for present in 0 .. 4 {
					mut baseline := PlanSet{}
					members_fixture(mut baseline, first_sector, second_sector, kind, present)
					for reverse in [false, true] {
						for first in 0 .. 8 {
							for second in 0 .. 8 {
								choices := [first, second]!
								mut batch := PoolMembersBatch{count: 2}
								mut valid := true
								mut changed := u64(0)
								mut expected := baseline
								for i in 0 .. 2 {
									disk := if reverse { 1 - i } else { i }
									window := windows[choices[disk]]
									batch.rows[i] = PoolRegion{pool: 3, disk: u32(disk), window: window}
									sector := if disk == 0 { first_sector } else { second_sector }
									member := present & (1 << disk) != 0
									// Bounds, sector/alignment and overlap are independent of the planner.
									valid = valid && if member { choices[disk] == 1 } else {
										window.start < window.end && window.end <= 32768
										&& window.alignment >= sector && window.alignment & (window.alignment - 1) == 0
										&& window.start % sector == 0 && window.end % sector == 0
										&& (window.end <= 16384 || window.start >= 24576)
									}
									if !member {
										expected.windows[expected.regions] = batch.rows[i]; expected.regions++
										changed |= u64(1) << i
									}
								}
								mut set := baseline
								mut results := PoolMembersResults{count: 19, changed: 17}
								previous := results
								assert bundle_pool_members_batch(mut set, 3, &batch, false, mut results) == valid
								if valid { assert set == expected && results == PoolMembersResults{count: 2, changed: changed} }
								else { assert set == baseline && results == previous }
								// Removing uses original disk indices and preserves every other row.
								set = baseline; results = previous
								expected = baseline
								for i in 2 .. baseline.regions { expected.windows[i] = PoolRegion{} }
								expected.regions = 2
								changed = 0
								for i in 0 .. 2 { if present & (1 << batch.rows[i].disk) != 0 { changed |= u64(1) << i } }
								assert bundle_pool_members_batch(mut set, 3, &batch, true, mut results)
								assert set == expected && results == PoolMembersResults{count: 2, changed: changed}
								assert bundle_pool_members_batch(mut set, 3, &batch, true, mut results)
								assert set == expected && results == PoolMembersResults{count: 2}
							}
						}
					}
				}
			}
		}
	}
}

fn test_membership_invalid_requests_roll_back_set_and_results_for_both_operations() {
	mut baseline := PlanSet{}
	members_fixture(mut baseline, 512, 4096, 1, 1)
	mut batch := PoolMembersBatch{count: 2}
	batch.rows[0] = PoolRegion{pool: 3, disk: 1, window: SpaceWindow{start: 8192, end: 12288, alignment: 4096}}
	batch.rows[1] = PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 8192, end: 12288, alignment: 4096}}
	good := batch
	for remove in [false, true] {
		for mode in 0 .. 8 {
			batch = good
			mut pool := u32(3)
			mut set := baseline
			match mode {
				0 { batch.count = 0 }
				1 { batch.count = 65 }
				2 { batch.count = -1 }
				3 { batch.rows[1].disk = 1 }
				4 { batch.rows[1].disk = 2 }
				5 { batch.rows[1].disk = 64 }
				6 { batch.rows[1] = PoolRegion{pool: 4, disk: 0, window: good.rows[1].window} }
				else { pool = 64 }
			}
			before := set
			mut result := PoolMembersResults{count: 77, changed: u64(-1)}
			previous := result
			assert !bundle_pool_members_batch(mut set, pool, &batch, remove, mut result)
			assert set == before && result == previous
		}
	}
	// The first addition fits; the later saved member mismatch discards it.
	batch = good; batch.rows[1].window = SpaceWindow{start: 8192, end: 16384, alignment: 4096}
	mut set := baseline
	mut results := PoolMembersResults{count: 9, changed: 63}
	previous := results
	assert !bundle_pool_members_batch(mut set, 3, &batch, false, mut results)
	assert set == baseline && results == previous
	set.plans[1].rows[0].slot = 2
	invalid := set
	assert !bundle_pool_members_batch(mut set, 3, &good, true, mut results)
	assert set == invalid && results == previous
}

fn test_membership_full_table_retries_priority_compaction_and_v1_v2_roundtrips() {
	mut set := PlanSet{}
	mut batch := PoolMembersBatch{count: 64}
	for disk in 0 .. 64 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~u64(4095), sector: 4096, kind: 1}}
		plan.key.id[0] = u8(disk + 1)
		plan.rows[0] = Request{slot: u32(disk), offset: 0, length: 4096, flags: u64(disk & 1)}
		assert append_plan(mut set, &plan)
		batch.rows[63 - disk] = PoolRegion{pool: 3, disk: u32(disk),
			window: SpaceWindow{start: plan.key.bytes - 8192, end: plan.key.bytes, alignment: 4096}}
	}
	baseline := set
	mut results := PoolMembersResults{}
	assert bundle_pool_members_batch(mut set, 3, &batch, false, mut results)
	assert set.regions == 64 && results.changed == u64(-1)
	for i in 0 .. 64 { assert set.windows[i] == batch.rows[i] }
	configured := set
	assert bundle_pool_members_batch(mut set, 3, &batch, false, mut results)
	assert set == configured && results.changed == 0
	mut bytes := [8768]u8{}
	assert encode_bundle(&set, &bytes[0]) == 8768
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], 8768, mut decoded) && decoded == set
	// All keeps remain admissible at the full bound; a later new row does not.
	mut extra := PoolMembersBatch{count: 1}
	extra.rows[0] = PoolRegion{pool: 4, disk: 0, window: SpaceWindow{start: 4096, end: 8192, alignment: 4096}}
	previous := results
	assert !bundle_pool_members_batch(mut set, 4, &extra, false, mut results)
	assert set == configured && results == previous
	assert bundle_pool_members_batch(mut set, 3, &batch, true, mut results)
	assert set == baseline && results.changed == u64(-1)
	assert encode_bundle(&set, &bytes[0]) == 6208 && bytes[7] == `1`
	decoded = PlanSet{}
	assert decode_bundle(&bytes[0], 6208, mut decoded) && decoded == baseline
	assert bundle_pool_members_batch(mut set, 3, &batch, true, mut results) && results.changed == 0
}

fn test_membership_batch_cli_rejects_counts_unsigned_numbers_and_invalid_windows() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-add-batch'), &char(c'/unused'), &char(c'3'),
			&char(c'0'), &char(c'0'), &char(c'4096'), &char(c'4096'), &char(nil)]!
		for command in [c'pool-add-batch', c'pool-preview-add-batch'] {
			args[1] = &char(command)
			for count in [2, 3, 4, 5, 6, 7, 9, 261, 264] { assert run(count, &args[0]) == 2 }
			for at in 3 .. 8 {
				old := args[at]
				for bad in [c'', c'-1', c'1x', c'18446744073709551616'] { args[at] = &char(bad); assert run(8, &args[0]) == 2 }
				args[at] = old
			}
			args[4] = &char(c'64'); assert run(8, &args[0]) == 2; args[4] = &char(c'0')
			args[7] = &char(c'0'); assert run(8, &args[0]) == 2; args[7] = &char(c'4096')
		}
		for command in [c'pool-remove-batch', c'pool-preview-remove-batch'] {
			args[1] = &char(command)
			for count in [2, 3, 4, 69, 260] { assert run(count, &args[0]) == 2 }
			for at in [3, 4] {
				old := args[at]
				for bad in [c'', c'-1', c'64', c'1x', c'18446744073709551616'] { args[at] = &char(bad); assert run(5, &args[0]) == 2 }
				args[at] = old
			}
		}
	}
}

fn test_maximum_membership_cli_publishes_all_260_add_and_68_remove_arguments() {
	work := os.join_path(os.temp_dir(), 'vinix-members-full-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	for disk in 0 .. 64 {
		mut plan := Plan{key: DiskKey{bytes: 32768, sector: 4096, kind: 1}}
		plan.key.id[0] = u8(disk + 1)
		assert append_plan(mut set, &plan)
	}
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	unsafe {
		mut args := [261]&char{}
		mut numbers := [64][4]char{}
		args[0] = &char(c'vinix-volume'); args[2] = path.str; args[3] = &char(c'3')
		for i in 0 .. 64 {
			C.snprintf(&numbers[i][0], 4, c'%u', u32(63 - i))
			args[4 + i * 4] = &numbers[i][0]; args[5 + i * 4] = &char(c'8192')
			args[6 + i * 4] = &char(c'12288'); args[7 + i * 4] = &char(c'4096')
		}
		args[1] = &char(c'pool-preview-add-batch'); assert run(260, &args[0]) == 0
		assert os.read_bytes(path)! == original
		args[1] = &char(c'pool-add-batch'); assert run(260, &args[0]) == 0
		configured := os.read_bytes(path)!
		mut decoded := PlanSet{}
		assert decode_bundle(configured.data, configured.len, mut decoded) && decoded.regions == 64
		for i in 0 .. 64 { assert decoded.windows[i].disk == u32(63 - i) }
		assert run(260, &args[0]) == 0 && os.read_bytes(path)! == configured
		for i in 0 .. 64 { args[4 + i] = &numbers[63 - i][0] }
		args[68] = &char(nil)
		args[1] = &char(c'pool-preview-remove-batch'); assert run(68, &args[0]) == 0
		assert os.read_bytes(path)! == configured
		args[1] = &char(c'pool-remove-batch'); assert run(68, &args[0]) == 0
		assert os.read_bytes(path)! == original
		assert run(68, &args[0]) == 0 && os.read_bytes(path)! == original
	}
}

fn test_membership_commands_preserve_corrupt_symlink_and_nonregular_sources() {
	work := os.join_path(os.temp_dir(), 'vinix-members-input-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	members_fixture(mut set, 512, 4096, 1, 0)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	os.symlink(path, work + '/link')!
	mut batch := PoolMembersBatch{count: 1}
	batch.rows[0] = PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 8192, end: 12288, alignment: 4096}}
	for remove in [false, true] {
		for preview in [false, true] {
			for input in [work + '/link', work, work + '/missing'] {
				assert members_batch_pool_plan(input.str, 3, &batch, remove, preview) == 1
				assert os.read_bytes(path)! == original
			}
			os.write_file(path, 'invalid saved bundle')!
			assert members_batch_pool_plan(path.str, 3, &batch, remove, preview) == 1
			assert os.read_file(path)! == 'invalid saved bundle'
			os.write_file_array(path, original)!
		}
	}
	assert os.ls(work)!.len == 2
}
