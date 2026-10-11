// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn member_plan(id u64, slot int) Plan {
	mut plan := Plan{
		key: DiskKey{
			bytes:  16777216
			sector: 512
			kind:   1
		}
	}
	put_le(&plan.key.id[0], 0, 4, id)
	if slot >= 0 {
		plan.count = 1
		plan.rows[0] = Request{
			slot:   u32(slot)
			offset: 1048576
			length: 8192
			flags:  1
		}
	}
	return plan
}

fn test_enrollment_preserves_existing_desired_geometry_and_imports_a_whole_plan() {
	mut set := PlanSet{}
	first := member_plan(1, 2)
	assert append_plan(mut set, &first)
	second := member_plan(2, -1)
	assert bundle_enroll_disk(mut set, &second)
	mut third := member_plan(3, 9)
	third.count = 2
	third.rows[1] = Request{
		slot:   13
		offset: 2097152
		length: 4096
	}
	assert bundle_enroll_disk(mut set, &third)
	assert set.count == 3 && set.plans[0] == first && set.plans[1] == second
	assert set.plans[2] == third && set.slots == (u64(1) << 2) | (u64(1) << 9) | (u64(1) << 13)
	mut bytes := [6208]u8{}
	size := encode_bundle(&set, &bytes[0])
	mut decoded := PlanSet{}
	assert size == 352 && decode_bundle(&bytes[0], size, mut decoded)
	assert decoded.count == 3 && decoded.plans[0] == first && decoded.plans[2] == third
}

fn test_forgetting_empty_first_middle_last_members_preserves_order_slots_and_one_disk() {
	mut set := PlanSet{}
	for i in 0 .. 4 {
		plan := member_plan(u64(i + 1), if i == 2 { 12 } else { -1 })
		assert append_plan(mut set, &plan)
	}
	kept := set.plans[2]
	assert bundle_forget_disk(mut set, 1) && set.count == 3
	assert set.plans[0].key.id[0] == 1 && set.plans[1] == kept && set.plans[2].key.id[0] == 4
	assert set.plans[3] == Plan{} && set.slots == u64(1) << 12
	assert bundle_forget_disk(mut set, 0) && set.count == 2 && set.plans[0] == kept
	assert bundle_forget_disk(mut set, 1) && set.count == 1 && set.plans[0] == kept
	original := set
	assert !bundle_forget_disk(mut set, 0) && set == original
	assert bundle_remove_row(mut set, 12)
	empty := set
	assert !bundle_forget_disk(mut set, 0) && set == empty
	added := member_plan(5, -1)
	assert bundle_enroll_disk(mut set, &added) && bundle_forget_disk(mut set, 0)
	assert set.count == 1 && set.plans[0] == added && set.slots == 0
}

fn test_invalid_membership_edits_leave_all_fields_and_inactive_rows_unchanged() {
	mut set := PlanSet{}
	first := member_plan(1, 2)
	assert append_plan(mut set, &first)
	// Even inactive destination storage must survive a refused enrollment.
	set.plans[1] = member_plan(99, 63)
	original := set
	for failure in 0 .. 7 {
		mut plan := member_plan(2, 9)
		match failure {
			0 { plan.key = first.key }
			1 { plan.rows[0].slot = 2 }
			2 { plan.rows[0].length = 0 }
			3 { plan.rows[0].offset++ }
			4 { plan.count = 65 }
			5 { plan.key.id = [16]u8{} }
			else { plan.rows[0].version = 2 }
		}

		assert !bundle_enroll_disk(mut set, &plan) && set == original
	}
	for disk in [-1, 0, 1, 64] {
		assert !bundle_forget_disk(mut set, disk) && set == original
	}
	mut invalid := PlanSet{}
	plan := member_plan(2, -1)
	assert !bundle_enroll_disk(mut invalid, &plan) && invalid == PlanSet{}
	assert !bundle_forget_disk(mut invalid, 0) && invalid == PlanSet{}
}

fn test_maximum_disk_slot_and_format_bounds_survive_empty_removal_and_reenrollment() {
	mut set := PlanSet{}
	for i in 0 .. 64 {
		plan := member_plan(u64(i + 1), i)
		assert append_plan(mut set, &plan)
	}
	original := set
	new := member_plan(100, -1)
	assert !bundle_enroll_disk(mut set, &new) && set == original
	assert bundle_remove_row(mut set, 31) && bundle_forget_disk(mut set, 31)
	assert set.count == 63 && set.plans[31].key.id[0] == 33
	replacement := member_plan(100, 31)
	assert bundle_enroll_disk(mut set, &replacement) && set.count == 64 && set.slots == u64(-1)
	mut bytes := [6208]u8{}
	assert encode_bundle(&set, &bytes[0]) == 6208
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], 6208, mut decoded) && decoded.slots == u64(-1)
	assert decoded.plans[63] == replacement && decoded.plans[31].key.id[0] == 33
}

fn test_membership_file_edits_preserve_sources_and_fail_without_replacing_the_bundle() {
	work := os.join_path(os.temp_dir(), 'vinix-disk-plan-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	source := work + '/member.vmap'
	mut set := PlanSet{}
	first := member_plan(1, 2)
	assert append_plan(mut set, &first) && publish_bundle(path.str, &set)
	new := member_plan(2, -1)
	assert publish_plan(source.str, &new)
	original := os.read_bytes(path)!
	input := os.read_bytes(source)!
	assert enroll_bundle_disk(path.str, source.str) == 0 && os.read_bytes(source)! == input
	added := os.read_bytes(path)!
	mut decoded := PlanSet{}
	assert decode_bundle(added.data, added.len, mut decoded) && decoded.count == 2
	assert decoded.plans[0] == first && decoded.plans[1] == new
	assert enroll_bundle_disk(path.str, source.str) == 1 && os.read_bytes(path)! == added
	assert forget_bundle_disk(path.str, 0) == 1 && os.read_bytes(path)! == added
	assert forget_bundle_disk(path.str, 2) == 1 && os.read_bytes(path)! == added
	assert forget_bundle_disk(path.str, 1) == 0 && os.read_bytes(path)! == original
	assert forget_bundle_disk(path.str, 0) == 1 && os.read_bytes(path)! == original
	os.symlink(source, work + '/input-link')!
	os.symlink(path, work + '/bundle-link')!
	assert enroll_bundle_disk(path.str, (work + '/input-link').str) == 1
	assert enroll_bundle_disk((work + '/bundle-link').str, source.str) == 1
	assert forget_bundle_disk((work + '/bundle-link').str, 0) == 1
	assert enroll_bundle_disk(path.str, (work + '/missing').str) == 1
	assert enroll_bundle_disk(path.str, work.str) == 1
	assert enroll_bundle_disk(path.str, path.str) == 1
	mut damaged := input.clone()
	damaged[40] ^= 1
	os.write_file_array(source, damaged)!
	assert enroll_bundle_disk(path.str, source.str) == 1 && os.read_bytes(path)! == original
	os.write_file_array(path, damaged)!
	assert forget_bundle_disk(path.str, 0) == 1 && os.read_bytes(path)! == damaged
	assert enroll_bundle_disk(path.str, source.str) == 1 && os.read_bytes(path)! == damaged
	assert os.ls(work)!.len == 4 // Two inputs and two symlinks; no publication temporary.
}

fn test_membership_cli_rejects_argument_counts_and_bad_indices_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-enroll'), &char(c'/unused'),
			&char(c'/missing'), &char(nil)]!
		assert run(3, &args[0]) == 2 && run(5, &args[0]) == 2
		args[1] = &char(c'plan-forget')
		assert run(3, &args[0]) == 2 && run(5, &args[0]) == 2
		for bad in [c'-1', c'64', c'', c'18446744073709551616', c'1x'] {
			args[3] = &char(bad)
			assert run(4, &args[0]) == 2
		}
	}
}
