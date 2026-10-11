// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn expansion_batch_fixture(mut set PlanSet) {
	for p in 0 .. 2 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 32768,
			sector: if p == 0 { u64(512) } else { u64(4096) }, kind: 1}}
		plan.key.id[0] = u8(p + 1)
		plan.rows[0] = Request{slot: u32(2 + p * 7), offset: if p == 0 { u64(12288) } else { u64(4096) },
			length: 4096, flags: u64(p ^ 1)}
		assert append_plan(mut set, &plan)
	}
	for p in [1, 0] {
		region := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 4096, end: 8192, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	other := PoolRegion{pool: 6, disk: 1, window: SpaceWindow{start: 24576, end: 32768, alignment: 4096}}
	assert bundle_pool_add(mut set, &other)
}

fn test_expansion_batch_preserves_all_rows_identity_member_priority_and_reports_requested_order() {
	mut set := PlanSet{}
	expansion_batch_fixture(mut set)
	before := set
	mut batch := PoolExpansionBatch{count: 2}
	batch.disks[0] = 0; batch.ends[0] = 16384
	batch.disks[1] = 1; batch.ends[1] = 12288
	mut result := PoolExpansionResults{}
	assert bundle_pool_expand_batch(mut set, 3, &batch, mut result)
	assert result.count == 2 && result.previous[..2] == [u64(8192), 8192]
	assert result.rows[0] == PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096, end: 16384, alignment: 4096}}
	assert result.rows[1] == PoolRegion{pool: 3, disk: 1, window: SpaceWindow{start: 4096, end: 12288, alignment: 4096}}
	mut expected := before
	expected.windows[0] = result.rows[1]; expected.windows[1] = result.rows[0]
	assert set == expected
	// A desired row in newly eligible space reduces capacity; expansion keeps it.
	mut total := PoolSpace{}
	assert bundle_pool_space(&set, 3, mut total) && total.bytes_high == 0 && total.bytes_low == 12288
	assert bundle_pool_expand_batch(mut set, 3, &batch, mut result) && set == expected
	assert result.previous[..2] == [u64(16384), 12288]
	set = before; batch.ends[1] = 8192
	assert bundle_pool_expand_batch(mut set, 3, &batch, mut result)
	assert result.rows[1] == before.windows[0] && result.previous[1] == 8192
	// Expansion up to another region's start is valid and retains all 3 records.
	batch.ends[1] = 24576
	assert bundle_pool_expand_batch(mut set, 3, &batch, mut result) && set.regions == 3
}

fn test_expansion_batch_later_failure_preserves_complete_set_and_caller_output() {
	mut set := PlanSet{}
	expansion_batch_fixture(mut set)
	before := set
	mut batch := PoolExpansionBatch{count: 2}
	batch.disks[0] = 0; batch.ends[0] = 16384; batch.disks[1] = 1
	mut output := PoolExpansionResults{count: 19}
	output.previous[63] = 77; output.rows[63] = before.windows[2]
	previous := output
	for end in [u64(0), 4096, 8193, 28672, 36864, u64(-1)] {
		batch.ends[1] = end
		assert !bundle_pool_expand_batch(mut set, 3, &batch, mut output) && set == before && output == previous
	}
	batch.ends[1] = 12288
	for disk in [u32(0), 2, 64] {
		batch.disks[1] = disk
		assert !bundle_pool_expand_batch(mut set, 3, &batch, mut output) && set == before && output == previous
	}
	batch.disks[1] = 1
	for pool in [u32(4), 64] { assert !bundle_pool_expand_batch(mut set, pool, &batch, mut output) && set == before && output == previous }
	for count in [-1, 0, 65] {
		batch.count = count
		assert !bundle_pool_expand_batch(mut set, 3, &batch, mut output) && set == before && output == previous
	}
	batch.count = 2
	set.windows[0].window = SpaceWindow{start: 4096, end: 8193, alignment: 4096}
	invalid := set
	assert !bundle_pool_expand_batch(mut set, 3, &batch, mut output) && set == invalid && output == previous
}

// Enumerate occupied eligibility cells independently. Desired mappings are not
// pool reservations, and an existing row straddles the previous region end.
fn test_expansion_batch_matches_independent_cell_oracle_for_6400_attempts() {
	for first_mask in 0 .. 16 {
		for second_mask in 0 .. 16 {
			mut set := PlanSet{}
			for p in 0 .. 2 {
				mut plan := Plan{count: 1, key: DiskKey{bytes: 8192, sector: 512, kind: 1}}
				plan.key.id[0] = u8(p + 1)
				plan.rows[0] = Request{slot: u32(p), offset: 1536, length: 1024, flags: u64(p)}
				assert append_plan(mut set, &plan)
			}
			for p in [1, 0] {
				region := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 512, end: 2048, alignment: 512}}
				assert bundle_pool_add(mut set, &region)
			}
			masks := [first_mask, second_mask]!
			for p in 0 .. 2 {
				for bit in 0 .. 4 {
					if masks[p] & (1 << bit) == 0 { continue }
					region := PoolRegion{pool: u32(20 + bit), disk: u32(p),
						window: SpaceWindow{start: u64(4 + bit) * 512, end: u64(5 + bit) * 512, alignment: 512}}
					assert bundle_pool_add(mut set, &region)
				}
			}
			for first_end in 4 .. 9 {
				for second_end in 4 .. 9 {
					ends := [first_end, second_end]!
					mut fits := true
					for p in 0 .. 2 { for cell in 4 .. ends[p] { if masks[p] & (1 << (cell - 4)) != 0 { fits = false } } }
					mut trial := set
					mut batch := PoolExpansionBatch{count: 2}
					for p in 0 .. 2 { batch.disks[p] = u32(p); batch.ends[p] = u64(ends[p]) * 512 }
					mut result := PoolExpansionResults{count: 7}
					previous := result
					assert bundle_pool_expand_batch(mut trial, 3, &batch, mut result) == fits
					if !fits { assert trial == set && result == previous; continue }
					mut expected := set
					for p in 0 .. 2 {
						row := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 512, end: batch.ends[p], alignment: 512}}
						assert result.rows[p] == row && result.previous[p] == 2048
						expected.windows[1 - p] = row
					}
					assert trial == expected
				}
			}
		}
	}
}

fn test_maximum_expansion_batch_near_u64_keeps_full_region_table_and_all_64_cli_pairs() {
	mut set := PlanSet{}
	mut batch := PoolExpansionBatch{count: 64}
	for p in 0 .. 64 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~u64(511), sector: 512, kind: 1}}
		plan.key.id[0] = u8(p + 1)
		plan.rows[0] = Request{slot: u32(p), offset: plan.key.bytes - 512, length: 512, flags: u64(p & 1)}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 63, disk: u32(p), window: SpaceWindow{start: plan.key.bytes - 1536, end: plan.key.bytes - 1024, alignment: 512}}
		assert bundle_pool_add(mut set, &region)
		batch.disks[63 - p] = u32(p); batch.ends[63 - p] = plan.key.bytes
	}
	before := set
	mut result := PoolExpansionResults{}
	assert bundle_pool_expand_batch(mut set, 63, &batch, mut result) && set.regions == 64
	assert set.plans == before.plans && set.slots == before.slots
	for i in 0 .. 64 { assert result.rows[i] == set.windows[63 - i] && result.previous[i] == set.plans[63 - i].key.bytes - 1024 }
	mut bytes := [8768]u8{}
	assert encode_bundle(&set, &bytes[0]) == 8768
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], 8768, mut decoded) && decoded == set
	work := os.join_path(os.temp_dir(), 'vinix-expand-batch-full-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/full.vset'
	assert publish_bundle(path.str, &set)
	unsafe {
		mut args := [133]&char{}
		mut disks := [64][4]char{}; mut ends := [64][21]char{}
		args[0] = &char(c'vinix-volume'); args[1] = &char(c'pool-expand-batch'); args[2] = path.str; args[3] = &char(c'63')
		for i in 0 .. 64 {
			C.snprintf(&disks[i][0], 4, c'%u', batch.disks[i]); C.snprintf(&ends[i][0], 21, c'%lu', batch.ends[i])
			args[4 + i * 2] = &disks[i][0]; args[5 + i * 2] = &ends[i][0]
		}
		assert run(132, &args[0]) == 0 && os.read_bytes(path)! == bytes[..]
	}
}

fn test_expansion_batch_files_lock_writers_allow_preview_and_validate_inputs_and_cli() {
	work := os.join_path(os.temp_dir(), 'vinix-expand-batch-file-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	expansion_batch_fixture(mut set)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	mut batch := PoolExpansionBatch{count: 2}
	batch.disks[0] = 0; batch.ends[0] = 16384; batch.disks[1] = 1; batch.ends[1] = 12288
	mut edit := PlanEdit{}
	assert open_plan_edit(path.str, mut edit, true)
	assert expand_batch_pool_plan(path.str, 3, &batch, false) == 1
	assert expand_batch_pool_plan(path.str, 3, &batch, true) == 0 && os.read_bytes(path)! == original && os.ls(work)!.len == 1
	close_plan_edit(mut edit)
	assert expand_batch_pool_plan(path.str, 3, &batch, false) == 0
	expanded := os.read_bytes(path)!
	assert expanded != original && expand_batch_pool_plan(path.str, 3, &batch, false) == 0 && os.read_bytes(path)! == expanded
	batch.ends[1] = 28672
	for preview in [false, true] { assert expand_batch_pool_plan(path.str, 3, &batch, preview) == 1 && os.read_bytes(path)! == expanded }
	os.symlink(path, work + '/link')!
	for input in [work + '/link', work + '/missing', work] { for preview in [false, true] { assert expand_batch_pool_plan(input.str, 3, &batch, preview) == 1 } }
	mut broken := expanded.clone(); broken[24] ^= 1
	os.write_file_array(path, broken)!
	for preview in [false, true] { assert expand_batch_pool_plan(path.str, 3, &batch, preview) == 1 && os.read_bytes(path)! == broken }
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-expand-batch'), &char(c'/unused'), &char(c'3'), &char(c'0'), &char(c'16384'), &char(c'1'), &char(c'12288'), &char(nil)]!
		for command in [c'pool-expand-batch', c'pool-preview-expand-batch'] {
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
