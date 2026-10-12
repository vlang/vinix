// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn multi_growth_fixture(mut set PlanSet, first_mask int, second_mask int, kind u32) {
	for disk in 0 .. 2 {
		sector := if disk == 0 { u64(512) } else { u64(4096) }
		mut plan := Plan{count: 1, key: DiskKey{bytes: sector * 16, sector: sector, kind: if disk == 0 { kind } else { u32(3) - kind }}}
		plan.key.id[0] = u8(disk + 1); if plan.key.kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(disk), offset: sector * 2, length: sector, flags: u64(disk)}
		mask := if disk == 0 { first_mask } else { second_mask }
		for bit in 0 .. 4 { if mask & (1 << bit) != 0 {
			plan.rows[plan.count] = Request{slot: u32(10 + disk * 4 + bit), offset: sector * u64(3 + bit), length: sector, flags: u64(bit & 1)}; plan.count++
		} }
		assert append_plan(mut set, &plan)
	}
	// Each pool prefers an empty alternate disk. Growth must remain on the
	// existing row's own member even when that alternate has more capacity.
	for at in 0 .. 4 {
		pool := at & 1; alternate := at < 2; disk := if alternate { 1 - pool } else { pool }
		sector := set.plans[disk].key.sector
		region := PoolRegion{pool: u32(7 + pool), disk: u32(disk), window: SpaceWindow{
			start: sector * if alternate { u64(8) } else { u64(2) }, end: sector * if alternate { u64(15) } else { u64(7) }, alignment: sector}}
		assert bundle_pool_add(mut set, &region)
	}
	set.plans[63].key.id[0] = 91; set.windows[63] = PoolRegion{pool: 62}
}

fn test_multi_pool_growth_16384_independent_extension_oracles_and_exact_whole_set_retries() {
	for kind in [u32(1), 2] { for reverse in [false, true] { for first_mask in 0 .. 16 { for second_mask in 0 .. 16 {
		for first_cells in 1 .. 5 { for second_cells in 1 .. 5 {
			mut baseline := PlanSet{}; multi_growth_fixture(mut baseline, first_mask, second_mask, kind)
			mut expected := baseline; mut batch := MultiPoolGrowthBatch{count: 2}; mut expected_result := PoolGrowthResults{count: 2}
			mut fits := true
			for i in 0 .. 2 {
				disk := if reverse { 1 - i } else { i }; mask := if disk == 0 { first_mask } else { second_mask }; cells := if disk == 0 { first_cells } else { second_cells }
				for extension in 1 .. cells { if mask & (1 << (extension - 1)) != 0 { fits = false } }
				sector := baseline.plans[disk].key.sector
				batch.pools[i] = u32(7 + disk); batch.slots[i] = u32(disk); batch.lengths[i] = sector * u64(cells)
				expected.plans[disk].rows[0].length = batch.lengths[i]
				expected_result.disks[i] = u32(disk); expected_result.rows[i] = expected.plans[disk].rows[0]; expected_result.previous[i] = sector
			}
			mut set := baseline; mut result := PoolGrowthResults{count: 17}; result.rows[63].length = 91; result.disks[63] = 42; result.previous[63] = 33; old_result := result
			assert bundle_multi_pool_grow_batch(mut set, &batch, mut result) == fits
			if !fits { assert set == baseline && result == old_result; continue }
			assert set == expected && result == expected_result
			for i in 0 .. 2 { expected_result.previous[i] = expected_result.rows[i].length }
			assert bundle_multi_pool_grow_batch(mut set, &batch, mut result) && set == expected && result == expected_result
		} }
	} } } }
}

fn test_multi_pool_growth_later_invalid_requests_and_wrong_members_never_escape() {
	mut baseline := PlanSet{}; multi_growth_fixture(mut baseline, 0, 0, 2)
	for bad in 0 .. 14 {
		mut set := baseline; mut batch := MultiPoolGrowthBatch{count: 2}; batch.pools[0] = 7; batch.pools[1] = 8
		batch.slots[0] = 0; batch.slots[1] = 1; batch.lengths[0] = 1024; batch.lengths[1] = 8192
		match bad {
			0 { batch.count = -1 }
			1 { batch.count = 0 }
			2 { batch.count = 65 }
			3 { batch.pools[1] = 64 }
			4 { batch.pools[1] = 9 }
			5 { batch.pools[1] = 7 }
			6 { batch.slots[1] = 0 }
			7 { batch.slots[1] = 64 }
			8 { batch.slots[1] = 20 }
			9 { batch.lengths[1] = 0 }
			10 { batch.lengths[1] = 512 }
			11 { batch.lengths[1] = 4097 }
			12 { batch.lengths[1] = 24576 }
			else { batch.lengths[1] = u64(-1) }
		}
		mut result := PoolGrowthResults{count: 17}; result.rows[63].length = 91; result.previous[63] = 33; old_result := result
		assert !bundle_multi_pool_grow_batch(mut set, &batch, mut result) && set == baseline && result == old_result
	}
	mut batch := MultiPoolGrowthBatch{count: 2}; batch.pools[0] = 7; batch.pools[1] = 8; batch.slots[0] = 0; batch.slots[1] = 1; batch.lengths[0] = 1024; batch.lengths[1] = 8192
	mut result := PoolGrowthResults{count: 17}; old_result := result
	for bad in 0 .. 3 {
		mut set := baseline
		if bad == 0 { set.windows[3].window = SpaceWindow{start: 12288, end: 28672, alignment: 4096} } // Old row is outside its selected member.
		else if bad == 1 { set.windows[3].window = SpaceWindow{start: 8192, end: 8193, alignment: 4096} } // Corrupt complete source.
		else { set.plans[1].rows[1] = Request{slot: 20, offset: 12288, length: 4096}; set.plans[1].count = 2; set.slots |= u64(1) << 20 }
		before := set
		assert !bundle_multi_pool_grow_batch(mut set, &batch, mut result) && set == before && result == old_result
	}
}

fn test_multi_pool_growth_interleaved_same_pool_rows_preserve_order_modes_and_mixed_keeps() {
	mut set := PlanSet{}; multi_growth_fixture(mut set, 0, 0, 1)
	set.plans[0].rows[1] = Request{slot: 20, offset: 2048, length: 512, flags: 1}; set.plans[0].count = 2; set.slots |= u64(1) << 20
	before := set; mut expected := before; expected.plans[0].rows[0].length = 1024; expected.plans[1].rows[0].length = 8192; expected.plans[0].rows[1].length = 1024
	mut batch := MultiPoolGrowthBatch{count: 3}; batch.pools[0] = 7; batch.pools[1] = 8; batch.pools[2] = 7
	batch.slots[0] = 0; batch.slots[1] = 1; batch.slots[2] = 20; batch.lengths[0] = 1024; batch.lengths[1] = 8192; batch.lengths[2] = 1024
	mut result := PoolGrowthResults{}; assert bundle_multi_pool_grow_batch(mut set, &batch, mut result) && set == expected
	assert result.count == 3 && result.disks[0] == 0 && result.disks[1] == 1 && result.disks[2] == 0
	// An all-keep first row and two independent new growths still publish once.
	set = before; set.plans[0].rows[0].length = 1024
	assert bundle_multi_pool_grow_batch(mut set, &batch, mut result) && set == expected
	assert result.previous[0] == 1024 && result.previous[1] == 4096 && result.previous[2] == 512
	set = before; batch.lengths[0] = 1536 // Cannot consume the later row, regardless of request order.
	old_result := result; assert !bundle_multi_pool_grow_batch(mut set, &batch, mut result) && set == before && result == old_result
}

fn test_maximum_multi_pool_growth_195_cli_arguments_64_pools_near_u64_and_full_v2() {
	work := os.join_path(os.temp_dir(), 'vinix-multi-growth-full-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut baseline := PlanSet{}
	for disk in 0 .. 64 {
		sector := if disk & 1 == 0 { u64(512) } else { u64(4096) }; end := u64(-1) & ~(sector - 1)
		mut plan := Plan{count: 1, key: DiskKey{bytes: end, sector: sector, kind: if disk & 1 == 0 { u32(1) } else { u32(2) }}}
		plan.key.id[0] = u8(disk + 1); if plan.key.kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(63 - disk), offset: (end - 8192) & ~u64(4095), length: 4096, flags: u64(disk & 1)}
		assert append_plan(mut baseline, &plan)
		region := PoolRegion{pool: u32(disk), disk: u32(disk), window: SpaceWindow{start: plan.rows[0].offset, end: end, alignment: 4096}}
		assert bundle_pool_add(mut baseline, &region)
	}
	assert publish_bundle(path.str, &baseline); original := os.read_bytes(path)!; mut expected := baseline
	unsafe {
		mut args := [196]&char{}; mut pools := [64][4]char{}; mut slots := [64][4]char{}
		args[0] = &char(c'vinix-volume'); args[1] = &char(c'pool-preview-grow-set-batch'); args[2] = path.str
		for i in 0 .. 64 {
			disk := 63 - i; C.snprintf(&pools[i][0], 4, c'%u', u32(disk)); C.snprintf(&slots[i][0], 4, c'%u', u32(i))
			args[3 + i * 3] = &pools[i][0]; args[4 + i * 3] = &slots[i][0]; args[5 + i * 3] = &char(c'8192'); expected.plans[disk].rows[0].length = 8192
		}
		assert run(195, &args[0]) == 0 && os.read_bytes(path)! == original
		args[1] = &char(c'pool-grow-set-batch'); assert run(195, &args[0]) == 0
		bytes := os.read_bytes(path)!; mut decoded := PlanSet{}; assert bytes.len == 8768 && decode_bundle(bytes.data, bytes.len, mut decoded) && decoded == expected
		assert run(195, &args[0]) == 0 && os.read_bytes(path)! == bytes
	}
}

fn test_multi_pool_growth_source_rejections_writer_lock_and_complete_cli_tokens() {
	work := os.join_path(os.temp_dir(), 'vinix-multi-growth-input-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut set := PlanSet{}; multi_growth_fixture(mut set, 0, 0, 1); assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!; mut batch := MultiPoolGrowthBatch{count: 2}; batch.pools[0] = 7; batch.pools[1] = 8; batch.slots[0] = 0; batch.slots[1] = 1; batch.lengths[0] = 1024; batch.lengths[1] = 8192
	mut edit := PlanEdit{}; assert open_plan_edit(path.str, mut edit, true)
	assert grow_multi_pool_batch_plan(path.str, &batch, false) == 1 && grow_multi_pool_batch_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == original
	close_plan_edit(mut edit); assert grow_multi_pool_batch_plan(path.str, &batch, false) == 0
	grown := os.read_bytes(path)!; assert grown != original && grow_multi_pool_batch_plan(path.str, &batch, false) == 0 && os.read_bytes(path)! == grown
	os.symlink(path, work + '/link')!
	for input in [work, work + '/missing', work + '/link'] { for preview in [false, true] { assert grow_multi_pool_batch_plan(input.str, &batch, preview) == 1 } }
	mut broken := grown.clone(); broken[24] ^= 1; os.write_file_array(path, broken)!
	for preview in [false, true] { assert grow_multi_pool_batch_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == broken }
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-grow-set-batch'), &char(c'/unused'), &char(c'7'), &char(c'0'), &char(c'1024'), &char(c'8'), &char(c'1'), &char(c'8192'), &char(nil)]!
		for command in [c'pool-grow-set-batch', c'pool-preview-grow-set-batch'] {
			args[1] = &char(command); for count in [2, 3, 4, 5, 7, 8, 196, 198] { assert run(count, &args[0]) == 2 }
			for at in [3, 4, 5, 6, 7, 8] { old := args[at]; for bad in [c'', c'-1', c'1x', c'18446744073709551616'] { args[at] = &char(bad); assert run(9, &args[0]) == 2 }; args[at] = old }
			for at in [3, 4, 6, 7] { old := args[at]; args[at] = &char(c'64'); assert run(9, &args[0]) == 2; args[at] = old }
			for at in [5, 8] { old := args[at]; args[at] = &char(c'0'); assert run(9, &args[0]) == 2; args[at] = old }
		}
	}
}
