// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn growth_batch_fixture(mut set PlanSet) {
	for p in 0 .. 2 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 32768,
			sector: if p == 0 { u64(512) } else { u64(4096) }, kind: 1}}
		plan.key.id[0] = u8(p + 1)
		plan.rows[0] = Request{slot: if p == 0 { u32(2) } else { u32(9) },
			offset: 4096, length: 4096, flags: u64(p ^ 1)}
		if p == 0 { plan.rows[1] = Request{slot: 5, offset: 12288, length: 4096}; plan.count++ }
		assert append_plan(mut set, &plan)
	}
	for p in [1, 0] {
		region := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 4096, end: 16384, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
}

fn test_growth_batch_preserves_rows_modes_order_identity_and_reports_all_requests_and_retries() {
	mut set := PlanSet{}
	growth_batch_fixture(mut set)
	before := set
	mut batch := PoolGrowthBatch{count: 2}
	batch.slots[0] = 9; batch.lengths[0] = 12288
	batch.slots[1] = 2; batch.lengths[1] = 8192
	mut result := PoolGrowthResults{}
	assert bundle_pool_grow_batch(mut set, 3, &batch, mut result)
	assert result.count == 2 && result.disks[..2] == [u32(1), 0]
	assert result.previous[..2] == [u64(4096), 4096]
	assert result.rows[0] == Request{slot: 9, offset: 4096, length: 12288}
	assert result.rows[1] == Request{slot: 2, offset: 4096, length: 8192, flags: 1}
	assert set.windows == before.windows && set.slots == before.slots && set.count == before.count
	for p in 0 .. 2 { assert set.plans[p].key == before.plans[p].key && set.plans[p].count == before.plans[p].count }
	assert set.plans[0].rows[1] == before.plans[0].rows[1]
	after := set
	assert bundle_pool_grow_batch(mut set, 3, &batch, mut result) && set == after
	assert result.previous[..2] == [u64(12288), 8192]
	// Mixed unchanged/growth requests retain the same start and mode.
	set = before
	batch.lengths[0] = 4096
	assert bundle_pool_grow_batch(mut set, 3, &batch, mut result)
	assert result.previous[0] == result.rows[0].length && result.rows[1].length == 8192
}

fn test_growth_batch_later_failure_leaves_entire_set_and_caller_results_unchanged() {
	mut set := PlanSet{}
	growth_batch_fixture(mut set)
	mut batch := PoolGrowthBatch{count: 2}
	batch.slots[0] = 9; batch.lengths[0] = 8192
	batch.slots[1] = 2
	mut results := PoolGrowthResults{count: 17}
	results.rows[63] = Request{slot: 63, length: 99}
	results.previous[63] = 55; results.disks[63] = 44
	before := set
	previous := results
	for length in [u64(0), 512, 4097, 12288, 16384, u64(-1)] {
		batch.lengths[1] = length
		assert !bundle_pool_grow_batch(mut set, 3, &batch, mut results) && set == before && results == previous
	}
	batch.lengths[1] = 8192
	for slot in [u32(9), 20, 64] {
		batch.slots[1] = slot
		assert !bundle_pool_grow_batch(mut set, 3, &batch, mut results) && set == before && results == previous
	}
	batch.slots[1] = 2
	for pool in [u32(4), 64] { assert !bundle_pool_grow_batch(mut set, pool, &batch, mut results) && set == before && results == previous }
	for count in [-1, 0, 65] {
		batch.count = count
		assert !bundle_pool_grow_batch(mut set, 3, &batch, mut results) && set == before && results == previous
	}
	batch.count = 2
	set.windows[1].window = SpaceWindow{start: 8192, end: 16384, alignment: 4096} // Existing row starts outside its member.
	outside := set
	assert !bundle_pool_grow_batch(mut set, 3, &batch, mut results) && set == outside && results == previous
	set = before
	set.windows[1].window = SpaceWindow{start: 4096, end: 4097, alignment: 4096}
	invalid := set
	assert !bundle_pool_grow_batch(mut set, 3, &batch, mut results) && set == invalid && results == previous
}

// Each independent cell oracle scans only the extension after the existing
// row. The second disk's failure must roll back even a feasible first growth.
fn test_growth_batches_match_two_disk_sector_oracle_for_4096_fragmentation_attempts() {
	for first_mask in 0 .. 16 {
		for second_mask in 0 .. 16 {
			mut set := PlanSet{}
			for p in 0 .. 2 {
				mut plan := Plan{count: 1, key: DiskKey{bytes: 8192, sector: 512, kind: 1}}
				plan.key.id[0] = u8(p + 1)
				plan.rows[0] = Request{slot: u32(p), offset: 1024, length: 512, flags: u64(p)}
				mask := if p == 0 { first_mask } else { second_mask }
				for bit in 0 .. 4 {
					if mask & (1 << bit) != 0 {
						plan.rows[plan.count] = Request{slot: u32(10 + p * 4 + bit), offset: u64(3 + bit) * 512, length: 512}
						plan.count++
					}
				}
				assert append_plan(mut set, &plan)
			}
			for p in [1, 0] {
				region := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 1024, end: 5120, alignment: 1024}}
				assert bundle_pool_add(mut set, &region)
			}
			for first in 1 .. 5 {
				for second in 1 .. 5 {
					lengths := [first, second]!
					masks := [first_mask, second_mask]!
					mut fits := true
					for p in 0 .. 2 {
						for cell in 1 .. lengths[p] { if masks[p] & (1 << (cell - 1)) != 0 { fits = false } }
					}
					mut trial := set
					mut batch := PoolGrowthBatch{count: 2}
					for i in 0 .. 2 { batch.slots[i] = u32(i); batch.lengths[i] = u64(lengths[i]) * 512 }
					mut results := PoolGrowthResults{count: 7}
					previous := results
					assert bundle_pool_grow_batch(mut trial, 3, &batch, mut results) == fits
					if !fits { assert trial == set && results == previous; continue }
					assert trial.windows == set.windows && trial.slots == set.slots
					for p in 0 .. 2 {
						assert results.disks[p] == u32(p) && results.previous[p] == 512
						assert results.rows[p] == Request{slot: u32(p), offset: 1024, length: u64(lengths[p]) * 512, flags: u64(p)}
						assert trial.plans[p].key == set.plans[p].key && trial.plans[p].count == set.plans[p].count
						for at := u32(1); at < set.plans[p].count; at++ { assert trial.plans[p].rows[at] == set.plans[p].rows[at] }
					}
				}
			}
		}
	}
}

fn test_maximum_growth_batch_near_u64_roundtrips_and_accepts_all_64_cli_pairs() {
	mut set := PlanSet{}
	mut batch := PoolGrowthBatch{count: 64}
	for p in 0 .. 64 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~u64(511), sector: 512, kind: 1}}
		plan.key.id[0] = u8(p + 1)
		plan.rows[0] = Request{slot: u32(63 - p), offset: plan.key.bytes - 1024, length: 512, flags: u64(p & 1)}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 63, disk: u32(p), window: SpaceWindow{start: plan.key.bytes - 1024, end: plan.key.bytes, alignment: 512}}
		assert bundle_pool_add(mut set, &region)
		batch.slots[p] = u32(63 - p); batch.lengths[p] = 1024
	}
	mut results := PoolGrowthResults{}
	assert bundle_pool_grow_batch(mut set, 63, &batch, mut results) && set.slots == u64(-1)
	for p in 0 .. 64 { assert results.disks[p] == u32(p) && results.rows[p].length == 1024 && results.previous[p] == 512 }
	mut bytes := [8768]u8{}
	assert encode_bundle(&set, &bytes[0]) == 8768
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], 8768, mut decoded) && decoded == set
	assert bundle_pool_grow_batch(mut set, 63, &batch, mut results) && set == decoded
	work := os.join_path(os.temp_dir(), 'vinix-grow-batch-full-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/full.vset'
	assert publish_bundle(path.str, &set)
	unsafe {
		mut args := [133]&char{}
		mut numbers := [64][4]char{}
		args[0] = &char(c'vinix-volume'); args[1] = &char(c'pool-grow-batch'); args[2] = path.str; args[3] = &char(c'63')
		for i in 0 .. 64 { C.snprintf(&numbers[i][0], 4, c'%u', batch.slots[i]); args[4 + i * 2] = &numbers[i][0]; args[5 + i * 2] = &char(c'1024') }
		assert run(132, &args[0]) == 0 && os.read_bytes(path)! == bytes[..]
	}
}

fn test_growth_batch_files_lock_writers_allow_previews_and_reject_corrupt_inputs_and_cli_pairs() {
	work := os.join_path(os.temp_dir(), 'vinix-grow-batch-file-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	growth_batch_fixture(mut set)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	mut batch := PoolGrowthBatch{count: 2}
	batch.slots[0] = 2; batch.lengths[0] = 8192; batch.slots[1] = 9; batch.lengths[1] = 8192
	mut edit := PlanEdit{}
	assert open_plan_edit(path.str, mut edit, true)
	assert grow_batch_pool_plan(path.str, 3, &batch, false) == 1
	assert grow_batch_pool_plan(path.str, 3, &batch, true) == 0 && os.read_bytes(path)! == original && os.ls(work)!.len == 1
	close_plan_edit(mut edit)
	assert grow_batch_pool_plan(path.str, 3, &batch, false) == 0
	grown := os.read_bytes(path)!
	assert grown != original && grow_batch_pool_plan(path.str, 3, &batch, false) == 0 && os.read_bytes(path)! == grown
	batch.lengths[1] = 16384
	for preview in [false, true] { assert grow_batch_pool_plan(path.str, 3, &batch, preview) == 1 && os.read_bytes(path)! == grown }
	os.symlink(path, work + '/link')!
	for input in [work + '/link', work + '/missing', work] {
		for preview in [false, true] { assert grow_batch_pool_plan(input.str, 3, &batch, preview) == 1 }
	}
	mut broken := grown.clone(); broken[24] ^= 1
	os.write_file_array(path, broken)!
	for preview in [false, true] { assert grow_batch_pool_plan(path.str, 3, &batch, preview) == 1 && os.read_bytes(path)! == broken }
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-grow-batch'), &char(c'/unused'), &char(c'3'), &char(c'2'), &char(c'8192'), &char(c'9'), &char(c'8192'), &char(nil)]!
		for command in [c'pool-grow-batch', c'pool-preview-grow-batch'] {
			args[1] = &char(command)
			for count in [4, 5, 7, 134] { assert run(count, &args[0]) == 2 }
			for index in [3, 4, 5, 6, 7] {
				previous := args[index]
				for bad in [c'', c'-1', c'1x', c'18446744073709551616'] { args[index] = &char(bad); assert run(8, &args[0]) == 2 }
				args[index] = previous
			}
			for index in [3, 4, 6] { previous := args[index]; args[index] = &char(c'64'); assert run(8, &args[0]) == 2; args[index] = previous }
			for index in [5, 7] { previous := args[index]; args[index] = &char(c'0'); assert run(8, &args[0]) == 2; args[index] = previous }
		}
	}
}
