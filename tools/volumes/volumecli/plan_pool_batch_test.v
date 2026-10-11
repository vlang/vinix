// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn batch_fixture(mut set PlanSet) {
	for p in 0 .. 2 {
		mut plan := Plan{key: DiskKey{bytes: 32768, sector: if p == 0 { u64(4096) } else { u64(512) }, kind: 1}}
		plan.key.id[0] = u8(p + 1)
		assert append_plan(mut set, &plan)
	}
	for p in [1, 0] {
		region := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 4096, end: 12288, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
}

fn test_batch_places_in_request_and_member_order_preserves_modes_and_retries_without_relocation() {
	mut set := PlanSet{}
	batch_fixture(mut set)
	before := set
	mut batch := PoolBatch{count: 3}
	batch.rows[0] = Request{slot: 20, length: 512, flags: 1}
	batch.rows[1] = Request{slot: 10, length: 4096}
	batch.rows[2] = Request{slot: 30, length: 8192, flags: 1}
	mut placements := PoolPlacements{}
	assert bundle_pool_batch(mut set, 3, &batch, mut placements)
	assert placements.count == 3 && placements.keep == 0
	assert placements.disks[..3] == [u32(1), 1, 0]
	assert placements.rows[0] == Request{slot: 20, offset: 4096, length: 512, flags: 1}
	assert placements.rows[1] == Request{slot: 10, offset: 8192, length: 4096}
	assert placements.rows[2] == Request{slot: 30, offset: 4096, length: 8192, flags: 1}
	assert set.windows == before.windows && set.count == before.count
	assert set.plans[0].key == before.plans[0].key && set.plans[1].key == before.plans[1].key
	after := set
	assert bundle_pool_batch(mut set, 3, &batch, mut placements) && set == after
	assert placements.keep == 7 && placements.rows[0].offset == 4096
	// A matching existing row keeps its start even after earlier space is freed.
	assert bundle_remove_row(mut set, 20)
	mut mixed := PoolBatch{count: 2}
	mixed.rows[0] = batch.rows[1]
	mixed.rows[1] = Request{slot: 40, length: 4096, flags: 1}
	assert bundle_pool_batch(mut set, 3, &mixed, mut placements)
	assert placements.keep == 1 && placements.rows[0].offset == 8192
	assert placements.disks[1] == 1 && placements.rows[1].offset == 4096
}

fn test_batch_later_failures_preserve_complete_set_and_placement_outputs() {
	mut set := PlanSet{}
	batch_fixture(mut set)
	mut batch := PoolBatch{count: 2}
	batch.rows[0] = Request{slot: 20, length: 8192}
	batch.rows[1] = Request{slot: 21, length: 16384}
	mut placements := PoolPlacements{count: 9, keep: u64(-1)}
	placements.rows[63] = Request{slot: 63, offset: 999, length: 99}
	placements.disks[63] = 99
	previous := placements
	before := set
	assert !bundle_pool_batch(mut set, 3, &batch, mut placements) && set == before && placements == previous
	for bad in [Request{slot: 20, length: 4096}, Request{slot: 64, length: 4096},
		Request{slot: 21, length: 0}, Request{slot: 21, length: 4096, flags: 2},
		Request{slot: 21, length: 4096, version: 2}, Request{slot: 21, offset: 512, length: 4096},
		Request{slot: 21, length: u64(-1)}, Request{slot: 21, length: 4097}] {
		batch.rows[1] = bad
		assert !bundle_pool_batch(mut set, 3, &batch, mut placements) && set == before && placements == previous
	}
	for count in [-1, 0, 65] {
		batch.count = count
		assert !bundle_pool_batch(mut set, 3, &batch, mut placements) && set == before && placements == previous
	}
	batch.count = 1
	for pool in [u32(2), 64] {
		assert !bundle_pool_batch(mut set, pool, &batch, mut placements) && set == before && placements == previous
	}
	assert bundle_pool_batch(mut set, 3, &batch, mut placements)
	owned := set
	for bad in [Request{slot: 20, length: 4096}, Request{slot: 20, length: 8192, flags: 1}] {
		batch.rows[0] = bad
		assert !bundle_pool_batch(mut set, 3, &batch, mut placements) && set == owned
	}
	batch.rows[0] = Request{slot: 20, length: 8192}
	assert bundle_pool_remove(mut set, 3, 1)
	outside := set
	assert !bundle_pool_batch(mut set, 3, &batch, mut placements) && set == outside
	// An existing mapping straddling a member is not an idempotent allocation.
	region := PoolRegion{pool: 3, disk: 1, window: SpaceWindow{start: 8192, end: 16384, alignment: 4096}}
	assert bundle_pool_add(mut set, &region)
	straddling := set
	assert !bundle_pool_batch(mut set, 3, &batch, mut placements) && set == straddling
}

// Cell scanning uses neither the gap enumerator nor the allocator. Earlier
// placements occupy cells before later requests are considered, across disks.
fn test_batch_matches_independent_two_request_fragmentation_oracle() {
	for first_mask in 0 .. 16 {
		for second_mask in 0 .. 16 {
			mut set := PlanSet{}
			mut occupied := [2][8]bool{}
			for p in 0 .. 2 {
				mut plan := Plan{key: DiskKey{bytes: 8192, sector: 512, kind: 1}}
				plan.key.id[0] = u8(p + 1)
				mask := if p == 0 { first_mask } else { second_mask }
				for bit in 0 .. 4 {
					if mask & (1 << bit) == 0 { continue }
					occupied[p][bit * 2] = true
					plan.rows[plan.count] = Request{slot: u32(p * 8 + bit), offset: u64(2 + bit * 2) * 512, length: 512}
					plan.count++
				}
				assert append_plan(mut set, &plan)
			}
			for p in [1, 0] {
				region := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 1024, end: 5120,
					alignment: if p == 0 { u64(1024) } else { u64(2048) }}}
				assert bundle_pool_add(mut set, &region)
			}
			for first_length in 1 .. 5 {
				for second_length in 1 .. 5 {
					mut cells := occupied
					mut expected_disks := [2]u32{}
					mut expected_offsets := [2]u64{}
					mut fits := true
					lengths := [first_length, second_length]!
					for i in 0 .. 2 {
						mut found := false
						for p in [1, 0] {
							if found { break }
							alignment := if p == 0 { 1024 } else { 2048 }
							for start in 0 .. 8 {
								if (start + 2) * 512 % alignment != 0 || start + lengths[i] > 8 { continue }
								mut free := true
								for at in start .. start + lengths[i] { if cells[p][at] { free = false } }
								if !free { continue }
								for at in start .. start + lengths[i] { cells[p][at] = true }
								expected_disks[i] = u32(p)
								expected_offsets[i] = u64(start + 2) * 512
								found = true
								break
							}
						}
						if !found { fits = false; break }
					}
					mut batch := PoolBatch{count: 2}
					for i in 0 .. 2 { batch.rows[i] = Request{slot: u32(50 + i), length: u64(lengths[i]) * 512, flags: u64(i)} }
					mut trial := set
					mut placements := PoolPlacements{count: 9, keep: 99}
					previous := placements
					assert bundle_pool_batch(mut trial, 3, &batch, mut placements) == fits
					if !fits { assert trial == set && placements == previous; continue }
					assert placements.count == 2 && placements.keep == 0 && trial.windows == set.windows
					for i in 0 .. 2 {
						assert placements.disks[i] == expected_disks[i] && placements.rows[i].offset == expected_offsets[i]
						assert placements.rows[i].slot == u32(50 + i) && placements.rows[i].length == u64(lengths[i]) * 512
						assert placements.rows[i].flags == u64(i)
					}
					for p in 0 .. 2 {
						assert trial.plans[p].key == set.plans[p].key
						for at := u32(0); at < set.plans[p].count; at++ { assert trial.plans[p].rows[at] == set.plans[p].rows[at] }
					}
				}
			}
		}
	}
}

fn test_batch_full_slots_disks_and_near_u64_regions_roundtrip_and_retry() {
	mut set := PlanSet{}
	mut batch := PoolBatch{count: 64}
	for p in 0 .. 64 {
		mut plan := Plan{key: DiskKey{bytes: u64(-1) & ~u64(511), sector: 512, kind: 1}}
		plan.key.id[0] = u8(p + 1)
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 63, disk: u32(p), window: SpaceWindow{start: plan.key.bytes - 512, end: plan.key.bytes, alignment: 512}}
		assert bundle_pool_add(mut set, &region)
		batch.rows[p] = Request{slot: u32(63 - p), length: 512, flags: u64(p & 1)}
	}
	mut placements := PoolPlacements{}
	assert bundle_pool_batch(mut set, 63, &batch, mut placements) && set.slots == u64(-1)
	for p in 0 .. 64 { assert placements.disks[p] == u32(p) && placements.rows[p].offset == set.plans[p].key.bytes - 512 }
	mut bytes := [8768]u8{}
	assert encode_bundle(&set, &bytes[0]) == 8768
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], 8768, mut decoded) && decoded == set
	assert bundle_pool_batch(mut set, 63, &batch, mut placements) && set == decoded && placements.keep == u64(-1)
	work := os.join_path(os.temp_dir(), 'vinix-pool-batch-full-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/full.vset'
	assert publish_bundle(path.str, &set)
	unsafe {
		mut args := [197]&char{}
		mut numbers := [64][4]char{}
		args[0] = &char(c'vinix-volume'); args[1] = &char(c'pool-allocate-batch')
		args[2] = path.str; args[3] = &char(c'63')
		for i in 0 .. 64 {
			C.snprintf(&numbers[i][0], 4, c'%u', batch.rows[i].slot)
			args[4 + i * 3] = &numbers[i][0]; args[5 + i * 3] = &char(c'512')
			args[6 + i * 3] = if i & 1 == 0 { &char(c'rw') } else { &char(c'ro') }
		}
		assert run(196, &args[0]) == 0 && os.read_bytes(path)! == bytes[..]
	}
}

fn test_batch_keeps_manual_sector_aligned_row_and_rejects_invalid_complete_sets() {
	mut set := PlanSet{}
	batch_fixture(mut set)
	row := Request{slot: 20, offset: 4608, length: 512, flags: 1}
	assert bundle_add_row(mut set, 1, &row) // Placement alignment is for new rows.
	mut batch := PoolBatch{count: 1}
	batch.rows[0] = Request{slot: 20, length: 512, flags: 1}
	mut placements := PoolPlacements{}
	before := set
	assert bundle_pool_batch(mut set, 3, &batch, mut placements) && set == before
	assert placements.keep == 1 && placements.rows[0] == row && placements.disks[0] == 1
	set.windows[0].window = SpaceWindow{start: 4096, end: 12289, alignment: 4096}
	invalid := set
	previous := placements
	assert !bundle_pool_batch(mut set, 3, &batch, mut placements) && set == invalid && placements == previous
	set = before
	set.plans[0].key = set.plans[1].key
	duplicate := set
	assert !bundle_pool_batch(mut set, 3, &batch, mut placements) && set == duplicate && placements == previous
}

fn test_batch_commands_preview_without_publication_and_reject_bad_files_and_cli_arguments() {
	work := os.join_path(os.temp_dir(), 'vinix-pool-batch-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/pool.vset'
	mut set := PlanSet{}
	batch_fixture(mut set)
	assert publish_bundle(path.str, &set)
	before := os.read_bytes(path)!
	mut batch := PoolBatch{count: 2}
	batch.rows[0] = Request{slot: 20, length: 8192, flags: 1}
	batch.rows[1] = Request{slot: 21, length: 8192}
	assert batch_pool_plan(path.str, 3, &batch, true) == 0 && os.read_bytes(path)! == before && os.ls(work)!.len == 1
	assert batch_pool_plan(path.str, 3, &batch, false) == 0
	mut decoded := PlanSet{}
	after := os.read_bytes(path)!
	assert decode_bundle(after.data, after.len, mut decoded) && decoded.plans[1].rows[0].slot == 20 && decoded.plans[0].rows[0].slot == 21
	assert batch_pool_plan(path.str, 3, &batch, false) == 0 && os.read_bytes(path)! == after
	os.symlink(path, work + '/link')!
	for input in [work + '/link', work + '/missing', work] {
		for preview in [false, true] { assert batch_pool_plan(input.str, 3, &batch, preview) == 1 }
	}
	mut broken := after.clone()
	broken[24] ^= 1
	os.write_file_array(path, broken)!
	for preview in [false, true] { assert batch_pool_plan(path.str, 3, &batch, preview) == 1 && os.read_bytes(path)! == broken }
	unsafe {
		mut args := [197]&char{}
		args[0] = &char(c'vinix-volume')
		args[2] = &char(c'/unused')
		args[3] = &char(c'3')
		args[4] = &char(c'20'); args[5] = &char(c'8192'); args[6] = &char(c'ro')
		for command in [c'pool-allocate-batch', c'pool-preview-batch'] {
			args[1] = &char(command)
			for argc in [2, 4, 6, 8, 197] { assert run(argc, &args[0]) == 2 }
			for index in [3, 4, 5] {
				previous := args[index]
				for bad in [c'', c'-1', c'1x', c'18446744073709551616'] { args[index] = &char(bad); assert run(7, &args[0]) == 2 }
				args[index] = previous
			}
			for index in [3, 4] { previous := args[index]; args[index] = &char(c'64'); assert run(7, &args[0]) == 2; args[index] = previous }
			for bad in [c'', c'RO', c'1', c'grow'] { args[6] = &char(bad); assert run(7, &args[0]) == 2 }
			args[6] = &char(c'ro'); args[5] = &char(c'0'); assert run(7, &args[0]) == 2; args[5] = &char(c'8192')
		}
	}
}
