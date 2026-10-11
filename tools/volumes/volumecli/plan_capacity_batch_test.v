// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn capacity_batch_fixture(mut set PlanSet, first_sector u64, second_sector u64, first_kind u32) {
	for disk in 0 .. 2 {
		kind := if disk == 0 { first_kind } else { u32(3) - first_kind }
		mut plan := Plan{count: 2, key: DiskKey{bytes: 16777216,
			sector: if disk == 0 { first_sector } else { second_sector }, kind: kind}}
		plan.key.id[0] = u8(disk + 1)
		if kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(2 + disk * 7), offset: 4194304, length: 8192, flags: 1}
		plan.rows[1] = Request{slot: u32(3 + disk * 7), offset: 1048576, length: 12288}
		assert append_plan(mut set, &plan)
	}
	for disk in [1, 0] {
		region := PoolRegion{pool: 3, disk: u32(disk),
			window: SpaceWindow{start: 6291456, end: 6303744, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	other := PoolRegion{pool: 5, disk: 0, window: SpaceWindow{start: 8388608, end: 8392704, alignment: 4096}}
	assert bundle_pool_add(mut set, &other)
	set.plans[63].key.id[0] = 99
	set.windows[63] = PoolRegion{pool: 62}
}

fn test_capacity_batch_preserves_all_desired_rows_pools_priority_and_unused_storage() {
	mut set := PlanSet{}
	capacity_batch_fixture(mut set, 512, 4096, 1)
	before := set
	mut batch := CapacityBatch{count: 2}
	batch.disks[0] = 1; batch.expected[0] = 33554432
	batch.disks[1] = 0; batch.expected[1] = 25165824
	mut keys := CapacityKeys{}
	for i in 0 .. 2 { keys.rows[i] = set.plans[batch.disks[i]].key; keys.rows[i].bytes = batch.expected[i] }
	observed := keys
	mut results := CapacityBatchResults{}
	assert bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results)
	mut expected := before
	expected.plans[1].key.bytes = 33554432; expected.plans[0].key.bytes = 25165824
	assert set == expected && keys == observed && results.count == 2 && results.keys == keys
	assert results.previous[0] == 16777216 && results.previous[1] == 16777216
	assert bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results) && set == expected
	assert results.previous[0] == 33554432 && results.previous[1] == 25165824
	// Mixed adopt/keep requests retain the second member exactly.
	set = before; batch.expected[1] = 16777216; keys.rows[1].bytes = 16777216
	assert bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results)
	expected.plans[0].key.bytes = 16777216
	assert set == expected
}

// Independently enumerate the four required conditions for each physical key:
// identity, sector, exact expected bytes and no shrink. Include both request
// orders and eight mixed-sector/MBR/GPT configurations: 4096 complete attempts.
fn test_capacity_batch_matches_independent_condition_oracle_for_4096_attempts() {
	for first_sector in [u64(512), 4096] {
		for second_sector in [u64(512), 4096] {
			for kind in [u32(1), 2] {
				mut baseline := PlanSet{}
				capacity_batch_fixture(mut baseline, first_sector, second_sector, kind)
				for reverse in [false, true] {
					for first_mask in 0 .. 16 {
						for second_mask in 0 .. 16 {
							masks := [first_mask, second_mask]!
							mut batch := CapacityBatch{count: 2}
							mut keys := CapacityKeys{}
							for i in 0 .. 2 {
								disk := if reverse { 1 - i } else { i }
								mask := masks[disk]
								batch.disks[i] = u32(disk)
								keys.rows[i] = baseline.plans[disk].key
								keys.rows[i].bytes = if mask & 8 != 0 { u64(25165824) } else { u64(8388608) }
								batch.expected[i] = keys.rows[i].bytes + if mask & 4 != 0 { u64(0) } else { baseline.plans[disk].key.sector }
								if mask & 2 == 0 { keys.rows[i].sector = if keys.rows[i].sector == 512 { u64(4096) } else { u64(512) } }
								if mask & 1 == 0 { keys.rows[i].id[0] += 32 }
							}
							mut set := baseline
							mut results := CapacityBatchResults{count: 19}
							results.previous[63] = 77
							previous := results
							valid := first_mask == 15 && second_mask == 15
							assert bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results) == valid
							if !valid { assert set == baseline && results == previous; continue }
							mut expected := baseline
							expected.plans[0].key.bytes = 25165824; expected.plans[1].key.bytes = 25165824
							assert set == expected && results.keys == keys && results.count == 2
						}
					}
				}
			}
		}
	}
}

fn test_capacity_batch_invalid_requests_and_later_keys_roll_back_every_field() {
	mut set := PlanSet{}
	capacity_batch_fixture(mut set, 512, 4096, 1)
	before := set
	mut batch := CapacityBatch{count: 2}
	mut keys := CapacityKeys{}
	for i in 0 .. 2 { batch.disks[i] = u32(i); batch.expected[i] = 25165824; keys.rows[i] = set.plans[i].key; keys.rows[i].bytes = 25165824 }
	mut results := CapacityBatchResults{count: 17}
	results.previous[63] = 42; results.keys.rows[63].id[0] = 9
	previous := results
	for count in [-1, 0, 65] {
		batch.count = count
		assert !bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results) && set == before && results == previous
	}
	batch.count = 2
	for disk in [u32(0), 2, 64] {
		batch.disks[1] = disk
		assert !bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results) && set == before && results == previous
	}
	batch.disks[1] = 1
	for end in [u64(0), 8388608, 25165825, u64(-1)] {
		batch.expected[1] = end
		assert !bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results) && set == before && results == previous
	}
	batch.expected[1] = 25165824
	keys.rows[1].kind = 3
	assert !bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results) && set == before && results == previous
	keys.rows[1] = before.plans[1].key; keys.rows[1].bytes = 25165824
	set.plans[1].rows[0].slot = 2
	invalid := set
	assert !bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results) && set == invalid && results == previous
	// Identical identifiers at different geometries must not be adopted.
	set = before; set.regions = 0; set.plans[1].key.kind = 1; set.plans[1].key.id = before.plans[0].key.id
	ambiguous := set
	assert bundle_set_valid(&set)
	assert !bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results) && set == ambiguous && results == previous
}

fn test_maximum_capacity_batch_preserves_all_64_members_and_rows_near_u64() {
	mut set := PlanSet{}
	mut batch := CapacityBatch{count: 64}
	mut keys := CapacityKeys{}
	for disk in 0 .. 64 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 16777216,
			sector: if disk & 1 == 0 { u64(512) } else { u64(4096) }, kind: if disk & 1 == 0 { u32(1) } else { u32(2) }}}
		plan.key.id[0] = u8(disk + 1)
		if plan.key.kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(disk), offset: 8192, length: 4096, flags: u64(disk & 1)}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 63, disk: u32(disk), window: SpaceWindow{start: 8388608, end: 8392704, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
		i := 63 - disk
		batch.disks[i] = u32(disk); batch.expected[i] = u64(-1) & ~(plan.key.sector - 1)
		keys.rows[i] = plan.key; keys.rows[i].bytes = batch.expected[i]
	}
	before := set
	mut results := CapacityBatchResults{}
	assert bundle_adopt_capacity_batch(mut set, &batch, &keys, mut results)
	mut expected := before
	for i in 0 .. 64 { expected.plans[batch.disks[i]].key.bytes = batch.expected[i]; assert results.previous[i] == 16777216 }
	assert set == expected && results.keys == keys && results.count == 64
	mut bytes := [8768]u8{}
	assert encode_bundle(&set, &bytes[0]) == 8768
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], 8768, mut decoded) && decoded == set
}

fn test_capacity_batch_cli_rejects_invalid_counts_pairs_numbers_and_empty_devices() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-capacity-batch'), &char(c'/unused'),
			&char(c'0'), &char(c'/unused-device'), &char(c'25165824'), &char(c'1'), &char(c'/unused-device'), &char(c'25165824'), &char(nil)]!
		for command in [c'plan-capacity-batch', c'plan-preview-capacity-batch'] {
			args[1] = &char(command)
			for count in [2, 3, 4, 5, 7, 8, 196, 198] { assert run(count, &args[0]) == 2 }
			for index in [3, 5, 6, 8] {
				old := args[index]
				for bad in [c'', c'-1', c'1x', c'18446744073709551616'] { args[index] = &char(bad); assert run(9, &args[0]) == 2 }
				args[index] = old
			}
			for index in [3, 6] { old := args[index]; args[index] = &char(c'64'); assert run(9, &args[0]) == 2; args[index] = old }
			for index in [5, 8] { old := args[index]; args[index] = &char(c'0'); assert run(9, &args[0]) == 2; args[index] = old }
			for index in [4, 7] { old := args[index]; args[index] = &char(c''); assert run(9, &args[0]) == 2; args[index] = old }
		}
	}
}
