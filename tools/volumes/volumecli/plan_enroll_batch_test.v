// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn enrollment_member(member int, kind u32) Plan {
	mut plan := Plan{count: if member == 3 { u32(0) } else { u32(1 + (member & 1)) },
		key: DiskKey{bytes: 65536, sector: if member & 1 == 0 { u64(512) } else { u64(4096) },
			kind: if member & 1 == 0 { kind } else { u32(3) - kind }}}
	plan.key.id[0] = u8(member + 1)
	for row := u32(0); row < plan.count; row++ {
		plan.rows[row] = Request{slot: u32(member * 2) + row, offset: u64(row) * 8192,
			length: 4096, flags: u64(member & 1)}
	}
	return plan
}

fn enrollment_fixture(mut set PlanSet, mask u32, kind u32) {
	mut anchor := Plan{count: 1, key: DiskKey{bytes: 65536, sector: 4096, kind: 1}}
	anchor.key.id[0] = 100; anchor.rows[0] = Request{slot: 63, length: 8192, flags: 1}
	anchor.rows[63] = Request{slot: 61, length: 99}
	assert append_plan(mut set, &anchor)
	region := PoolRegion{pool: 4, disk: 0, window: SpaceWindow{start: 32768, end: 40960, alignment: 4096}}
	assert bundle_pool_add(mut set, &region)
	for member in [2, 0, 3, 1]! {
		if mask & (u32(1) << member) == 0 { continue }
		plan := enrollment_member(member, kind)
		at := set.count; assert append_plan(mut set, &plan)
		window := PoolRegion{pool: 3, disk: u32(at), window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}
		assert bundle_pool_add(mut set, &window)
	}
	set.plans[63].key.id[0] = 77; set.windows[63] = PoolRegion{pool: 62}
}

fn test_all_existing_and_requested_subsets_match_independent_append_keep_oracles() {
	mut attempts := 0
	for kind in [u32(1), 2] {
		for reverse in [false, true] {
			for existing in u32(0) .. 16 {
				for requested in u32(0) .. 16 {
					mut set := PlanSet{}; enrollment_fixture(mut set, existing, kind)
					original := set; mut expected := set
					mut batch := DiskEnrollmentBatch{}
					mut wanted := DiskEnrollmentResults{}
					for ordinal in 0 .. 4 {
						member := if reverse { 3 - ordinal } else { ordinal }
						if requested & (u32(1) << member) == 0 { continue }
						plan := enrollment_member(member, kind)
						at := batch.count; batch.plans[at] = plan; batch.count++
						mut found := -1
						for disk in 1 .. original.count { if original.plans[disk].key.id[0] == u8(member + 1) { found = disk } }
						if found < 0 {
							wanted.disks[at] = u32(expected.count); wanted.added |= u64(1) << at
							expected.plans[expected.count] = plan; expected.count++
							for row := u32(0); row < plan.count; row++ { expected.slots |= u64(1) << plan.rows[row].slot }
						} else { wanted.disks[at] = u32(found) }
					}
					mut results := DiskEnrollmentResults{count: 77, added: u64(-1)}; results.disks[63] = 55
					if requested == 0 {
						previous := results
						assert !bundle_enroll_batch(mut set, &batch, mut results) && set == original && results == previous
					} else {
						wanted.count = batch.count
						assert bundle_enroll_batch(mut set, &batch, mut results) && set == expected && results == wanted
						assert bundle_enroll_batch(mut set, &batch, mut results) && set == expected && results.added == 0
						assert results.disks == wanted.disks && results.count == wanted.count
					}
					attempts++
				}
			}
		}
	}
	assert attempts == 1024
}

fn test_later_identity_geometry_row_and_slot_conflicts_preserve_all_caller_state() {
	mut baseline := PlanSet{}; enrollment_fixture(mut baseline, 1, 1)
	for mode in 0 .. 11 {
		mut set := baseline
		mut batch := DiskEnrollmentBatch{count: 2}
		batch.plans[0] = enrollment_member(1, 1); batch.plans[1] = enrollment_member(0, 1)
		match mode {
			0 { batch.count = -1 }
			1 { batch.count = 0 }
			2 { batch.count = 65 }
			3 { batch.plans[1].key.bytes *= 2 }
			4 { batch.plans[1].key.sector = 4096 }
			5 { batch.plans[1].rows[0].flags = 1 }
			6 { batch.plans[1].rows[0].offset = 8192 }
			7 { batch.plans[1].count = 0 }
			8 { batch.plans[1] = batch.plans[0]; batch.plans[1].key.bytes *= 2 }
			9 { batch.plans[1] = enrollment_member(2, 1); batch.plans[1].rows[0].slot = 2 }
			else { batch.plans[1].rows[0].length = 0 }
		}
		mut results := DiskEnrollmentResults{count: 77, added: u64(-1)}; results.disks[63] = 55
		previous := results
		assert !bundle_enroll_batch(mut set, &batch, mut results) && set == baseline && results == previous
	}
	mut set := baseline
	mut alias := baseline.plans[0]; alias.count = 0; alias.key.bytes *= 2
	assert append_plan(mut set, &alias) // Old key equality includes geometry.
	ambiguous := set
	mut batch := DiskEnrollmentBatch{count: 1}; batch.plans[0] = enrollment_member(1, 1)
	mut result := DiskEnrollmentResults{count: 9}
	assert !bundle_enroll_batch(mut set, &batch, mut result) && set == ambiguous && result == DiskEnrollmentResults{count: 9}
	set = baseline; set.plans[1].rows[0].version = 2
	invalid := set
	assert !bundle_enroll_batch(mut set, &batch, mut result) && set == invalid
	mut ordered := PlanSet{}; enrollment_fixture(mut ordered, 2, 1)
	baseline_order := ordered
	batch.plans[0] = enrollment_member(2, 1); batch.plans[1] = enrollment_member(1, 1); batch.count = 2
	first_row := batch.plans[1].rows[0]
	batch.plans[1].rows[0] = batch.plans[1].rows[1]; batch.plans[1].rows[1] = first_row
	assert !bundle_enroll_batch(mut ordered, &batch, mut result) && ordered == baseline_order && result == DiskEnrollmentResults{count: 9}
}

fn test_maximum_cli_imports_64_sources_preserves_full_v2_pool_table_and_all_keep_priority() {
	work := os.join_path(os.temp_dir(), 'vinix-enrollment-full-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut sources := []string{cap: 64}
	mut batch := DiskEnrollmentBatch{count: 64}
	for disk in 0 .. 64 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~u64(4095),
			sector: if disk & 1 == 0 { u64(512) } else { u64(4096) }, kind: if disk & 1 == 0 { u32(1) } else { u32(2) }}}
		plan.key.id[0] = u8(disk + 1); plan.rows[0] = Request{slot: u32(disk), length: 4096, flags: u64(disk & 1)}
		batch.plans[disk] = plan
		source := work + '/disk-' + disk.str() + '.vmap'; sources << source
		assert publish_plan(source.str, &plan)
	}
	mut set := PlanSet{}; assert append_plan(mut set, &batch.plans[0])
	for pool in 0 .. 64 {
		end := set.plans[0].key.bytes - u64(pool) * 4096
		region := PoolRegion{pool: u32(pool), disk: 0, window: SpaceWindow{start: end - 4096, end: end, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!
	unsafe {
		mut args := [68]&char{}
		args[0] = &char(c'vinix-volume'); args[2] = path.str
		for i in 0 .. 64 { args[3 + i] = sources[63 - i].str }
		args[1] = &char(c'plan-preview-enroll-batch'); assert run(67, &args[0]) == 0 && os.read_bytes(path)! == original
		args[1] = &char(c'plan-enroll-batch'); assert run(67, &args[0]) == 0
		current := os.read_bytes(path)!
		mut decoded := PlanSet{}; assert current.len == 8768 && decode_bundle(current.data, current.len, mut decoded)
		mut expected := set; expected.count = 64; expected.slots = u64(-1)
		for disk in 1 .. 64 { expected.plans[disk] = batch.plans[64 - disk] }
		assert decoded == expected
		assert run(67, &args[0]) == 0 && os.read_bytes(path)! == current
		for disk in 0 .. 64 { assert os.read_bytes(sources[disk])!.len == 96 }
		mut overflow := DiskEnrollmentBatch{count: 2}; overflow.plans[0] = decoded.plans[31]
		overflow.plans[1] = Plan{key: DiskKey{bytes: 65536, sector: 4096, kind: 1}}; overflow.plans[1].key.id[0] = 100
		mut result := DiskEnrollmentResults{count: 9}; previous := decoded
		assert !bundle_enroll_batch(mut decoded, &overflow, mut result) && decoded == previous && result == DiskEnrollmentResults{count: 9}
	}
}

fn test_later_bad_source_alias_corruption_and_cli_counts_never_publish_a_prefix() {
	work := os.join_path(os.temp_dir(), 'vinix-enrollment-input-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; first := work + '/first.vmap'; second := work + '/second.vmap'
	mut set := PlanSet{}; enrollment_fixture(mut set, 0, 1)
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!
	plan := enrollment_member(0, 1); other := enrollment_member(1, 1)
	assert publish_plan(first.str, &plan) && publish_plan(second.str, &other)
	input := os.read_bytes(first)!
	os.symlink(first, work + '/alias')!
	unsafe {
		mut inputs := [first.str, second.str]!
		for preview in [false, true] {
			for bad in [(work + '/missing').str, work.str, path.str, (work + '/alias').str, first.str] {
				inputs[1] = bad
				assert enroll_batch_bundle_plan(path.str, 2, &inputs[0], preview) == 1 && os.read_bytes(path)! == original
			}
			inputs[1] = second.str; os.write_file(second, 'invalid plan')!
			assert enroll_batch_bundle_plan(path.str, 2, &inputs[0], preview) == 1 && os.read_bytes(path)! == original
			assert publish_plan(second.str, &other)
		}
		mut args := [&char(c'vinix-volume'), &char(c'plan-enroll-batch'), path.str, first.str, &char(c''), &char(nil)]!
		for command in [c'plan-enroll-batch', c'plan-preview-enroll-batch'] {
			args[1] = &char(command)
			for count in [2, 3, 68, 260] { assert run(count, &args[0]) == 2 }
			assert run(5, &args[0]) == 2 && os.read_bytes(path)! == original
		}
	}
	assert os.read_bytes(first)! == input
}
