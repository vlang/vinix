// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn contract_fixture(mut set PlanSet, first_sector u64, second_sector u64, first_kind u32) {
	for disk in 0 .. 2 {
		kind := if disk == 0 { first_kind } else { u32(3) - first_kind }
		mut plan := Plan{count: 2, key: DiskKey{bytes: 25165824,
			sector: if disk == 0 { first_sector } else { second_sector }, kind: kind}}
		plan.key.id[0] = u8(disk + 1)
		if kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(2 + disk * 7), offset: 4194304, length: 8192, flags: 1}
		plan.rows[1] = Request{slot: u32(3 + disk * 7), offset: 1048576, length: 12288}
		assert append_plan(mut set, &plan)
	}
	for disk in [1, 0] {
		region := PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: 6291456, end: 6303744, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	other := PoolRegion{pool: 5, disk: 0, window: SpaceWindow{start: 8388608, end: 8392704, alignment: 4096}}
	assert bundle_pool_add(mut set, &other)
	set.plans[63].key.id[0] = 99; set.windows[63] = PoolRegion{pool: 62}
}

fn contract_requests(set &PlanSet) (CapacityContractBatch, CapacityKeys) {
	mut batch := CapacityContractBatch{count: 2}; mut observed := CapacityKeys{}
	for i in 0 .. 2 {
		disk := 1 - i; batch.keys[i] = set.plans[disk].key
		// Request identities deliberately carry unrelated geometry.
		batch.keys[i].bytes = 1; batch.keys[i].sector = 3; batch.expected[i] = 16777216
		observed.rows[i] = set.plans[disk].key; observed.rows[i].bytes = batch.expected[i]
	}
	return batch, observed
}

fn test_contract_capacity_preserves_every_mapping_pool_priority_and_unused_field() {
	mut set := PlanSet{}; contract_fixture(mut set, 512, 4096, 1)
	before := set; batch, observed := contract_requests(&set); mut results := CapacityContractResults{}
	assert bundle_contract_capacity_batch(mut set, &batch, &observed, mut results)
	mut expected := before; expected.plans[0].key.bytes = 16777216; expected.plans[1].key.bytes = 16777216
	assert set == expected && results.count == 2 && results.keys == observed
	assert results.disks[0] == 1 && results.disks[1] == 0 && results.previous[0] == 25165824 && results.previous[1] == 25165824
	assert bundle_contract_capacity_batch(mut set, &batch, &observed, mut results) && set == expected
	assert results.previous[0] == 16777216 && results.previous[1] == 16777216
	// A selected subset does not change an unselected disk's geometry.
	set = before; mut subset := batch; subset.count = 1
	assert bundle_contract_capacity_batch(mut set, &subset, &observed, mut results)
	expected.plans[0].key.bytes = 25165824; assert set == expected
}

// Enumerate identity, sector, exact observation and contraction independently:
// eight geometries, two request orders and 256 mask pairs = 4096 attempts.
fn test_contract_capacity_matches_4096_independent_condition_oracles() {
	for first_sector in [u64(512), 4096] { for second_sector in [u64(512), 4096] { for kind in [u32(1), 2] {
		mut baseline := PlanSet{}; contract_fixture(mut baseline, first_sector, second_sector, kind)
		for reverse in [false, true] { for first_mask in 0 .. 16 { for second_mask in 0 .. 16 {
			masks := [first_mask, second_mask]!
			mut batch := CapacityContractBatch{count: 2}; mut observed := CapacityKeys{}
			for i in 0 .. 2 {
				disk := if reverse { 1 - i } else { i }; mask := masks[disk]
				batch.keys[i] = baseline.plans[disk].key; observed.rows[i] = baseline.plans[disk].key
				batch.keys[i].sector = 0; batch.keys[i].bytes = u64(-1)
				observed.rows[i].bytes = if mask & 8 != 0 { u64(16777216) } else { u64(33554432) }
				batch.expected[i] = observed.rows[i].bytes + if mask & 4 != 0 { u64(0) } else { baseline.plans[disk].key.sector }
				if mask & 2 == 0 { observed.rows[i].sector = if observed.rows[i].sector == 512 { u64(4096) } else { u64(512) } }
				if mask & 1 == 0 { observed.rows[i].id[0] += 32 }
			}
			mut set := baseline; mut results := CapacityContractResults{count: 19}; results.previous[63] = 77
			old_results := results; valid := first_mask == 15 && second_mask == 15
			assert bundle_contract_capacity_batch(mut set, &batch, &observed, mut results) == valid
			if !valid { assert set == baseline && results == old_results; continue }
			mut expected := baseline; expected.plans[0].key.bytes = 16777216; expected.plans[1].key.bytes = 16777216
			assert set == expected && results.keys == observed && results.count == 2
		} } }
	} } }
}

fn test_contract_capacity_invalid_later_requests_preserve_all_caller_and_result_fields() {
	mut baseline := PlanSet{}; contract_fixture(mut baseline, 512, 4096, 1)
	requests, observations := contract_requests(&baseline)
	for bad in 0 .. 18 {
		mut set := baseline; mut batch := requests; mut observed := observations
		match bad {
			0 { batch.count = -1 }
			1 { batch.count = 0 }
			2 { batch.count = 65 }
			3 { batch.keys[1] = batch.keys[0] }
			4 { batch.keys[1].id[0] = 78 }
			5 { batch.keys[1].kind = 3 }
			6 { batch.expected[1] = 0 }
			7 { batch.expected[1] = 512 }
			8 { batch.expected[1] = 16777217 }
			9 { batch.expected[1] = 33554432 }
			10 { batch.expected[1] = u64(-1) }
			11 { observed.rows[1].kind = 3 }
			12 { observed.rows[1].bytes -= 512 }
			13 { observed.rows[1].sector = 4096 }
			14 { observed.rows[1].id[0]++ }
			15 { set.plans[0].rows[1].offset = 16777216 } // Pending desired bytes are protected.
			16 { set.windows[2].window = SpaceWindow{start: 8388608, end: 20971520, alignment: 4096} } // An unselected pool must also fit.
			else { set.plans[1].rows[0].slot = 2 }
		}
		before := set; mut results := CapacityContractResults{count: 17}; results.previous[63] = 42; results.keys.rows[63].id[0] = 9
		old_results := results
		assert !bundle_contract_capacity_batch(mut set, &batch, &observed, mut results) && set == before && results == old_results
	}
	// Ambiguity in an unselected empty member is rejected even at another size.
	mut set := baseline; set.regions = 0; set.plans[1].count = 0
	set.plans[1].key = set.plans[0].key; set.plans[1].key.bytes = 33554432
	assert bundle_set_valid(&set)
	before := set; mut batch := requests; batch.count = 1; batch.keys[0] = set.plans[0].key
	mut results := CapacityContractResults{count: 17}; old_results := results
	assert !bundle_contract_capacity_batch(mut set, &batch, &observations, mut results) && set == before && results == old_results
}

fn test_contract_capacity_identity_retry_after_compaction_and_u64_maximum_bundle() {
	mut set := PlanSet{}; mut batch := CapacityContractBatch{count: 64}; mut observed := CapacityKeys{}
	for disk in 0 .. 64 {
		sector := if disk & 1 == 0 { u64(512) } else { u64(4096) }
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~(sector - 1), sector: sector, kind: if disk & 1 == 0 { u32(1) } else { u32(2) }}}
		plan.key.id[0] = u8(disk + 1); if plan.key.kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(disk), offset: 8192, length: 4096, flags: u64(disk & 1)}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 63, disk: u32(disk), window: SpaceWindow{start: 8388608, end: 8392704, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
		i := 63 - disk; batch.keys[i] = plan.key; batch.expected[i] = plan.key.bytes - 8192
		observed.rows[i] = plan.key; observed.rows[i].bytes = batch.expected[i]
	}
	before := set; mut results := CapacityContractResults{}
	assert bundle_contract_capacity_batch(mut set, &batch, &observed, mut results)
	mut expected := before
	for i in 0 .. 64 { expected.plans[63 - i].key.bytes = batch.expected[i]; assert results.disks[i] == u32(63 - i) && results.previous[i] == before.plans[63 - i].key.bytes }
	assert set == expected && results.keys == observed
	mut bytes := [8768]u8{}; assert encode_bundle(&set, &bytes[0]) == 8768
	mut decoded := PlanSet{}; assert decode_bundle(&bytes[0], 8768, mut decoded) && decoded == set
	// The selector continues to find the same disk after unrelated membership compaction.
	mut compacted := PlanSet{count: 1}; compacted.plans[0] = set.plans[63]
	mut one := CapacityContractBatch{count: 1}; one.keys[0] = batch.keys[0]; one.expected[0] = batch.expected[0]
	assert bundle_contract_capacity_batch(mut compacted, &one, &observed, mut results) && results.disks[0] == 0
}

fn test_contract_capacity_cli_validates_complete_syntax_before_bundle_access() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-contract-capacity-batch'), &char(c'/unused'),
			&char(c'mbr:00000001'), &char(c'/unused-device'), &char(c'16777216'),
			&char(c'gpt:02000000-0000-0000-0000-000000000083'), &char(c'/unused-device'), &char(c'16777216'), &char(nil)]!
		for command in [c'plan-contract-capacity-batch', c'plan-preview-contract-capacity-batch'] {
			args[1] = &char(command)
			for count in [2, 3, 4, 5, 7, 8, 196, 198] { assert run(count, &args[0]) == 2 }
			for index in [3, 6] { old := args[index]; for bad in [c'', c'mbr:1', c'mbr:00000000', c'gpt:broken', c'0'] { args[index] = &char(bad); assert run(9, &args[0]) == 2 }; args[index] = old }
			for index in [5, 8] { old := args[index]; for bad in [c'', c'0', c'-1', c'1x', c'18446744073709551616'] { args[index] = &char(bad); assert run(9, &args[0]) == 2 }; args[index] = old }
			for index in [4, 7] { old := args[index]; args[index] = &char(c''); assert run(9, &args[0]) == 2; args[index] = old }
		}
	}
}
