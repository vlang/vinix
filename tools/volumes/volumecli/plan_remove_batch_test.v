// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn removal_fixture(mut set PlanSet, other_first bool, kind u32) {
	slots := [u32(4), 0, 7, 1, 8, 5, 6, 3, 2]!
	for disk in 0 .. 3 {
		mut plan := Plan{count: 3, key: DiskKey{bytes: 65536,
			sector: if disk & 1 == 0 { u64(512) } else { u64(4096) },
			kind: if disk & 1 == 0 { kind } else { u32(3) - kind }}}
		plan.key.id[0] = u8(disk + 1)
		for at in 0 .. 3 {
			slot := slots[disk * 3 + at]
			plan.rows[at] = Request{slot: slot, offset: u64(at * 8192),
				length: 4096 * (1 + u64(slot & 1)), flags: u64(slot & 1)}
		}
		plan.rows[63] = Request{slot: 61, length: 99}
		assert append_plan(mut set, &plan)
		member := PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: 32768, end: 40960 + u64(disk * 4096), alignment: 4096}}
		other := PoolRegion{pool: 4, disk: u32(disk), window: SpaceWindow{start: 49152, end: 57344, alignment: 4096}}
		if other_first { assert bundle_pool_add(mut set, &other) }
		assert bundle_pool_add(mut set, &member)
		if !other_first { assert bundle_pool_add(mut set, &other) }
	}
	set.plans[63].key.id[0] = 77
	set.windows[63] = PoolRegion{pool: 62}
}

fn removal_sequences(baseline &PlanSet, mut batch MappingRemovalBatch, depth int, used u64) int {
	mut attempts := 0
	if depth > 0 {
		mut request := batch; request.count = depth + 1; request.slots[depth] = 63
		mut set := unsafe { *baseline }; mut expected := set
		// Independent stable filtering oracle; never call the removal primitive.
		for disk in 0 .. expected.count {
			mut kept := u32(0)
			for at := u32(0); at < baseline.plans[disk].count; at++ {
				row := baseline.plans[disk].rows[at]
				if used & (u64(1) << row.slot) != 0 { continue }
				expected.plans[disk].rows[kept] = row; kept++
			}
			for at := kept; at < baseline.plans[disk].count; at++ { expected.plans[disk].rows[at] = Request{} }
			expected.plans[disk].count = kept
		}
		expected.slots &= ~used
		mut results := MappingRemovalResults{}
		assert bundle_remove_batch(mut set, &request, mut results) && set == expected
		assert results.count == depth + 1 && results.removed == (u64(1) << depth) - 1
		for i in 0 .. depth {
			assert results.rows[i].slot == request.slots[i]
			mut found := false
			for at := u32(0); at < baseline.plans[results.disks[i]].count; at++ {
				if baseline.plans[results.disks[i]].rows[at] == results.rows[i] { found = true }
			}
			assert found
		}
		assert bundle_remove_batch(mut set, &request, mut results) && set == expected
		assert results.count == depth + 1 && results.removed == 0
		attempts++
	}
	if depth == 6 { return attempts }
	for slot in 0 .. 6 {
		if used & (u64(1) << slot) != 0 { continue }
		batch.slots[depth] = u32(slot)
		attempts += removal_sequences(baseline, mut batch, depth + 1, used | (u64(1) << slot))
	}
	return attempts
}

fn test_every_ordered_subset_preserves_remaining_rows_pools_identities_and_absent_retries() {
	mut attempts := 0
	for other_first in [false, true] {
		for kind in [u32(1), 2] {
			mut set := PlanSet{}; removal_fixture(mut set, other_first, kind)
			mut batch := MappingRemovalBatch{}
			attempts += removal_sequences(&set, mut batch, 0, 0)
		}
	}
	assert attempts == 7824
}

fn test_invalid_later_removal_requests_and_invalid_source_preserve_all_caller_fields() {
	mut baseline := PlanSet{}; removal_fixture(mut baseline, true, 2)
	for mode in 0 .. 5 {
		mut set := baseline; mut batch := MappingRemovalBatch{count: 2}
		batch.slots[0] = 4; batch.slots[1] = 2
		match mode {
			0 { batch.count = -1 }
			1 { batch.count = 0 }
			2 { batch.count = 65 }
			3 { batch.slots[1] = 4 }
			else { batch.slots[1] = 64 }
		}
		mut results := MappingRemovalResults{count: 77, removed: u64(-1)}
		results.disks[63] = 49; results.rows[63] = Request{slot: 31}
		previous := results
		assert !bundle_remove_batch(mut set, &batch, mut results) && set == baseline && results == previous
	}
	mut set := baseline; set.plans[2].rows[0].slot = 4
	invalid := set
	mut batch := MappingRemovalBatch{count: 1}; batch.slots[0] = 4
	mut result := MappingRemovalResults{count: 9}
	assert !bundle_remove_batch(mut set, &batch, mut result)
	assert set == invalid && result == MappingRemovalResults{count: 9}
}

fn test_maximum_removal_cli_keeps_all_enrolled_disks_and_pool_order_and_reuses_freed_slots() {
	work := os.join_path(os.temp_dir(), 'vinix-removal-full-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for single in [false, true] {
		mut set := PlanSet{}
		for disk in 0 .. if single { 1 } else { 64 } {
			mut plan := Plan{count: if single { u32(64) } else { u32(1) },
				key: DiskKey{bytes: u64(-1) & ~u64(4095), sector: if disk & 1 == 0 { u64(512) } else { u64(4096) }, kind: 1}}
			plan.key.id[0] = u8(disk + 1)
			for at := u32(0); at < plan.count; at++ {
				plan.rows[at] = Request{slot: if single { at } else { u32(disk) }, offset: u64(at) * 8192, length: 4096, flags: u64(at & 1)}
			}
			assert append_plan(mut set, &plan)
			region := PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: plan.key.bytes - 8192, end: plan.key.bytes, alignment: 4096}}
			assert bundle_pool_add(mut set, &region)
		}
		assert publish_bundle(path.str, &set); original := os.read_bytes(path)!
		unsafe {
			mut args := [68]&char{}; mut numbers := [64][4]char{}
			args[0] = &char(c'vinix-volume'); args[2] = path.str
			for i in 0 .. 64 { C.snprintf(&numbers[i][0], 4, c'%u', u32(63 - i)); args[3 + i] = &numbers[i][0] }
			args[1] = &char(c'plan-preview-remove-batch'); assert run(67, &args[0]) == 0 && os.read_bytes(path)! == original
			args[1] = &char(c'plan-remove-batch'); assert run(67, &args[0]) == 0
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded)
			mut expected := set; expected.slots = 0
			for disk in 0 .. expected.count {
				for at := u32(0); at < expected.plans[disk].count; at++ { expected.plans[disk].rows[at] = Request{} }
				expected.plans[disk].count = 0
			}
			assert decoded == expected && current.len == 64 + expected.count * 64 + expected.regions * 40
			assert run(67, &args[0]) == 0 && os.read_bytes(path)! == current
			row := Request{slot: 63, offset: 8192, length: 4096, flags: 1}
			assert bundle_add_row(mut decoded, 0, &row) && decoded.slots == u64(1) << 63
		}
	}
}

fn test_removal_cli_sources_and_later_bad_numbers_never_publish_a_prefix() {
	work := os.join_path(os.temp_dir(), 'vinix-removal-input-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}; removal_fixture(mut set, false, 1)
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!
	os.symlink(path, work + '/link')!
	mut batch := MappingRemovalBatch{count: 2}; batch.slots[0] = 4; batch.slots[1] = 2
	for preview in [false, true] {
		for input in [work + '/link', work + '/missing', work] { assert remove_batch_bundle_plan(input.str, &batch, preview) == 1 }
		assert os.read_bytes(path)! == original
		os.write_file(path, 'invalid bundle')!
		assert remove_batch_bundle_plan(path.str, &batch, preview) == 1 && os.read_file(path)! == 'invalid bundle'
		os.write_file_array(path, original)!
	}
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-remove-batch'), path.str, &char(c'4'), &char(c'2'), &char(nil)]!
		for command in [c'plan-remove-batch', c'plan-preview-remove-batch'] {
			args[1] = &char(command)
			for count in [2, 3, 68, 260] { assert run(count, &args[0]) == 2 }
			for bad in [c'', c'-1', c'64', c'1x', c'18446744073709551616'] {
				args[4] = &char(bad); assert run(5, &args[0]) == 2 && os.read_bytes(path)! == original
			}
			args[4] = &char(c'4'); assert run(5, &args[0]) == 1 && os.read_bytes(path)! == original
		}
	}
}
