// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn pool_growth_set(mut set PlanSet) {
	mut first := Plan{count: 2, key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
	first.key.id[0] = 1
	first.rows[0] = Request{slot: 2, offset: 4096, length: 4096, flags: 1}
	first.rows[1] = Request{slot: 5, offset: 12288, length: 4096}
	mut second := Plan{count: 1, key: DiskKey{bytes: 32768, sector: 4096, kind: 1}}
	second.key.id[0] = 2
	second.rows[0] = Request{slot: 9, offset: 4096, length: 4096}
	assert append_plan(mut set, &first) && append_plan(mut set, &second)
	for region in [PoolRegion{pool: 3, disk: 1, window: SpaceWindow{start: 4096, end: 16384, alignment: 4096}},
		PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096, end: 8192, alignment: 4096}},
		PoolRegion{pool: 4, disk: 0, window: SpaceWindow{start: 16384, end: 20480, alignment: 4096}}] {
		assert bundle_pool_add(mut set, &region)
	}
}

fn test_pool_expansion_preserves_member_priority_mappings_and_rejects_invalid_endpoints_atomically() {
	mut set := PlanSet{}
	pool_growth_set(mut set)
	before := set
	assert bundle_pool_expand(mut set, 3, 0, 12288)
	assert set.plans == before.plans && set.slots == before.slots && set.regions == before.regions
	assert set.windows[0] == before.windows[0] && set.windows[2] == before.windows[2]
	assert set.windows[1].window == SpaceWindow{start: 4096, end: 12288, alignment: 4096}
	assert bundle_pool_expand(mut set, 3, 0, 12288)
	after := set
	for end in [u64(0), 4096, 8192, 12287, 12289, 16896, 33280, u64(-1)] {
		assert !bundle_pool_expand(mut set, 3, 0, end) && set == after
	}
	for pool, disk in {3: u32(2), 4: 1, 5: 0, 64: 0} {
		assert !bundle_pool_expand(mut set, u32(pool), disk, 16384) && set == after
	}
	assert bundle_pool_expand(mut set, 3, 0, 16384) // Adjacent other pool is valid.
	// Expansion includes occupied desired rows; it does not claim their bytes free.
	mut space := PoolSpace{}
	assert bundle_pool_space(&set, 3, mut space) && space.bytes_low == 12288
	mut chosen := Request{}
	mut disk := u32(99)
	row := Request{slot: 20, length: 4096}
	assert bundle_pool_allocate(mut set, 3, &row, unsafe { &disk }, mut chosen)
	assert disk == 1 && chosen.offset == 8192 // Member order survives expansion.
}

fn test_pool_mapping_growth_requires_own_member_and_contiguous_bounds_preserves_modes_and_failure_outputs() {
	mut set := PlanSet{}
	pool_growth_set(mut set)
	mut disk := u32(99)
	before := set
	assert !bundle_pool_grow(mut set, 3, 2, 8192, unsafe { &disk }) && set == before && disk == 99
	assert bundle_pool_expand(mut set, 3, 0, 12288)
	pre_growth := set
	assert bundle_pool_grow(mut set, 3, 2, 8192, unsafe { &disk }) && disk == 0
	assert set.plans[0].rows[0] == Request{slot: 2, offset: 4096, length: 8192, flags: 1}
	assert set.plans[0].rows[1] == pre_growth.plans[0].rows[1] && set.plans[1] == pre_growth.plans[1]
	assert set.windows == pre_growth.windows && set.slots == pre_growth.slots
	assert bundle_pool_grow(mut set, 3, 2, 8192, unsafe { &disk })
	after := set
	for length in [u64(0), 4096, 8193, 12288, u64(-1)] {
		assert !bundle_pool_grow(mut set, 3, 2, length, unsafe { &disk }) && set == after && disk == 0
	}
	for pool, slot in {3: u32(20), 4: 2, 5: 9, 64: 2} {
		assert !bundle_pool_grow(mut set, u32(pool), slot, 8192, unsafe { &disk }) && set == after && disk == 0
	}
	assert !bundle_pool_grow(mut set, 3, 64, 8192, unsafe { &disk }) && set == after
	assert !bundle_pool_grow(mut set, 3, 9, 4608, unsafe { &disk }) && set == after
	assert bundle_pool_grow(mut set, 3, 9, 8192, unsafe { &disk }) && disk == 1
	assert bundle_pool_expand(mut set, 3, 0, 16384)
	blocked := set
	assert !bundle_pool_grow(mut set, 3, 2, 12288, unsafe { &disk }) && set == blocked // Desired-row overlap.
	// A mapping straddling eligibility cannot be admitted by a no-op request.
	assert bundle_grow_row(mut set, 9, 16384)
	outside := set
	assert !bundle_pool_grow(mut set, 3, 9, 16384, unsafe { &disk }) && set == outside
	set.plans[1].rows[0].offset = 0
	set.plans[1].rows[0].length = 4096
	outside_start := set
	assert !bundle_pool_grow(mut set, 3, 9, 8192, unsafe { &disk }) && set == outside_start
}

// Brute-force sectors independently determine whether growth has contiguous
// room in the member; aggregate capacity on another disk cannot bridge a hole.
fn test_pool_growth_matches_independent_sector_oracle_for_every_fragmentation_pattern() {
	for mask in 0 .. 128 {
		mut set := PlanSet{}
		mut plan := Plan{count: 1, key: DiskKey{bytes: 8192, sector: 512, kind: 1}}
		plan.key.id[0] = 1
		plan.rows[0] = Request{slot: 2, offset: 1024, length: 512, flags: u64(mask & 1)}
		for bit in 0 .. 7 {
			if mask & (1 << bit) == 0 { continue }
			plan.rows[plan.count] = Request{slot: u32(10 + bit), offset: u64(3 + bit) * 512, length: 512}
			plan.count++
		}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 1024, end: 5120, alignment: 1024}}
		assert bundle_pool_add(mut set, &region)
		for cells in 1 .. 10 {
			mut fits := cells <= 8
			for cell in 1 .. cells {
				if cell <= 7 && mask & (1 << (cell - 1)) != 0 { fits = false }
			}
			mut trial := set
			mut disk := u32(99)
			assert bundle_pool_grow(mut trial, 3, 2, u64(cells) * 512, unsafe { &disk }) == fits
			if fits {
				assert disk == 0 && trial.plans[0].rows[0].length == u64(cells) * 512
				assert trial.plans[0].rows[0].offset == 1024 && trial.plans[0].rows[0].flags == u64(mask & 1)
				assert trial.windows == set.windows && trial.slots == set.slots
			} else { assert trial == set && disk == 99 }
		}
	}
}

fn test_pool_growth_requires_capacity_adoption_preserves_full_tables_and_near_u64_bounds() {
	mut set := PlanSet{}
	mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~u64(511), sector: 512, kind: 1}}
	plan.key.id[0] = 1
	start := plan.key.bytes - 4096
	plan.rows[0] = Request{slot: 2, offset: start, length: 512}
	assert append_plan(mut set, &plan)
	region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: start, end: plan.key.bytes - 2048, alignment: 512}}
	assert bundle_pool_add(mut set, &region)
	before := set
	assert !bundle_pool_expand(mut set, 3, 0, u64(-1)) && set == before
	assert bundle_pool_expand(mut set, 3, 0, plan.key.bytes)
	mut disk := u32(99)
	assert bundle_pool_grow(mut set, 3, 2, 4096, unsafe { &disk })
	after := set
	assert !bundle_pool_grow(mut set, 3, 2, u64(-1), unsafe { &disk }) && set == after
	set = PlanSet{}
	plan = Plan{key: DiskKey{bytes: 65536, sector: 512, kind: 1}}
	plan.key.id[0] = 1
	assert append_plan(mut set, &plan)
	for pool in 0 .. 64 {
		member := PoolRegion{pool: u32(pool), disk: 0, window: SpaceWindow{start: u64(pool) * 512, end: u64(pool + 1) * 512, alignment: 512}}
		assert bundle_pool_add(mut set, &member)
	}
	assert bundle_pool_expand(mut set, 63, 0, 65536) && set.regions == 64
	full := set
	assert !bundle_pool_expand(mut set, 0, 0, 1024) && set == full
	mut small := PlanSet{}
	pool_growth_set(mut small)
	assert !bundle_pool_expand(mut small, 4, 0, 65536)
	mut observed := small.plans[0].key
	observed.bytes = 65536
	assert bundle_adopt_capacity(mut small, 0, &observed, 65536)
	assert bundle_pool_expand(mut small, 4, 0, 65536)
}

fn test_pool_growth_file_commands_republish_equal_size_and_refuse_bad_inputs_and_arguments() {
	work := os.join_path(os.temp_dir(), 'vinix-pool-growth-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/pool.vset'
	mut set := PlanSet{}
	pool_growth_set(mut set)
	assert publish_bundle(path.str, &set)
	assert grow_pool_plan(path.str, 3, 0, 12288, true) == 0
	expanded := os.read_bytes(path)!
	assert grow_pool_plan(path.str, 3, 0, 12288, true) == 0 && os.read_bytes(path)! == expanded
	assert grow_pool_plan(path.str, 3, 2, 8192, false) == 0
	grown := os.read_bytes(path)!
	assert grow_pool_plan(path.str, 3, 2, 8192, false) == 0 && os.read_bytes(path)! == grown
	assert grow_pool_plan(path.str, 3, 2, 12288, false) == 1 && os.read_bytes(path)! == grown
	os.symlink(path, work + '/link')!
	for input in [work + '/link', work + '/missing', work] {
		assert grow_pool_plan(input.str, 3, 0, 16384, true) == 1
		assert grow_pool_plan(input.str, 3, 2, 8192, false) == 1
	}
	mut broken := grown.clone()
	broken[24] ^= 1
	os.write_file_array(path, broken)!
	assert grow_pool_plan(path.str, 3, 0, 16384, true) == 1 && os.read_bytes(path)! == broken
	assert grow_pool_plan(path.str, 3, 2, 8192, false) == 1 && os.read_bytes(path)! == broken
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-expand'), &char(c'/unused'), &char(c'3'),
			&char(c'0'), &char(c'12288'), &char(nil)]!
		for command in [c'pool-expand', c'pool-grow'] {
			args[1] = &char(command)
			assert run(5, &args[0]) == 2 && run(7, &args[0]) == 2
			for index in [3, 4, 5] {
				previous := args[index]
				for bad in [c'', c'-1', c'1x', c'18446744073709551616'] {
					args[index] = &char(bad)
					assert run(6, &args[0]) == 2
				}
				args[index] = previous
			}
			args[5] = &char(c'0')
			assert run(6, &args[0]) == 2
			args[5] = &char(c'12288')
			for index in [3, 4] {
				previous := args[index]
				args[index] = &char(c'64')
				assert run(6, &args[0]) == 2
				args[index] = previous
			}
		}
	}
}
