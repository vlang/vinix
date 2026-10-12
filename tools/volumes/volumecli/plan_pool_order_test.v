// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn priority_fixture(mut set PlanSet, other_first bool, kind u32) {
	for disk in 0 .. 8 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 65536,
			sector: if disk & 1 == 0 { u64(512) } else { u64(4096) }, kind: if disk & 1 == 0 { kind } else { u32(3) - kind }}}
		plan.key.id[0] = u8(disk + 1)
		plan.rows[0] = Request{slot: u32(disk), offset: 8192, length: 4096, flags: u64(disk & 1)}
		assert append_plan(mut set, &plan)
	}
	for disk in [u32(3), 0, 5, 1, 4, 2] {
		member := PoolRegion{pool: 3, disk: disk, window: SpaceWindow{start: 16384, end: 32768 + u64(disk) * 4096, alignment: 4096}}
		other := PoolRegion{pool: 4, disk: disk, window: SpaceWindow{start: 0, end: 4096, alignment: 4096}}
		if other_first { assert bundle_pool_add(mut set, &other) }
		assert bundle_pool_add(mut set, &member)
		if !other_first { assert bundle_pool_add(mut set, &other) }
	}
	set.plans[63].key.id[0] = 99
	set.windows[63] = PoolRegion{pool: 62}
}

fn priority_permutations(baseline &PlanSet, mut order PoolOrder, depth int, used u64) int {
	if depth != 6 {
		mut attempts := 0
		for disk in 0 .. 6 {
			if used & (u64(1) << disk) != 0 { continue }
			order.disks[depth] = u32(disk)
			attempts += priority_permutations(baseline, mut order, depth + 1, used | (u64(1) << disk))
		}
		return attempts
	}
	mut set := unsafe { *baseline }
	mut expected := set
	mut at := 0
	for i in 0 .. expected.regions {
		if expected.windows[i].pool != 3 { continue }
		// Construct each expected row from its disk-specific fixture geometry,
		// independently of the production permutation planner.
		disk := order.disks[at]
		expected.windows[i] = PoolRegion{pool: 3, disk: disk, window: SpaceWindow{start: 16384, end: 32768 + u64(disk) * 4096, alignment: 4096}}
		at++
	}
	mut result := PoolOrderResults{}
	assert bundle_pool_order(mut set, 3, &order, mut result) && set == expected && result.count == 6
	source_order := [u32(3), 0, 5, 1, 4, 2]!
	for i in 0 .. 6 { assert source_order[result.previous[i]] == order.disks[i] }
	mut before_space := PoolSpace{}; mut after_space := PoolSpace{}
	assert bundle_pool_space(baseline, 3, mut before_space) && bundle_pool_space(&set, 3, mut after_space)
	assert before_space == after_space
	assert bundle_pool_order(mut set, 3, &order, mut result) && set == expected
	for i in 0 .. 6 { assert result.previous[i] == u32(i) }
	mut disk := u32(63)
	mut chosen := Request{}
	request := Request{slot: 63, length: 4096, flags: 1}
	assert bundle_pool_allocate(mut set, 3, &request, unsafe { &disk }, mut chosen)
	assert disk == order.disks[0] && chosen == Request{slot: 63, offset: 16384, length: 4096, flags: 1}
	return 1
}

fn test_every_six_member_permutation_preserves_bounds_other_pools_rows_and_changes_first_fit() {
	mut attempts := 0
	for other_first in [false, true] {
		for kind in [u32(1), 2] {
			mut baseline := PlanSet{}
			priority_fixture(mut baseline, other_first, kind)
			mut order := PoolOrder{count: 6}
			attempts += priority_permutations(&baseline, mut order, 0, 0)
		}
	}
	assert attempts == 2880
}

fn test_invalid_priority_lists_preserve_every_field_and_caller_results() {
	mut baseline := PlanSet{}
	priority_fixture(mut baseline, false, 1)
	mut good := PoolOrder{count: 6}
	for i in 0 .. 6 { good.disks[i] = u32(i) }
	for mode in 0 .. 10 {
		mut order := good; mut set := baseline; mut pool := u32(3)
		match mode {
			0 { order.count = -1 }
			1 { order.count = 0 }
			2 { order.count = 65 }
			3 { order.count = 5 }
			4 { order.disks[5] = 4 }
			5 { order.disks[5] = 6 }
			6 { order.disks[5] = 8 }
			7 { order.disks[5] = 64 }
			8 { pool = 5 }
			else { pool = 64 }
		}
		mut result := PoolOrderResults{count: 77}; result.previous[63] = 49
		previous := result
		assert !bundle_pool_order(mut set, pool, &order, mut result)
		assert set == baseline && result == previous
	}
	mut set := baseline; set.plans[1].rows[0].slot = 0
	invalid := set
	mut results := PoolOrderResults{count: 9}
	assert !bundle_pool_order(mut set, 3, &good, mut results)
	assert set == invalid && results == PoolOrderResults{count: 9}
}

fn test_maximum_priority_cli_previews_publishes_retries_and_roundtrips_all_64_members() {
	work := os.join_path(os.temp_dir(), 'vinix-priority-full-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	for disk in 0 .. 64 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~u64(4095), sector: 4096, kind: 1}}
		plan.key.id[0] = u8(disk + 1); plan.rows[0] = Request{slot: u32(disk), length: 4096, flags: u64(disk & 1)}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: plan.key.bytes - 8192, end: plan.key.bytes, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	unsafe {
		mut args := [69]&char{}; mut numbers := [64][4]char{}
		args[0] = &char(c'vinix-volume'); args[2] = path.str; args[3] = &char(c'3')
		for i in 0 .. 64 { C.snprintf(&numbers[i][0], 4, c'%u', u32(63 - i)); args[4 + i] = &numbers[i][0] }
		args[1] = &char(c'pool-preview-order'); assert run(68, &args[0]) == 0 && os.read_bytes(path)! == original
		args[1] = &char(c'pool-order'); assert run(68, &args[0]) == 0
		current := os.read_bytes(path)!
		mut decoded := PlanSet{}
		assert current.len == 8768 && decode_bundle(current.data, current.len, mut decoded)
		mut expected := set
		for i in 0 .. 64 { expected.windows[i] = set.windows[63 - i] }
		assert decoded == expected && current != original
		assert run(68, &args[0]) == 0 && os.read_bytes(path)! == current
	}
}

fn test_priority_cli_and_sources_reject_invalid_arguments_corruption_and_symlinks() {
	work := os.join_path(os.temp_dir(), 'vinix-priority-input-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}; priority_fixture(mut set, true, 2)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	os.symlink(path, work + '/link')!
	mut order := PoolOrder{count: 6}; for i in 0 .. 6 { order.disks[i] = u32(i) }
	for preview in [false, true] {
		for input in [work + '/link', work + '/missing', work] {
			assert order_pool_plan(input.str, 3, &order, preview) == 1 && os.read_bytes(path)! == original
		}
		os.write_file(path, 'invalid bundle')!
		assert order_pool_plan(path.str, 3, &order, preview) == 1 && os.read_file(path)! == 'invalid bundle'
		os.write_file_array(path, original)!
	}
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-order'), path.str, &char(c'3'), &char(c'0'), &char(nil)]!
		for command in [c'pool-order', c'pool-preview-order'] {
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
