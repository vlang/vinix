// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli
import os

fn multi_fixture(mut set PlanSet, first_mask int, second_mask int, kind u32) {
	for disk in 0 .. 2 {
		mut plan := Plan{key: DiskKey{bytes: 131072, sector: if disk == 0 { u64(512) } else { u64(4096) }, kind: if disk == 0 { kind } else { u32(3) - kind }}}
		plan.key.id[0] = u8(disk + 1); if plan.key.kind == 2 { plan.key.id[15] = 0x83 }
		for pool in 0 .. 2 { for cell in 0 .. 2 {
			mask := if pool == 0 { first_mask } else { second_mask }; bit := disk * 2 + cell
			if mask & (1 << bit) == 0 { continue }
			plan.rows[plan.count] = Request{slot: u32(pool * 4 + bit), offset: u64(8192 + pool * 24576 + cell * 4096), length: 4096, flags: u64(bit & 1)}
			plan.count++
		} }
		assert append_plan(mut set, &plan)
	}
	// Opposite member priorities, interleaved positions and two pools per disk.
	for at in 0 .. 4 {
		pool := at & 1; disk := if pool == 0 { 1 - at / 2 } else { at / 2 }
		region := PoolRegion{pool: u32(7 + pool), disk: u32(disk), window: SpaceWindow{start: u64(8192 + pool * 24576), end: u64(16384 + pool * 24576), alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	set.plans[63].key.id[0] = 91; set.windows[63] = PoolRegion{pool: 62}
}

fn multi_cell_oracle(pool int, mask int, cells int) (bool, int, u64) {
	for priority in 0 .. 2 {
		disk := if pool == 0 { 1 - priority } else { priority }
		for cell in 0 .. 2 {
			if cell + cells > 2 { continue }; mut free := true
			for part in 0 .. cells { if mask & (1 << (disk * 2 + cell + part)) != 0 { free = false } }
			if free { return true, disk, u64(8192 + pool * 24576 + cell * 4096) }
		}
	}
	return false, 0, 0
}

fn test_multi_pool_4096_independent_fragmentation_priority_and_whole_set_oracles() {
	for kind in [u32(1), 2] { for reverse in [false, true] { for first_mask in 0 .. 16 { for second_mask in 0 .. 16 {
		for first_cells in 1 .. 3 { for second_cells in 1 .. 3 {
			mut baseline := PlanSet{}; multi_fixture(mut baseline, first_mask, second_mask, kind)
			mut batch := MultiPoolBatch{count: 2}; mut expected := baseline; mut expected_result := PoolPlacements{count: 2}
			mut fits := true
			for i in 0 .. 2 {
				pool := if reverse { 1 - i } else { i }; mask := if pool == 0 { first_mask } else { second_mask }; cells := if pool == 0 { first_cells } else { second_cells }
				batch.pools[i] = u32(7 + pool); batch.rows[i] = Request{slot: u32(20 + pool), length: u64(cells * 4096), flags: u64(pool)}
				valid, disk, offset := multi_cell_oracle(pool, mask, cells)
				if !valid { fits = false; continue }
				row := Request{slot: u32(20 + pool), offset: offset, length: u64(cells * 4096), flags: u64(pool)}
				expected.plans[disk].rows[expected.plans[disk].count] = row; expected.plans[disk].count++; expected.slots |= u64(1) << row.slot
				expected_result.rows[i] = row; expected_result.disks[i] = u32(disk)
			}
			mut set := baseline; mut result := PoolPlacements{count: 17, keep: 42}; result.rows[63] = Request{slot: 63, length: 91}; old_result := result
			assert bundle_multi_pool_batch(mut set, &batch, mut result) == fits
			if !fits { assert set == baseline && result == old_result; continue }
			assert set == expected && result == expected_result
			assert bundle_multi_pool_batch(mut set, &batch, mut result) && set == expected
			expected_result.keep = 3; assert result == expected_result
		} }
	} } } }
}

fn test_multi_pool_interleaved_same_pool_requests_mixed_keeps_and_sector_alignment() {
	mut set := PlanSet{}; multi_fixture(mut set, 0, 0, 1)
	mut batch := MultiPoolBatch{count: 3}; batch.pools[0] = 7; batch.pools[1] = 8; batch.pools[2] = 7
	batch.rows[0] = Request{slot: 20, length: 4096, flags: 1}; batch.rows[1] = Request{slot: 21, length: 8192}; batch.rows[2] = Request{slot: 22, length: 8192}
	mut result := PoolPlacements{}; assert bundle_multi_pool_batch(mut set, &batch, mut result)
	assert result.disks[0] == 1 && result.disks[1] == 0 && result.disks[2] == 0
	assert result.rows[0].offset == 8192 && result.rows[1].offset == 32768 && result.rows[2].offset == 8192
	assert bundle_remove_row(mut set, 20)
	// A retry of an existing placement stays fixed; the omitted slot can be
	// reallocated without moving any other row, even in reverse request order.
	batch.rows[0] = Request{slot: 22, length: 8192}; batch.rows[2] = Request{slot: 20, length: 512, flags: 1}
	before := set; old_result := result
	assert !bundle_multi_pool_batch(mut set, &batch, mut result) && set == before && result == old_result
	set.windows[2].window = SpaceWindow{start: 8192, end: 20480, alignment: 4096}
	assert bundle_multi_pool_batch(mut set, &batch, mut result) && result.keep == 3
	assert result.disks[2] == 0 && result.rows[2].offset == 16384 && result.rows[2].length == 512
}

fn test_multi_pool_later_failures_retain_results_and_every_source_field() {
	mut baseline := PlanSet{}; multi_fixture(mut baseline, 0, 0, 2)
	for bad in 0 .. 12 {
		mut set := baseline; mut batch := MultiPoolBatch{count: 2}; batch.pools[0] = 7; batch.pools[1] = 8
		batch.rows[0] = Request{slot: 20, length: 4096}; batch.rows[1] = Request{slot: 21, length: 4096, flags: 1}
		match bad {
			0 { batch.count = -1 }
			1 { batch.count = 0 }
			2 { batch.count = 65 }
			3 { batch.pools[1] = 64 }
			4 { batch.pools[1] = 9 }
			5 { batch.rows[1].slot = 20 }
			6 { batch.rows[1].slot = 64 }
			7 { batch.rows[1].length = 0 }
			8 { batch.rows[1].length = 12288 }
			9 { batch.rows[1].flags = 2 }
			10 { batch.rows[1].offset = 4096 }
			else { batch.rows[1].version = 2 }
		}
		mut result := PoolPlacements{count: 17, keep: 42}; result.rows[63].length = 91; old_result := result
		assert !bundle_multi_pool_batch(mut set, &batch, mut result) && set == baseline && result == old_result
	}
	mut batch := MultiPoolBatch{count: 2}; batch.pools[0] = 7; batch.pools[1] = 8
	batch.rows[0] = Request{slot: 20, length: 4096}; batch.rows[1] = Request{slot: 21, length: 4096}
	mut set := baseline; mut result := PoolPlacements{}; assert bundle_multi_pool_batch(mut set, &batch, mut result)
	after := set; old_result := result
	for bad in 0 .. 3 { mut retry := batch
		if bad == 0 { retry.pools[1] = 7 } else if bad == 1 { retry.rows[1].flags = 1 } else { retry.rows[1].length = 8192 }
		assert !bundle_multi_pool_batch(mut set, &retry, mut result) && set == after && result == old_result
	}
}

fn test_maximum_multi_pool_batch_259_argument_cli_64_pools_full_v2_and_durable_retry() {
	work := os.join_path(os.temp_dir(), 'vinix-multi-pool-full-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut baseline := PlanSet{}; mut expected := PlanSet{}
	for disk in 0 .. 64 {
		sector := if disk & 1 == 0 { u64(512) } else { u64(4096) }; end := u64(-1) & ~(sector - 1)
		mut plan := Plan{key: DiskKey{bytes: end, sector: sector, kind: if disk & 1 == 0 { u32(1) } else { u32(2) }}}
		plan.key.id[0] = u8(disk + 1); if plan.key.kind == 2 { plan.key.id[15] = 0x83 }; assert append_plan(mut baseline, &plan)
		region := PoolRegion{pool: u32(disk), disk: u32(disk), window: SpaceWindow{start: (end - 8192) & ~u64(4095), end: end, alignment: 4096}}
		assert bundle_pool_add(mut baseline, &region)
	}
	assert publish_bundle(path.str, &baseline); original := os.read_bytes(path)!; unsafe { expected = *(&baseline) }
	unsafe {
		mut args := [260]&char{}; mut pools := [64][4]char{}; mut slots := [64][4]char{}
		args[0] = &char(c'vinix-volume'); args[1] = &char(c'pool-preview-set-batch'); args[2] = path.str
		for i in 0 .. 64 {
			disk := 63 - i; C.snprintf(&pools[i][0], 4, c'%u', u32(disk)); C.snprintf(&slots[i][0], 4, c'%u', u32(i))
			args[3 + i * 4] = &pools[i][0]; args[4 + i * 4] = &slots[i][0]; args[5 + i * 4] = &char(c'4096'); args[6 + i * 4] = if i & 1 == 0 { &char(c'ro') } else { &char(c'rw') }
			expected.plans[disk].count = 1; expected.plans[disk].rows[0] = Request{slot: u32(i), offset: baseline.windows[disk].window.start, length: 4096, flags: if i & 1 == 0 { u64(1) } else { u64(0) }}
		}
		expected.slots = u64(-1)
		assert run(259, &args[0]) == 0 && os.read_bytes(path)! == original
		args[1] = &char(c'pool-allocate-set-batch'); assert run(259, &args[0]) == 0
		bytes := os.read_bytes(path)!; mut decoded := PlanSet{}; assert bytes.len == 8768 && decode_bundle(bytes.data, bytes.len, mut decoded) && decoded == expected
		assert run(259, &args[0]) == 0 && os.read_bytes(path)! == bytes
	}
}

fn test_multi_pool_sources_and_complete_cli_tokens_fail_without_publication() {
	work := os.join_path(os.temp_dir(), 'vinix-multi-pool-input-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; mut set := PlanSet{}; multi_fixture(mut set, 0, 0, 1); assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!; mut batch := MultiPoolBatch{count: 1}; batch.pools[0] = 7; batch.rows[0] = Request{slot: 20, length: 4096}
	os.symlink(path, work + '/link')!
	for bad in [work, work + '/missing', work + '/link'] { for preview in [false, true] { assert multi_pool_batch_plan(bad.str, &batch, preview) == 1 } }
	mut damaged := original.clone(); damaged[24] ^= 1; os.write_file_array(path, damaged)!
	for preview in [false, true] { assert multi_pool_batch_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == damaged }
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-preview-set-batch'), &char(c'/unused'), &char(c'7'), &char(c'20'), &char(c'4096'), &char(c'ro'), &char(c'8'), &char(c'21'), &char(c'4096'), &char(c'rw'), &char(nil)]!
		for command in [c'pool-preview-set-batch', c'pool-allocate-set-batch'] {
			args[1] = &char(command); for count in [2, 3, 4, 5, 6, 8, 9, 10, 260, 263] { assert run(count, &args[0]) == 2 }
			for at in [3, 4, 5, 7, 8, 9] { old := args[at]; for bad in [c'', c'-1', c'1x', c'18446744073709551616'] { args[at] = &char(bad); assert run(11, &args[0]) == 2 }; args[at] = old }
			for at in [3, 4, 7, 8] { old := args[at]; args[at] = &char(c'64'); assert run(11, &args[0]) == 2; args[at] = old }
			for at in [5, 9] { old := args[at]; args[at] = &char(c'0'); assert run(11, &args[0]) == 2; args[at] = old }
			for at in [6, 10] { old := args[at]; args[at] = &char(c'RO'); assert run(11, &args[0]) == 2; args[at] = old }
		}
	}
}
